#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]

mod common;

use common::{cli, rows, serve, with_own};
use serde_json::{json, Value};

const EMPTY_LOKI: &str = r#"{"status":"success","data":{"resultType":"streams","result":[]}}"#;
const EMPTY_PROM: &str = r#"{"status":"success","data":{"resultType":"vector","result":[]}}"#;

fn gauge(label: &str, names: &[&str]) -> String {
    let result: Vec<Value> = names
        .iter()
        .map(|n| json!({"metric": {label: n}, "value": [1.0, "1"]}))
        .collect();
    json!({"status": "success", "data": {"resultType": "vector", "result": result}}).to_string()
}

/// Ledger `tool_call` records as `(tool_name, result_bytes)`.
fn ledger_calls(calls: &[(&str, u64)]) -> String {
    let streams: Vec<Value> = calls
        .iter()
        .enumerate()
        .map(|(i, (tool, bytes))| {
            json!({
                "stream": {"service_name": "cc-obs-ledger"},
                "values": [[
                    format!("{}", 1_760_000_000_000_000_000_u64 + i as u64),
                    "cc_obs_ledger.tool_call",
                    {"structuredMetadata": {
                        "session_id": "s1",
                        "tool_name": tool,
                        "input_hash": format!("h{i}"),
                        "result_bytes": bytes.to_string(),
                        "turn": "1",
                        "seq": i.to_string(),
                    }}
                ]],
            })
        })
        .collect();
    json!({"status": "success", "data": {"resultType": "streams", "result": streams}}).to_string()
}

/// claude-code `tool_result` records, which name every MCP call `mcp_tool`.
fn native_results(n: usize) -> String {
    let streams: Vec<Value> = (0..n)
        .map(|i| {
            json!({
                "stream": {"service_name": "claude-code"},
                "values": [[
                    format!("{}", 1_760_000_000_000_000_000_u64 + i as u64),
                    "tool_result",
                    {"structuredMetadata": {
                        "tool_name": "mcp_tool",
                        "tool_result_size_bytes": "4000",
                    }}
                ]],
            })
        })
        .collect();
    json!({"status": "success", "data": {"resultType": "streams", "result": streams}}).to_string()
}

fn mcp_rules(connected: &[&str], calls: &[(&str, u64)]) -> Vec<(&'static str, String)> {
    with_own(vec![
        (
            "cc_obs_ledger_mcp_server_connected",
            gauge("mcp_server_name", connected),
        ),
        ("cc_obs_ledger.tool_call", ledger_calls(calls)),
        ("event_name=\"tool_result\"", native_results(3)),
        ("event_name=", EMPTY_LOKI.to_owned()),
        ("/prom/", EMPTY_PROM.to_owned()),
    ])
}

fn keys(out: &Value) -> Vec<&str> {
    rows(out)
        .iter()
        .map(|r| r["key"].as_str().unwrap())
        .collect()
}

#[test]
fn idle_mcp_matches_plugin_server_across_name_normalisation() {
    let fake = serve(mcp_rules(&["plugin:a:b"], &[("mcp__plugin_a_b__x", 400)]));
    let run = cli(&fake, &["top", "mcp", "--idle"]);
    assert_eq!(run.code, 0, "{}", run.err);
    let out = run.json();
    assert!(
        !keys(&out).contains(&"plugin:a:b"),
        "called server idle: {out}"
    );
}

#[test]
fn idle_mcp_matches_claude_ai_server_with_spaces() {
    let fake = serve(mcp_rules(
        &["claude.ai Claude Docs", "never-called"],
        &[("mcp__claude_ai_Claude_Docs__read", 400)],
    ));
    let out = cli(&fake, &["top", "mcp", "--idle"]).json();
    assert_eq!(keys(&out), vec!["never-called"], "{out}");
}

#[test]
fn mcp_by_tokens_ranks_ledger_calls_and_keeps_unconnected_servers() {
    let fake = serve(mcp_rules(
        &["plugin:a:b"],
        &[
            ("mcp__plugin_a_b__x", 4000),
            ("mcp__plugin_a_b__y", 4000),
            ("mcp__claude-in-chrome__navigate", 40_000),
            ("Read", 999_999),
        ],
    ));
    let run = cli(&fake, &["top", "mcp", "--by", "tokens"]);
    assert_eq!(run.code, 0, "{}", run.err);
    let out = run.json();
    assert_eq!(keys(&out), vec!["claude-in-chrome", "plugin_a_b"], "{out}");
    let plugin = rows(&out)
        .iter()
        .find(|r| r["key"] == "plugin_a_b")
        .unwrap();
    assert_eq!(plugin["calls"], 2, "{out}");
}
