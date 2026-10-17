#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::unwrap_in_result
)]

//! Skill listing, MCP server and per-turn cache signals, read from the transcript
//! and sent by the Stop hook.

use cc_obs_ledger::otlp::{turn_payloads, Resource};
use cc_obs_ledger::transcript::{parse, parse_from, Position, ToolHasher};
use serde_json::Value;

fn hasher() -> ToolHasher {
    ToolHasher::new(b"k".to_vec())
}

fn assistant(request: &str, time: &str, usage: &str) -> String {
    format!(
        r#"{{"type":"assistant","sessionId":"sess-1","requestId":"{request}","timestamp":"{time}","cwd":"/work/proj","isSidechain":false,"message":{{"model":"m1","role":"assistant","content":[{{"type":"text","text":"x"}}]{usage}}}}}"#
    )
}

fn usage(creation: u64) -> String {
    format!(
        r#","usage":{{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":2,"cache_creation_input_tokens":{creation}}}"#
    )
}

fn user() -> String {
    r#"{"type":"user","sessionId":"sess-1","cwd":"/work/proj","isSidechain":false,"message":{"role":"user","content":"hello"}}"#.to_owned()
}

fn attachment(body: Value) -> String {
    serde_json::json!({"type":"attachment","sessionId":"sess-1","attachment":body}).to_string()
}

fn skill_listing(content: &str) -> String {
    attachment(serde_json::json!({"type":"skill_listing","content":content}))
}

fn mcp_delta(added: &[&str], removed: &[&str]) -> String {
    attachment(serde_json::json!({
        "type":"mcp_instructions_delta",
        "addedNames":added,
        "addedBlocks":["## secret instruction text"],
        "removedNames":removed,
    }))
}

fn metrics(text: &str, name: &str) -> Vec<Value> {
    let parsed = parse(text, &hasher());
    metrics_of(&parsed, name)
}

fn metrics_of(parsed: &cc_obs_ledger::transcript::Parsed, name: &str) -> Vec<Value> {
    turn_payloads(&Resource::new("h", &[]), parsed)
        .iter()
        .filter_map(|p| p.body.pointer("/resourceMetrics/0/scopeMetrics/0/metrics"))
        .filter_map(Value::as_array)
        .flatten()
        .filter(|m| m["name"] == name)
        .flat_map(|m| m["gauge"]["dataPoints"].as_array().unwrap().clone())
        .collect()
}

fn attr(point: &Value, key: &str) -> Option<String> {
    point["attributes"]
        .as_array()
        .unwrap()
        .iter()
        .find(|a| a["key"] == key)
        .map(|a| {
            a["value"]["stringValue"]
                .as_str()
                .or_else(|| a["value"]["intValue"].as_str())
                .unwrap()
                .to_owned()
        })
}

#[test]
fn each_listed_skill_gets_a_token_estimate() {
    let listing = "- alpha: 0123456789012345678901234\n- plugin:beta: short one";
    let points = metrics(&skill_listing(listing), "cc_obs_ledger_skill_listed_tokens");
    assert_eq!(points.len(), 2, "{points:?}");
    let alpha = points
        .iter()
        .find(|p| attr(p, "skill_name").as_deref() == Some("alpha"))
        .expect("alpha");
    // "- alpha: 0123456789012345678901234" is 34 chars: 34 / 4 = 8.
    assert_eq!(alpha["asInt"], "8");
    assert!(points
        .iter()
        .any(|p| attr(p, "skill_name").as_deref() == Some("plugin:beta")));
}

#[test]
fn skill_gauge_carries_only_the_skill_name_label() {
    let points = metrics(
        &skill_listing("- alpha: d"),
        "cc_obs_ledger_skill_listed_tokens",
    );
    let keys: Vec<&str> = points[0]["attributes"]
        .as_array()
        .unwrap()
        .iter()
        .map(|a| a["key"].as_str().unwrap())
        .collect();
    assert_eq!(keys, ["skill_name"]);
}

#[test]
fn a_wrapped_description_counts_toward_its_skill() {
    let listing = "- alpha: first line\ncontinued here\n- beta: x";
    let points = metrics(&skill_listing(listing), "cc_obs_ledger_skill_listed_tokens");
    let alpha = points
        .iter()
        .find(|p| attr(p, "skill_name").as_deref() == Some("alpha"))
        .unwrap();
    // "- alpha: first line" (19) + newline (1) + "continued here" (14) = 34 / 4 = 8.
    assert_eq!(alpha["asInt"], "8");
}

#[test]
fn no_skill_metric_without_a_skill_listing() {
    let text = [
        user(),
        assistant("r1", "2026-10-09T10:00:00.000Z", &usage(5)),
    ]
    .join("\n");
    assert!(metrics(&text, "cc_obs_ledger_skill_listed_tokens").is_empty());
}

#[test]
fn the_latest_skill_listing_wins() {
    let text = [skill_listing("- old: aaaa"), skill_listing("- new: bbbb")].join("\n");
    let points = metrics(&text, "cc_obs_ledger_skill_listed_tokens");
    assert_eq!(points.len(), 1);
    assert_eq!(attr(&points[0], "skill_name").as_deref(), Some("new"));
}

#[test]
fn each_mcp_server_in_the_instructions_is_connected() {
    let text = mcp_delta(&["claude-in-chrome", "plugin:x:nixos"], &[]);
    let points = metrics(&text, "cc_obs_ledger_mcp_server_connected");
    assert_eq!(points.len(), 2, "{points:?}");
    for point in &points {
        assert_eq!(point["asInt"], "1");
    }
    assert!(points
        .iter()
        .any(|p| attr(p, "mcp_server_name").as_deref() == Some("plugin:x:nixos")));
}

#[test]
fn a_removed_mcp_server_is_not_connected() {
    let text = [mcp_delta(&["a", "b"], &[]), mcp_delta(&[], &["a"])].join("\n");
    let points = metrics(&text, "cc_obs_ledger_mcp_server_connected");
    assert_eq!(points.len(), 1, "{points:?}");
    assert_eq!(attr(&points[0], "mcp_server_name").as_deref(), Some("b"));
}

#[test]
fn no_mcp_metric_without_mcp_instructions() {
    let text = [
        user(),
        assistant("r1", "2026-10-09T10:00:00.000Z", &usage(5)),
    ]
    .join("\n");
    assert!(metrics(&text, "cc_obs_ledger_mcp_server_connected").is_empty());
}

#[test]
fn instruction_text_never_reaches_a_payload() {
    let text = [
        mcp_delta(&["a"], &[]),
        skill_listing("- alpha: SECRET-DESC"),
    ]
    .join("\n");
    let parsed = parse(&text, &hasher());
    let sent = turn_payloads(&Resource::new("h", &[]), &parsed);
    let all = serde_json::to_string(&sent.iter().map(|p| &p.body).collect::<Vec<_>>()).unwrap();
    assert!(!all.contains("secret instruction text"), "{all}");
    assert!(!all.contains("SECRET-DESC"), "{all}");
}

#[test]
fn cache_creation_is_reported_per_request_with_the_context_labels() {
    let text = [
        user(),
        assistant("r1", "2026-10-09T10:00:00.000Z", &usage(7)),
        assistant("r2", "2026-10-09T10:00:10.000Z", &usage(0)),
    ]
    .join("\n");
    let points = metrics(&text, "cc_obs_ledger_cache_creation_tokens");
    assert_eq!(points.len(), 2, "{points:?}");
    let first = &points[0];
    assert_eq!(first["asInt"], "7");
    assert_eq!(attr(first, "session.id").as_deref(), Some("sess-1"));
    assert_eq!(attr(first, "project").as_deref(), Some("proj"));
    assert_eq!(attr(first, "model").as_deref(), Some("m1"));
    assert_eq!(attr(first, "agent").as_deref(), Some("main"));
    assert_eq!(attr(first, "turn").as_deref(), Some("1"));
    assert_eq!(points[1]["asInt"], "0");
}

#[test]
fn no_cache_creation_metric_when_the_request_has_no_usage() {
    let text = [user(), assistant("r1", "2026-10-09T10:00:00.000Z", "")].join("\n");
    assert!(metrics(&text, "cc_obs_ledger_cache_creation_tokens").is_empty());
}

#[test]
fn seconds_since_the_previous_request_are_reported() {
    let text = [
        user(),
        assistant("r1", "2026-10-09T10:00:00.000Z", &usage(1)),
        assistant("r2", "2026-10-09T10:06:30.500Z", &usage(1)),
    ]
    .join("\n");
    let points = metrics(&text, "cc_obs_ledger_seconds_since_prev_request");
    // The first request has no predecessor: no point, not a zero.
    assert_eq!(points.len(), 1, "{points:?}");
    assert_eq!(points[0]["asInt"], "390");
    assert_eq!(attr(&points[0], "turn").as_deref(), Some("1"));
    assert_eq!(attr(&points[0], "session.id").as_deref(), Some("sess-1"));
}

#[test]
fn a_request_without_a_timestamp_has_no_gap() {
    let bare = r#"{"type":"assistant","sessionId":"sess-1","requestId":"r2","cwd":"/work/proj","isSidechain":false,"message":{"model":"m1","content":[]}}"#;
    let text = [
        assistant("r1", "2026-10-09T10:00:00.000Z", &usage(1)),
        bare.to_owned(),
    ]
    .join("\n");
    assert!(metrics(&text, "cc_obs_ledger_seconds_since_prev_request").is_empty());
}

#[test]
fn the_gap_carries_across_two_stop_hooks() {
    let first = [
        user(),
        assistant("r1", "2026-10-09T10:00:00.000Z", &usage(1)),
    ]
    .join("\n");
    let second = assistant("r2", "2026-10-09T10:10:00.000Z", &usage(1));
    let one = parse_from(&first, &hasher(), Position::default());
    let two = parse_from(&second, &hasher(), one.end);
    let points = metrics_of(&two, "cc_obs_ledger_seconds_since_prev_request");
    assert_eq!(points.len(), 1, "{points:?}");
    assert_eq!(points[0]["asInt"], "600");
}

#[test]
fn subagent_requests_do_not_set_the_main_agents_gap() {
    let sub = r#"{"type":"assistant","sessionId":"sess-1","requestId":"s1","timestamp":"2026-10-09T10:00:50.000Z","cwd":"/work/proj","isSidechain":true,"message":{"model":"m1","content":[]}}"#;
    let text = [
        assistant("r1", "2026-10-09T10:00:00.000Z", &usage(1)),
        sub.to_owned(),
        assistant("r2", "2026-10-09T10:01:00.000Z", &usage(1)),
    ]
    .join("\n");
    let points = metrics(&text, "cc_obs_ledger_seconds_since_prev_request");
    assert_eq!(points.len(), 1, "{points:?}");
    assert_eq!(points[0]["asInt"], "60");
}
