#![allow(
    dead_code,
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects,
    clippy::panic
)]

use std::fs;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use serde_json::Value;

pub struct Fake {
    pub base: String,
    seen: Arc<Mutex<Vec<String>>>,
}

impl Fake {
    pub fn seen(&self) -> Vec<String> {
        self.seen.lock().unwrap().clone()
    }

    pub fn seen_matching(&self, needle: &str) -> Vec<String> {
        self.seen()
            .into_iter()
            .filter(|s| s.contains(needle))
            .collect()
    }
}

pub fn fixture(name: &str) -> String {
    fs::read_to_string(
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures")
            .join(name),
    )
    .unwrap()
}

fn percent_decode(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while let Some(&b) = bytes.get(i) {
        if b == b'%' {
            let hex = text.get(i + 1..i + 3).unwrap_or("");
            if let Ok(v) = u8::from_str_radix(hex, 16) {
                out.push(v);
                i += 3;
                continue;
            }
        }
        out.push(if b == b'+' { b' ' } else { b });
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// First rule whose needle is contained in the decoded request target wins; no
/// match answers 404.
pub fn serve(rules: Vec<(&str, String)>) -> Fake {
    let rules: Vec<(String, String)> = rules.into_iter().map(|(n, b)| (n.to_owned(), b)).collect();
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let seen = Arc::new(Mutex::new(Vec::new()));
    let seen_in = Arc::clone(&seen);
    thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { continue };
            stream
                .set_read_timeout(Some(Duration::from_secs(2)))
                .unwrap();
            let mut buf = Vec::new();
            let mut chunk = [0u8; 4096];
            while !buf.windows(4).any(|w| w == b"\r\n\r\n") {
                match stream.read(&mut chunk) {
                    Ok(0) | Err(_) => break,
                    Ok(n) => buf.extend_from_slice(&chunk[..n]),
                }
            }
            let text = String::from_utf8_lossy(&buf).into_owned();
            let target = percent_decode(text.split_whitespace().nth(1).unwrap_or(""));
            seen_in.lock().unwrap().push(target.clone());
            let hit = rules.iter().find(|(needle, _)| target.contains(needle));
            let (status, body) = match hit {
                Some((_, body)) => ("200 OK", body.as_str()),
                None => (
                    "404 Not Found",
                    r#"{"status":"error","error":"no fixture"}"#,
                ),
            };
            let reply = format!(
                "HTTP/1.1 {status}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            );
            let _ = stream.write_all(reply.as_bytes());
        }
    });
    Fake { base, seen }
}

pub fn endpoints_json(base: &str) -> String {
    serde_json::json!({
        "host": "test-host",
        "urls": {
            "grafana": format!("{base}/grafana"),
            "loki": format!("{base}/loki"),
            "tempo": format!("{base}/tempo"),
            "prometheus": format!("{base}/prom"),
            "otlpHttp": base,
        },
        "ports": {}
    })
    .to_string()
}

pub fn endpoints_file(base: &str) -> (tempfile::TempDir, PathBuf) {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("endpoints.json");
    fs::write(&path, endpoints_json(base)).unwrap();
    (dir, path)
}

pub struct Run {
    pub code: i32,
    pub out: String,
    pub err: String,
}

impl Run {
    pub fn json(&self) -> Value {
        serde_json::from_str(&self.out)
            .unwrap_or_else(|e| panic!("stdout is not JSON ({e}): {}", self.out))
    }

    pub fn err_json(&self) -> Value {
        serde_json::from_str(&self.err)
            .unwrap_or_else(|e| panic!("stderr is not JSON ({e}): {}", self.err))
    }
}

pub fn cli(fake: &Fake, args: &[&str]) -> Run {
    let (_dir, path) = endpoints_file(&fake.base);
    cli_with(&path, args)
}

pub fn cli_with(endpoints: &Path, args: &[&str]) -> Run {
    let output = Command::new(env!("CARGO_BIN_EXE_cc-obs-query"))
        .args(args)
        .env("CC_OBS_ENDPOINTS", endpoints)
        .env_remove("XDG_CONFIG_HOME")
        .output()
        .unwrap();
    Run {
        code: output.status.code().unwrap_or(-1),
        out: String::from_utf8_lossy(&output.stdout).into_owned(),
        err: String::from_utf8_lossy(&output.stderr).into_owned(),
    }
}

pub fn rows(value: &Value) -> &Vec<Value> {
    value["rows"].as_array().unwrap()
}

pub fn row<'a>(value: &'a Value, key: &str) -> &'a Value {
    rows(value)
        .iter()
        .find(|r| r["key"] == key)
        .unwrap_or_else(|| panic!("no row {key} in {value}"))
}

pub const TOOL_PACK: &str = r#"version: 1
regrowth_factor: 1.5
retire: []
questions:
  - id: tool-result-size
    title: Which tools return the most tokens per use?
    signals: [claude_code.token.usage, claude_code.tool_result.tool_result_size_bytes]
    query: { command: "cc-obs-query top tool --by tokens" }
    decision_kind: build-tool | configure | dismiss
    threshold: { min_share: 0.03, min_calls: 1 }
"#;

pub fn digest_rules(loki_body: String) -> Vec<(&'static str, String)> {
    let ready = "ready".to_owned();
    vec![
        (
            "claude_code_token_usage_tokens_total{review_run=\"1\"",
            fixture("prom_scalar_review_tokens.json"),
        ),
        (
            "claude_code_cost_usage_USD_total{review_run=\"1\"}",
            fixture("prom_scalar_review_cost.json"),
        ),
        (
            "sum(increase(claude_code_token_usage_tokens_total",
            fixture("prom_scalar_total_tokens.json"),
        ),
        (
            "sum(increase(claude_code_cost_usage_USD_total",
            fixture("prom_scalar_total_cost.json"),
        ),
        (
            "count(sum by (session_id)",
            fixture("prom_scalar_sessions.json"),
        ),
        ("by (session_id)", fixture("prom_tokens_by_session.json")),
        ("event_name=\"tool_result\"", loki_body),
        ("/prom/-/ready", ready.clone()),
        ("/loki/ready", ready.clone()),
        ("/tempo/ready", ready),
        (
            "observability_guard_over_budget",
            fixture("prom_guard_ok.json"),
        ),
    ]
}

pub fn own_cost_rules() -> Vec<(&'static str, String)> {
    vec![
        (
            "claude_code_token_usage_tokens_total{review_run=\"1\"",
            fixture("prom_scalar_review_tokens.json"),
        ),
        (
            "claude_code_cost_usage_USD_total{review_run=\"1\"}",
            fixture("prom_scalar_review_cost.json"),
        ),
    ]
}

pub fn with_own(mut rules: Vec<(&'static str, String)>) -> Vec<(&'static str, String)> {
    rules.extend(own_cost_rules());
    rules
}

pub fn write_pack(dir: &Path, yaml: &str) -> PathBuf {
    let path = dir.join("questions.yaml");
    fs::write(&path, yaml).unwrap();
    path
}

pub fn s(path: &Path) -> &str {
    path.to_str().unwrap()
}
