// HTTP wrapper with exponential backoff. Retries on transport errors
// (connect/timeout) and on transient HTTP statuses (408, 429, 5xx).
// Non-transient errors (4xx other than 408/429) fail fast.
use anyhow::{anyhow, Result};
use std::io::Read;
use std::sync::OnceLock;
use std::thread;
use std::time::Duration;

fn agent() -> &'static ureq::Agent {
    static A: OnceLock<ureq::Agent> = OnceLock::new();
    A.get_or_init(|| {
        ureq::AgentBuilder::new()
            .timeout_connect(Duration::from_secs(15))
            .timeout_read(Duration::from_secs(60))
            .timeout_write(Duration::from_secs(30))
            .build()
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
        // cfwidget's WAF blocks the default ureq User-Agent; pretend to
        // be curl to get through. Modrinth + forgecdn don't care.
        let resp = agent().get(url).set("User-Agent", "curl/8").call();
        match resp {
            Ok(r) => {
                let mut buf = Vec::new();
                // 512 MiB cap is well above any single jar we'll see.
                if let Err(e) = r
                    .into_reader()
                    .take(512 * 1024 * 1024)
                    .read_to_end(&mut buf)
                {
                    last_err = Some(anyhow!("body read error: {}", e));
                    continue;
                }
                return Ok(buf);
            }
            Err(ureq::Error::Status(code, _)) if is_transient_status(code) => {
                last_err = Some(anyhow!("transient HTTP {}", code));
                continue;
            }
            Err(ureq::Error::Status(code, _)) => {
                // Permanent failure — surface immediately.
                return Err(anyhow!("HTTP {} (non-retriable) for {}", code, url));
            }
            Err(ureq::Error::Transport(t)) => {
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
