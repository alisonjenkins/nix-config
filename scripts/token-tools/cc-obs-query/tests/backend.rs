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

use cc_obs_query::backend::{Backend, Endpoints, LogFetch};
use cc_obs_query::error::Error;
use cc_obs_query::window;
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

#[test]
fn a_400_with_a_json_error_body_reaches_backend_rejected() {
    let base = serve_fn(|_| {
        (
            400,
            r#"{"status":"error","errorType":"bad_data","error":"parse error: unexpected end of input"}"#
                .to_owned(),
        )
    });
    let error = backend(&base).prom_instant("sum(", None).unwrap_err();
    assert!(
        matches!(&error, Error::BackendRejected { detail, .. }
            if detail.contains("unexpected end of input")),
        "{error:?}"
    );
}

#[test]
fn a_5xx_with_a_plain_text_body_keeps_the_text() {
    let base = serve_fn(|_| (500, "too many outstanding requests".to_owned()));
    let error = backend(&base)
        .loki_range("{a=\"b\"}", 0, 1, 10)
        .unwrap_err();
    assert!(
        matches!(&error, Error::BackendRejected { status, detail, .. }
            if status == "HTTP 500" && detail.contains("too many outstanding")),
        "{error:?}"
    );
}

#[test]
fn readiness_is_false_on_a_non_2xx() {
    let base = serve_fn(|_| (503, "not ready".to_owned()));
    assert!(!backend(&base).ready(cc_obs_query::backend::Store::Loki));
}

/// A Loki that behaves like the real one for paging: forward order, inclusive
/// `start`, at most `limit` entries. `events` are `(ts_ns, line)`.
fn paging_loki(events: Vec<(i64, String)>) -> String {
    serve_fn(move |target| {
        let num = |name: &str, default: i64| {
            param(target, name)
                .and_then(|v| v.parse().ok())
                .unwrap_or(default)
        };
        let (start, end, limit) = (num("start", 0), num("end", i64::MAX), num("limit", 100));
        let values = events
            .iter()
            .filter(|(ts, _)| *ts >= start && *ts <= end)
            .take(usize::try_from(limit).unwrap())
            .map(|(ts, line)| json!([ts.to_string(), line]))
            .collect();
        (200, loki_body(values))
    })
}

#[test]
fn prom_instant_drops_non_finite_samples() {
    let body = json!({"status": "success", "data": {"resultType": "vector", "result": [
        {"metric": {"k": "nan"}, "value": [1, "NaN"]},
        {"metric": {"k": "inf"}, "value": [1, "+Inf"]},
        {"metric": {"k": "ok"}, "value": [1, "2.5"]},
    ]}})
    .to_string();
    let base = serve_fn(move |_| (200, body.clone()));
    let samples = backend(&base).prom_instant("m", None).unwrap();
    assert_eq!(samples.len(), 1);
    assert_eq!(samples[0].labels["k"], "ok");
}

#[test]
fn since_with_a_multibyte_unit_is_an_error_not_a_panic() {
    for text in ["7é", "é", "7日", "日日"] {
        assert!(window::parse_since(text).is_err(), "{text}");
    }
}

#[test]
fn since_that_overflows_is_an_error() {
    assert!(window::parse_since("99999999999999999w").is_err());
    assert!(window::parse_since("99999999999999999999999d").is_err());
}

#[test]
fn a_huge_but_representable_since_does_not_panic() {
    let w = window::parse_since("9999999999999w").unwrap();
    let _ = (w.start_unix(), w.end_unix(), w.prom());
}

#[test]
fn range_with_equal_dates_is_rejected() {
    assert!(window::parse_range("--a", "2026-09-01..2026-09-01").is_err());
}

#[test]
fn dates_without_zero_padding_are_accepted() {
    assert_eq!(
        window::parse_until("2026-9-1").unwrap(),
        window::parse_until("2026-09-01").unwrap()
    );
}

fn param(target: &str, name: &str) -> Option<String> {
    let query = target.split_once('?')?.1;
    query
        .split('&')
        .find_map(|kv| kv.strip_prefix(&format!("{name}=")).map(str::to_owned))
}

fn line(tag: &str) -> String {
    json!({ "tag": tag }).to_string()
}

fn fetch(page_size: usize, max_pages: usize) -> LogFetch {
    LogFetch {
        page_size,
        max_records: 1000,
        max_pages,
    }
}

fn tags(pages: &cc_obs_query::backend::LogPages) -> Vec<String> {
    pages
        .records
        .iter()
        .map(|r| r.fields["tag"].clone())
        .collect()
}

#[test]
fn paging_drops_the_repeat_of_the_last_record_on_the_next_page() {
    let base = paging_loki(
        ["a", "b", "c", "d"]
            .iter()
            .zip([100, 200, 300, 400])
            .map(|(tag, ts)| (ts, line(tag)))
            .collect(),
    );
    let pages = backend(&base)
        .loki_paged("{x=\"y\"}", 0, 1000, fetch(3, 10))
        .unwrap();
    assert_eq!(tags(&pages), ["a", "b", "c", "d"]);
    assert!(!pages.truncated && pages.gaps.is_empty());
}

#[test]
fn a_page_of_one_timestamp_is_reported_as_a_gap_not_looped() {
    let events = (0..5).map(|i| (100, line(&format!("e{i}")))).collect();
    let base = paging_loki(events);
    let pages = backend(&base)
        .loki_paged("{x=\"y\"}", 0, 1000, fetch(2, 10))
        .unwrap();
    assert_eq!(pages.gaps.len(), 1, "{:?}", pages.gaps);
    assert!(pages.gaps[0].contains("share timestamp 100"));
    assert_eq!(pages.records.len(), 2);
}

#[test]
fn max_pages_marks_the_fetch_truncated() {
    let events = (1..=6).map(|i| (i * 100, line(&format!("e{i}")))).collect();
    let base = paging_loki(events);
    let pages = backend(&base)
        .loki_paged("{x=\"y\"}", 0, 1000, fetch(2, 2))
        .unwrap();
    assert!(pages.truncated);
    assert_eq!(tags(&pages), ["e1", "e2", "e3"]);
}

#[test]
fn identical_events_cut_by_a_page_boundary_lose_one_but_are_flagged() {
    // Known limit, pinned: three byte-identical events at ts 100 and a page cut
    // after two. Loki's start is inclusive and has no offset, so the next page
    // returns the same two events; they are indistinguishable from the kept
    // ones, the third is unreachable, and the paging reports it as a gap.
    let events = vec![
        (100, line("same")),
        (100, line("same")),
        (100, line("same")),
        (200, line("later")),
    ];
    let base = paging_loki(events);
    let pages = backend(&base)
        .loki_paged("{x=\"y\"}", 0, 1000, fetch(2, 10))
        .unwrap();
    assert_eq!(tags(&pages), ["same", "same", "later"]);
    assert_eq!(pages.gaps.len(), 1, "the loss must not be silent");
}
