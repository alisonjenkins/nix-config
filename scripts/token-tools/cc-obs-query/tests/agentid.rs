#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]

//! Sub-agents of one session share `session_id` and `agent="subagent"`; only the
//! `agent_id` attribute tells them apart, and each restarts its `seq` at 0.

mod common;

use common::{cli, fixture, row, rows, serve};
use serde_json::{json, Value};

const LEDGER: &str = "event_name=\"cc_obs_ledger.tool_call\"";

struct Rec {
    agent_id: Option<&'static str>,
    tool: &'static str,
    shape: Option<&'static str>,
    input: &'static str,
    seq: u64,
}

fn rec(agent_id: &'static str, tool: &'static str, input: &'static str, seq: u64) -> Rec {
    Rec {
        agent_id: Some(agent_id),
        tool,
        shape: None,
        input,
        seq,
    }
}

fn bash(agent_id: &'static str, shape: &'static str, seq: u64) -> Rec {
    Rec {
        agent_id: Some(agent_id),
        tool: "Bash",
        shape: Some(shape),
        input: shape,
        seq,
    }
}

fn loki(recs: &[Rec]) -> String {
    let lines: Vec<String> = recs
        .iter()
        .enumerate()
        .map(|(i, r)| {
            let mut meta = json!({
                "session_id": "s1", "agent": "subagent", "tool_name": r.tool,
                "input_hash": r.input, "input_prefix_hash": format!("p_{}", r.input),
                "result_bytes": "400", "turn": "0", "seq": r.seq.to_string(),
            });
            if let Some(id) = r.agent_id {
                meta["agent_id"] = json!(id);
            }
            if let Some(shape) = r.shape {
                meta["command_shape"] = json!(shape);
            }
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

fn run_ledger(recs: &[Rec], args: &[&str]) -> Value {
    let fake = serve(vec![
        (LEDGER, loki(recs)),
        (
            "claude_code_token_usage_tokens_total{review_run=\"1\"",
            fixture("prom_scalar_review_tokens.json"),
        ),
        (
            "claude_code_cost_usage_USD_total{review_run=\"1\"}",
            fixture("prom_scalar_review_cost.json"),
        ),
    ]);
    let run = cli(&fake, args);
    assert_eq!(run.code, 0, "{}", run.err);
    run.json()
}

#[test]
fn a_call_repeated_across_two_subagents_is_not_a_repeat() {
    let out = run_ledger(
        &[
            rec("agent-a", "Read", "same", 0),
            rec("agent-b", "Read", "same", 0),
        ],
        &["repeats"],
    );
    assert_eq!(out["calls_analysed"], json!(2), "{out}");
    assert!(
        rows(&out).is_empty(),
        "each sub-agent read the file once, so nothing repeats: {out}"
    );
}

#[test]
fn a_call_repeated_inside_one_subagent_is_counted_once_per_agent() {
    let out = run_ledger(
        &[
            rec("agent-a", "Read", "same", 0),
            rec("agent-a", "Read", "same", 1),
            rec("agent-b", "Read", "same", 0),
            rec("agent-b", "Read", "same", 1),
        ],
        &["repeats"],
    );
    let r = row(&out, "identical:Read");
    assert_eq!(r["value"], json!(2), "one repeat in each sub-agent: {out}");
    assert_eq!(r["calls"], json!(4), "{out}");
}

#[test]
fn records_without_an_agent_id_stay_one_stream() {
    let old = |seq| Rec {
        agent_id: None,
        tool: "Read",
        shape: None,
        input: "same",
        seq,
    };
    let out = run_ledger(&[old(0), old(1)], &["repeats"]);
    assert_eq!(row(&out, "identical:Read")["value"], json!(1), "{out}");
}

#[test]
fn automate_counts_each_subagent_run_of_a_sequence_separately() {
    let out = run_ledger(
        &[
            bash("agent-a", "git status", 0),
            bash("agent-a", "cargo test", 1),
            bash("agent-b", "git status", 0),
            bash("agent-b", "cargo test", 1),
        ],
        &["automate"],
    );
    let seq = row(&out, "sequence:git_status>cargo_test");
    assert_eq!(seq["calls"], json!(2), "two runs, one per agent: {out}");
    assert_eq!(seq["sub"], json!(2), "{out}");
    assert_eq!(seq["main"], json!(0), "{out}");
    assert_eq!(row(&out, "shape:git_status")["sub"], json!(2), "{out}");
}

#[test]
fn automate_does_not_stitch_two_subagents_into_one_sequence() {
    // agent-a ends on git status and agent-b starts with cargo test: a merged stream
    // would hold the window `git status > cargo test` that no agent ran.
    let out = run_ledger(
        &[
            bash("agent-a", "cargo build", 0),
            bash("agent-a", "git status", 1),
            bash("agent-b", "cargo test", 0),
            bash("agent-b", "cargo fmt", 1),
        ],
        &["automate"],
    );
    let keys: Vec<&str> = rows(&out)
        .iter()
        .map(|r| r["key"].as_str().unwrap())
        .collect();
    assert!(
        !keys.iter().any(|k| k.starts_with("sequence:")),
        "no sequence occurs twice: {keys:?}"
    );
}
