#![allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]

use cc_obs_ledger::otlp::{turn_payloads, Resource};
use cc_obs_ledger::transcript::{parse_from, Position, ToolHasher};
use serde_json::Value;

const NAME: &str = "cc_obs_ledger_requests_total";
const CUMULATIVE: u64 = 2;

fn assistant(request: &str, sidechain: bool) -> String {
    format!(
        r#"{{"type":"assistant","sessionId":"sess-1","requestId":"{request}","cwd":"/work/proj","isSidechain":{sidechain},"message":{{"id":"msg-{request}","role":"assistant","model":"m1","content":[{{"type":"text","text":"x"}}],"usage":{{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":1,"cache_creation_input_tokens":1}}}}}}"#
    )
}

fn lines(ids: &[&str], sidechain: bool) -> String {
    ids.iter()
        .map(|id| assistant(id, sidechain))
        .collect::<Vec<_>>()
        .join("\n")
}

/// One Stop: parse from `start`, return the counter's data points and where it ended.
fn stop(text: &str, start: Position, agent_id: Option<&str>) -> (Value, Vec<Value>, Position) {
    let mut parsed = parse_from(text, &ToolHasher::new(b"k".to_vec()), start);
    if let Some(id) = agent_id {
        parsed.set_agent_id(id);
    }
    let payloads = turn_payloads(&Resource::new("h", &[]), &parsed);
    let metric = payloads
        .iter()
        .filter_map(|p| p.body.pointer("/resourceMetrics/0/scopeMetrics/0/metrics"))
        .filter_map(Value::as_array)
        .flatten()
        .find(|m| m["name"] == NAME)
        .expect("no counter sent")
        .clone();
    let data = metric["sum"]["dataPoints"].as_array().unwrap().clone();
    (metric, data, parsed.end)
}

#[test]
fn one_stop_sends_a_cumulative_sum_with_a_fixed_start_time() {
    let (metric, data, _) = stop(&lines(&["a", "b"], false), Position::default(), None);
    assert_eq!(metric["sum"]["aggregationTemporality"], CUMULATIVE);
    assert_eq!(metric["sum"]["isMonotonic"], true);
    assert_eq!(data.len(), 1);
    assert_eq!(data[0]["asInt"], "2");
    let start: u64 = data[0]["startTimeUnixNano"]
        .as_str()
        .unwrap()
        .parse()
        .unwrap();
    let time: u64 = data[0]["timeUnixNano"].as_str().unwrap().parse().unwrap();
    assert!(start > 0 && start <= time, "start {start} time {time}");
}

#[test]
fn a_second_stop_adds_to_the_total_and_keeps_the_start_time() {
    let (_, first, end) = stop(&lines(&["a", "b"], false), Position::default(), None);
    let (_, second, _) = stop(&lines(&["c", "d", "e"], false), end, None);
    assert_eq!(second[0]["asInt"], "5");
    assert_eq!(
        first[0]["startTimeUnixNano"],
        second[0]["startTimeUnixNano"]
    );
}

#[test]
fn a_resumed_session_continues_from_the_stored_total() {
    // The cursor survives SessionEnd, so a resume parses on from the stored Position.
    let (_, first, end) = stop(&lines(&["a", "b"], false), Position::default(), None);
    let (_, resumed, _) = stop(&lines(&["c"], false), end, None);
    assert_eq!(
        resumed[0]["asInt"], "3",
        "restarted at 0 instead of continuing"
    );
    assert_eq!(
        first[0]["startTimeUnixNano"],
        resumed[0]["startTimeUnixNano"]
    );
}

#[test]
fn subagent_cursors_keep_separate_totals() {
    let (_, main, _) = stop(&lines(&["a", "b"], false), Position::default(), None);
    let (_, one, end_one) = stop(&lines(&["s1"], true), Position::default(), Some("ag-1"));
    let (_, two, _) = stop(
        &lines(&["t1", "t2", "t3"], true),
        Position::default(),
        Some("ag-2"),
    );
    let (_, one_again, _) = stop(&lines(&["s2"], true), end_one, Some("ag-1"));
    assert_eq!(main[0]["asInt"], "2");
    assert_eq!(one[0]["asInt"], "1");
    assert_eq!(two[0]["asInt"], "3");
    assert_eq!(one_again[0]["asInt"], "2");
    let agent = |p: &Value| {
        p["attributes"]
            .as_array()
            .unwrap()
            .iter()
            .find(|a| a["key"] == "agent_id")
            .map(|a| a["value"]["stringValue"].as_str().unwrap().to_owned())
    };
    assert_eq!(agent(&one_again[0]).as_deref(), Some("ag-1"));
}
