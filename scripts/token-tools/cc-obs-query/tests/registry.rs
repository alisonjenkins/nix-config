#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects,
    clippy::panic
)]

//! The known-signal registry and the evidence check for ledger-backed rankings.

mod common;

use std::fs;

use cc_obs_query::pack::{Pack, COLLECTED_SIGNALS};
use common::{cli, digest_rules, fixture, rows, s, serve, write_pack};
use serde_json::{json, Value};

const NEW_SIGNALS: [&str; 5] = [
    "cc_obs_ledger_requests_total",
    "cc_obs_ledger_mcp_server_connected",
    "cc_obs_ledger_skill_listed_tokens",
    "cc_obs_ledger_cache_creation_tokens",
    "cc_obs_ledger_seconds_since_prev_request",
];

fn question(signal: &str) -> String {
    format!(
        "version: 1\nquestions:\n  - id: only\n    title: Only\n    signals: [{signal}]\n    query: {{ command: \"cc-obs-query top model\" }}\n    decision_kind: configure\n"
    )
}

#[test]
fn pack_accepts_a_question_citing_each_new_ledger_signal() {
    for signal in NEW_SIGNALS {
        let dir = tempfile::tempdir().unwrap();
        let pack = write_pack(dir.path(), &question(signal));
        Pack::load(&pack).unwrap_or_else(|e| panic!("{signal}: {e}"));
    }
}

#[test]
fn unused_signals_flags_an_unreferenced_new_ledger_signal() {
    let dir = tempfile::tempdir().unwrap();
    let pack = write_pack(dir.path(), &question("claude_code.token.usage"));
    let fake = serve(vec![]);
    let run = cli(
        &fake,
        &["unused-signals", "--pack", s(&pack), "--limit", "100"],
    );
    assert_eq!(run.code, 1, "{}", run.err);
    let out = run.json();
    let keys: Vec<&str> = rows(&out)
        .iter()
        .map(|r| r["key"].as_str().unwrap())
        .collect();
    for signal in NEW_SIGNALS {
        assert!(keys.contains(&signal), "{signal} missing from {keys:?}");
        assert!(COLLECTED_SIGNALS.contains(&signal));
    }
}

const RUN_LENGTH_PACK: &str = r#"version: 1
questions:
  - id: agent-run-length
    title: Which sessions and sub-agents made the most API requests?
    signals: [claude_code.token.usage]
    query: { command: "cc-obs-query top session --by requests" }
    decision_kind: configure
    threshold: { min_value: 100 }
"#;

#[test]
fn digest_write_accepts_baseline_evidence_for_a_subagent_session() {
    let counter = json!({"status":"success","data":{"resultType":"vector","result":[
        {"metric":{"session_id":"s1","agent":"subagent"},"value":[1.0,"559"]},
        {"metric":{"session_id":"s1","agent":"main"},"value":[1.0,"40"]}
    ]}})
    .to_string();
    let mut rules = vec![("cc_obs_ledger_requests_total", counter)];
    rules.extend(digest_rules(fixture("loki_tool_results.json")));
    let dir = tempfile::tempdir().unwrap();
    let pack = write_pack(dir.path(), RUN_LENGTH_PACK);
    let fake = serve(rules);
    let run = cli(
        &fake,
        &[
            "digest",
            "--baseline",
            "--pack",
            s(&pack),
            "--since",
            "7d",
            "--until",
            "2026-10-09",
        ],
    );
    assert_eq!(run.code, 0, "{}", run.err);
    let digest: Value = run.json();
    assert_eq!(
        digest["questions"][0]["rows"][0]["evidence"],
        json!("session:s1/subagent"),
        "{digest}"
    );
    let file = dir.path().join("in.json");
    fs::write(&file, digest.to_string()).unwrap();
    let run = cli(
        &fake,
        &[
            "digest",
            "--write",
            s(&file),
            "--pack",
            s(&pack),
            "--until",
            "2026-10-09",
        ],
    );
    assert_eq!(run.code, 0, "{}", run.err);
}
