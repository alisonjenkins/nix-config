#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]

//! The ledger's `subagent` hook gives every sub-agent its own cursor, so each sub-agent's
//! `seq` starts at 0. The loader's dedupe must therefore keep two sub-agents' calls with
//! the same (session, agent, seq) apart by `agent_id`.

mod common;

use common::{cli, fixture, serve};
use serde_json::{json, Value};

const LEDGER: &str = "event_name=\"cc_obs_ledger.tool_call\"";

fn record(agent_id: &str, hash: &str) -> Value {
    json!({
        "session_id": "s1", "agent": "subagent", "agent_id": agent_id,
        "tool_name": "Read", "input_hash": hash, "input_prefix_hash": format!("p_{hash}"),
        "result_bytes": "10", "turn": "0", "seq": "0",
    })
}

fn loki(metas: &[Value]) -> String {
    let lines: Vec<String> = metas
        .iter()
        .enumerate()
        .map(|(i, meta)| {
            json!({
                "stream": {"service_name": "cc-obs-ledger"},
                "values": [[format!("{}", 1_760_000_000_000_000_000_u64 + i as u64),
                            "cc_obs_ledger.tool_call", {"structuredMetadata": meta}]]
            })
            .to_string()
        })
        .collect();
    format!(
        r#"{{"status":"success","data":{{"resultType":"streams","result":[{}],"stats":{{}}}}}}"#,
        lines.join(",")
    )
}

#[test]
#[ignore = "known: keyed on agent_id in follow-up"]
fn subagents_whose_seq_restarts_are_not_deduplicated_into_one() {
    let fake = serve(vec![
        (
            LEDGER,
            loki(&[record("agent-a", "x"), record("agent-b", "y")]),
        ),
        (
            "claude_code_token_usage_tokens_total{review_run=\"1\"",
            fixture("prom_scalar_review_tokens.json"),
        ),
        (
            "claude_code_cost_usage_USD_total{review_run=\"1\"}",
            fixture("prom_scalar_review_cost.json"),
        ),
    ]);
    let run = cli(&fake, &["repeats"]);
    assert_eq!(run.code, 0, "{}", run.err);
    let out = run.json();
    assert_eq!(
        out["calls_analysed"],
        json!(2),
        "two sub-agents' first calls were merged: {out}"
    );
}
