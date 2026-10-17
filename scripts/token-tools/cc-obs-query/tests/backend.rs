#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]

mod common;

use std::io::{Read, Write};
use std::net::TcpListener;
use std::thread;
use std::time::Duration;

use cc_obs_query::backend::{Backend, Endpoints};
use serde_json::{json, Value};

/// A one-handler HTTP server: `handler` gets the percent-decoded request target
/// and answers `(status, body)`. Returns the base URL.
fn serve_fn(handler: impl Fn(&str) -> (u16, String) + Send + 'static) -> String {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
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
            let target = decode(text.split_whitespace().nth(1).unwrap_or(""));
            let (status, body) = handler(&target);
            let reply = format!(
                "HTTP/1.1 {status} X\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                body.len()
            );
            let _ = stream.write_all(reply.as_bytes());
            let _ = stream.write_all(body.as_bytes());
        }
    });
    base
}

fn decode(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while let Some(&b) = bytes.get(i) {
        if b == b'%' {
            if let Ok(v) = u8::from_str_radix(text.get(i + 1..i + 3).unwrap_or(""), 16) {
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

fn backend(base: &str) -> Backend {
    Backend::new(serde_json::from_str::<Endpoints>(&common::endpoints_json(base)).unwrap())
}

fn loki_body(values: Vec<Value>) -> String {
    json!({"status": "success", "data": {"resultType": "streams",
        "result": [{"stream": {"service_name": "s"}, "values": values}]}})
    .to_string()
}

#[test]
fn body_over_the_read_cap_names_the_cap() {
    let body = format!("{{\"pad\":\"{}\"}}", "x".repeat(65 * 1024 * 1024));
    let base = serve_fn(move |_| (200, body.clone()));
    let error = backend(&base).tempo_trace("abc").unwrap_err();
    assert!(error.to_string().contains("64 MiB"), "{error}");
}

#[test]
fn loki_page_over_10mib_is_read_or_reports_cap() {
    let line = serde_json::to_string(&json!({"k": "x".repeat(2200)})).unwrap();
    let values: Vec<Value> = (0..5000)
        .map(|i| json!([(1_000_000 + i).to_string(), line]))
        .collect();
    let body = loki_body(values);
    assert!(body.len() > 10 * 1024 * 1024, "fixture must exceed 10 MiB");
    let base = serve_fn(move |_| (200, body.clone()));
    match backend(&base).loki_range("{a=\"b\"}", 0, i64::MAX, 5000) {
        Ok(records) => assert_eq!(records.len(), 5000),
        Err(error) => assert!(
            error.to_string().contains("MiB"),
            "error must name the size cap: {error}"
        ),
    }
}
