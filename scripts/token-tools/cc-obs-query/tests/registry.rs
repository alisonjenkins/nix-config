#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects,
    clippy::panic
)]

//! The known-signal registry and the evidence check for ledger-backed rankings.

mod common;

use cc_obs_query::pack::{Pack, COLLECTED_SIGNALS};
use common::{cli, rows, s, serve, write_pack};

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
