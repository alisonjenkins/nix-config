#![allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]

use cc_obs_ledger::otlp::{turn_payloads, Resource};
use cc_obs_ledger::transcript::{parse, ToolHasher};
use serde_json::Value;

const CONTEXT: &str = "cc_obs_ledger_context_tokens";
const T0: u64 = 1_767_225_600_000_000_000; // 2026-01-01T00:00:00Z

fn assistant(request: &str, timestamp: Option<&str>, input: u64) -> String {
    let ts = timestamp.map_or(String::new(), |t| format!(r#""timestamp":"{t}","#));
    format!(
        r#"{{"type":"assistant",{ts}"sessionId":"sess-1","requestId":"{request}","cwd":"/work/proj","isSidechain":false,"message":{{"id":"msg-{request}","role":"assistant","model":"m1","content":[{{"type":"text","text":"x"}}],"usage":{{"input_tokens":{input},"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}}}}"#
    )
}

fn user() -> &'static str {
    r#"{"type":"user","sessionId":"sess-1","cwd":"/work/proj","isSidechain":false,"message":{"role":"user","content":"hello"}}"#
}

/// (value, timeUnixNano) of every point of the named gauge, in payload order.
fn gauge_points(lines: &[String], name: &str) -> Vec<(u64, u64)> {
    let parsed = parse(&lines.join("\n"), &ToolHasher::new(b"k".to_vec()));
    turn_payloads(&Resource::new("h", &[]), &parsed)
        .iter()
        .filter_map(|p| p.body.pointer("/resourceMetrics/0/scopeMetrics/0/metrics"))
        .filter_map(Value::as_array)
        .flatten()
        .filter(|m| m["name"] == name)
        .flat_map(|m| m["gauge"]["dataPoints"].as_array().unwrap().clone())
        .map(|point| {
            (
                point["asInt"].as_str().unwrap().parse().unwrap(),
                point["timeUnixNano"].as_str().unwrap().parse().unwrap(),
            )
        })
        .collect()
}

#[test]
fn two_requests_in_a_turn_keep_their_own_transcript_timestamps() {
    let lines = [
        user().to_owned(),
        assistant("req-A", Some("2026-01-01T00:00:00.000Z"), 100),
        assistant("req-B", Some("2026-01-01T00:00:05.250Z"), 900),
    ];
    let points = gauge_points(&lines, CONTEXT);
    assert_eq!(
        points,
        vec![(100, T0), (900, T0 + 5_250_000_000)],
        "one gauge point per request, stamped with the request's own time"
    );
}

#[test]
fn requests_sharing_a_timestamp_get_distinct_increasing_nanoseconds() {
    let lines = [
        user().to_owned(),
        assistant("req-A", Some("2026-01-01T00:00:00.000Z"), 1),
        assistant("req-B", Some("2026-01-01T00:00:00.000Z"), 2),
        assistant("req-C", Some("2026-01-01T00:00:00.000Z"), 3),
    ];
    let times: Vec<u64> = gauge_points(&lines, CONTEXT)
        .into_iter()
        .map(|(_, t)| t)
        .collect();
    assert_eq!(times, vec![T0, T0 + 1, T0 + 2]);
}

#[test]
fn request_without_a_timestamp_falls_back_to_now_with_distinct_offsets() {
    let lines = [
        user().to_owned(),
        assistant("req-A", None, 1),
        assistant("req-B", None, 2),
    ];
    let points = gauge_points(&lines, CONTEXT);
    assert_eq!(points.len(), 2);
    assert!(
        points[0].1 > T0 && points[1].1 > points[0].1,
        "fallback times must be recent and strictly increasing: {points:?}"
    );
}
