#![allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]

use cc_obs_ledger::otlp::{turn_payloads, Resource};
use cc_obs_ledger::transcript::{parse, ToolHasher};
use serde_json::Value;

const NAME: &str = "cc_obs_ledger_requests_total";

fn assistant(request: &str, model: &str, sidechain: bool, block: u32) -> String {
    format!(
        r#"{{"type":"assistant","sessionId":"sess-1","requestId":"{request}","cwd":"/work/proj","isSidechain":{sidechain},"message":{{"id":"msg-{request}","role":"assistant","model":"{model}","content":[{{"type":"text","text":"b{block}"}}],"usage":{{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":1,"cache_creation_input_tokens":1}}}}}}"#
    )
}

fn user() -> &'static str {
    r#"{"type":"user","sessionId":"sess-1","cwd":"/work/proj","isSidechain":false,"message":{"role":"user","content":"hello"}}"#
}

/// One prompt, a tool loop of three main requests (req-A streamed as three
/// lines, req-B as two), and one subagent request.
fn transcript() -> String {
    [
        user().to_owned(),
        assistant("req-A", "m1", false, 0),
        assistant("req-A", "m1", false, 1),
        assistant("req-A", "m1", false, 2),
        assistant("req-B", "m1", false, 0),
        assistant("req-B", "m1", false, 1),
        assistant("req-C", "m1", false, 0),
        assistant("req-S", "m2", true, 0),
    ]
    .join("\n")
}

fn points(text: &str) -> (Value, Vec<Value>) {
    let parsed = parse(text, &ToolHasher::new(b"k".to_vec()));
    let payloads = turn_payloads(&Resource::new("h", &[]), &parsed);
    let metric = payloads
        .iter()
        .filter_map(|p| p.body.pointer("/resourceMetrics/0/scopeMetrics/0/metrics"))
        .filter_map(Value::as_array)
        .flatten()
        .find(|m| m["name"] == NAME)
        .expect("no cc_obs_ledger_requests_total metric sent")
        .clone();
    let data = metric["sum"]["dataPoints"].as_array().unwrap().clone();
    (metric, data)
}

fn attr(point: &Value, key: &str) -> String {
    point["attributes"]
        .as_array()
        .unwrap()
        .iter()
        .find(|a| a["key"] == key)
        .map(|a| a["value"]["stringValue"].as_str().unwrap().to_owned())
        .unwrap_or_default()
}

#[test]
fn a_request_streamed_over_several_lines_counts_once() {
    let (_, data) = points(&transcript());
    let main = data
        .iter()
        .find(|p| attr(p, "agent") == "main")
        .expect("main point");
    assert_eq!(main["asInt"], "3", "{data:?}");
}

#[test]
fn counts_are_split_by_model_and_agent() {
    let (_, data) = points(&transcript());
    let sub = data
        .iter()
        .find(|p| attr(p, "agent") == "subagent")
        .expect("subagent point");
    assert_eq!(sub["asInt"], "1");
    assert_eq!(attr(sub, "model"), "m2");
    assert_eq!(attr(sub, "session.id"), "sess-1");
    assert_eq!(attr(sub, "project"), "proj");
    assert_eq!(data.len(), 2);
}

#[test]
fn the_counter_is_a_cumulative_monotonic_sum_without_a_per_request_label() {
    let (metric, data) = points(&transcript());
    assert_eq!(metric["sum"]["isMonotonic"], true);
    assert_eq!(metric["sum"]["aggregationTemporality"], 2);
    for point in &data {
        for key in ["turn", "request_id", "request.id"] {
            assert!(
                point["attributes"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .all(|a| a["key"] != key),
                "label {key} would make one series per request"
            );
        }
    }
}
