// HTTP wrapper with exponential backoff. Retries on transport errors
// (connect/timeout) and on transient HTTP statuses (408, 429, 5xx).
// Non-transient errors (4xx other than 408/429) fail fast.
use anyhow::{anyhow, Result};
use std::sync::OnceLock;
use std::thread;
use std::time::Duration;

// ureq 3 has no per-read timeout; bound the whole body so a stalled
// download cannot hang forever while still allowing a large jar.
const BODY_TIMEOUT: Duration = Duration::from_secs(600);

fn agent() -> &'static ureq::Agent {
    static A: OnceLock<ureq::Agent> = OnceLock::new();
    A.get_or_init(|| {
        ureq::Agent::config_builder()
            .timeout_connect(Some(Duration::from_secs(15)))
            .timeout_recv_response(Some(Duration::from_secs(60)))
            .timeout_recv_body(Some(BODY_TIMEOUT))
            .timeout_send_body(Some(Duration::from_secs(30)))
            // cfwidget's WAF blocks the default ureq User-Agent; pretend to
            // be curl to get through. Modrinth + forgecdn don't care.
            .user_agent("curl/8")
            .build()
            .into()
    })
}

/// Classify an HTTP status code as transient (retriable) or terminal.
pub fn is_transient_status(code: u16) -> bool {
    code == 408 || code == 425 || code == 429 || (500..=599).contains(&code)
}

#[derive(Debug)]
pub struct RetryConfig {
    pub max_attempts: u32,
    pub base_delay: Duration,
    pub max_delay: Duration,
}

impl Default for RetryConfig {
    fn default() -> Self {
        Self {
            max_attempts: 5,
            base_delay: Duration::from_millis(500),
            max_delay: Duration::from_secs(30),
        }
    }
}

/// Compute backoff for attempt `n` (0-indexed). Doubles each step, capped
/// at `cfg.max_delay`. Deterministic — tests assert on the schedule.
pub fn backoff_for(cfg: &RetryConfig, attempt: u32) -> Duration {
    let factor = 1u64 << attempt.min(20);
    let dur = cfg.base_delay.saturating_mul(factor as u32);
    dur.min(cfg.max_delay)
}

/// GET `url` with retries. Returns body bytes on success.
pub fn http_get(url: &str) -> Result<Vec<u8>> {
    http_get_with(url, &RetryConfig::default())
}

pub fn http_get_with(url: &str, cfg: &RetryConfig) -> Result<Vec<u8>> {
    let mut last_err: Option<anyhow::Error> = None;
    for attempt in 0..cfg.max_attempts {
        if attempt > 0 {
            let delay = backoff_for(cfg, attempt - 1);
            eprintln!(
                "  http retry {}/{} (sleep {:.1}s): {}",
                attempt,
                cfg.max_attempts - 1,
                delay.as_secs_f32(),
                url
            );
            thread::sleep(delay);
        }
        let resp = agent().get(url).call();
        match resp {
            Ok(mut r) => {
                // 512 MiB cap is well above any single jar we'll see.
                match r
                    .body_mut()
                    .with_config()
                    .limit(512 * 1024 * 1024)
                    .read_to_vec()
                {
                    Ok(buf) => return Ok(buf),
                    Err(e) => {
                        last_err = Some(anyhow!("body read error: {}", e));
                        continue;
                    }
                }
            }
            Err(ureq::Error::StatusCode(code)) if is_transient_status(code) => {
                last_err = Some(anyhow!("transient HTTP {}", code));
                continue;
            }
            Err(ureq::Error::StatusCode(code)) => {
                // Permanent failure — surface immediately.
                return Err(anyhow!("HTTP {} (non-retriable) for {}", code, url));
            }
            Err(t) => {
                last_err = Some(anyhow!("transport error: {}", t));
                continue;
            }
        }
    }
    Err(last_err.unwrap_or_else(|| anyhow!("retries exhausted for {}", url)))
}

#[cfg(test)]
mod tests {
    use super::*;

    use std::io::{Read, Write};
    use std::net::TcpListener;

    /// Serve `responses` one connection each; returns the base URL and a
    /// handle yielding the raw requests received.
    fn serve(responses: Vec<&'static str>) -> (String, thread::JoinHandle<Vec<String>>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}/", listener.local_addr().unwrap());
        let h = thread::spawn(move || {
            let mut seen = Vec::new();
            for resp in responses {
                let (mut s, _) = listener.accept().unwrap();
                let mut buf = [0u8; 4096];
                let n = s.read(&mut buf).unwrap();
                seen.push(String::from_utf8_lossy(&buf[..n]).into_owned());
                s.write_all(resp.as_bytes()).unwrap();
            }
            seen
        });
        (url, h)
    }

    fn fast_cfg() -> RetryConfig {
        RetryConfig {
            max_attempts: 3,
            base_delay: Duration::from_millis(1),
            max_delay: Duration::from_millis(1),
        }
    }

    #[test]
    fn get_returns_body_and_sends_curl_user_agent() {
        let (url, h) = serve(vec![
            "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nhi",
        ]);
        let body = http_get_with(&url, &fast_cfg()).unwrap();
        assert_eq!(body, b"hi");
        let req = h.join().unwrap().remove(0).to_lowercase();
        assert!(req.contains("user-agent: curl/8"), "{req}");
    }

    #[test]
    fn terminal_status_fails_without_retry() {
        let (url, h) = serve(vec![
            "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
        ]);
        let err = http_get_with(&url, &fast_cfg()).unwrap_err().to_string();
        assert!(err.contains("HTTP 404"), "{err}");
        assert_eq!(h.join().unwrap().len(), 1);
    }

    #[test]
    fn transient_status_is_retried_then_succeeds() {
        let (url, h) = serve(vec![
            "HTTP/1.1 503 Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
            "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok",
        ]);
        let body = http_get_with(&url, &fast_cfg()).unwrap();
        assert_eq!(body, b"ok");
        assert_eq!(h.join().unwrap().len(), 2);
    }

    #[test]
    fn classifies_transient_statuses() {
        assert!(is_transient_status(500));
        assert!(is_transient_status(502));
        assert!(is_transient_status(503));
        assert!(is_transient_status(504));
        assert!(is_transient_status(599));
        assert!(is_transient_status(408));
        assert!(is_transient_status(425));
        assert!(is_transient_status(429));
    }

    #[test]
    fn classifies_terminal_statuses() {
        assert!(!is_transient_status(400));
        assert!(!is_transient_status(401));
        assert!(!is_transient_status(403));
        assert!(!is_transient_status(404));
        assert!(!is_transient_status(410));
    }

    #[test]
    fn backoff_doubles_and_caps() {
        let cfg = RetryConfig {
            max_attempts: 10,
            base_delay: Duration::from_millis(500),
            max_delay: Duration::from_secs(8),
        };
        assert_eq!(backoff_for(&cfg, 0), Duration::from_millis(500));
        assert_eq!(backoff_for(&cfg, 1), Duration::from_millis(1000));
        assert_eq!(backoff_for(&cfg, 2), Duration::from_millis(2000));
        assert_eq!(backoff_for(&cfg, 3), Duration::from_millis(4000));
        // Doubles to 8s, then caps.
        assert_eq!(backoff_for(&cfg, 4), Duration::from_secs(8));
        assert_eq!(backoff_for(&cfg, 9), Duration::from_secs(8));
    }
}
