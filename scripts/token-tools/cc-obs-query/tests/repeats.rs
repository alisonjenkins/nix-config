#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]

mod common;

use common::{cli, fixture, row, rows, serve};
use serde_json::{json, Value};

const LEDGER: &str = "event_name=\"cc_obs_ledger.tool_call\"";

/// One ledger record: session, agent, tool, input hash, prefix hash, result bytes, turn, seq.
struct Rec(
    &'static str,
    &'static str,
    &'static str,
    &'static str,
    &'static str,
    u64,
    u64,
    u64,
);

fn loki(recs: &[Rec]) -> String {
    let lines: Vec<String> = recs
        .iter()
        .enumerate()
        .map(|(i, r)| {
            let meta = json!({
                "session_id": r.0, "agent_type": r.1, "tool_name": r.2,
                "input_hash": r.3, "input_prefix_hash": r.4,
                "result_bytes": r.5.to_string(), "turn": r.6.to_string(), "seq": r.7.to_string(),
            });
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

fn run_repeats(body: String, extra: &[&str]) -> Value {
    let fake = serve(vec![
        (LEDGER, body),
        (
            "claude_code_token_usage_tokens_total{review_run=\"1\"",
            fixture("prom_scalar_review_tokens.json"),
        ),
        (
            "claude_code_cost_usage_USD_total{review_run=\"1\"}",
            fixture("prom_scalar_review_cost.json"),
        ),
    ]);
    let mut args = vec!["repeats"];
    args.extend_from_slice(extra);
    let run = cli(&fake, &args);
    assert_eq!(run.code, 0, "{}", run.err);
    run.json()
}

fn has(out: &Value, key: &str) -> bool {
    rows(out).iter().any(|r| r["key"] == key)
}

#[test]
fn sequence_run_of_five_counts_one_occurrence_not_three() {
    let recs: Vec<Rec> = (0..5)
        .map(|i| Rec("s1", "main", "Bash", "h", "p", 10, i, i))
        .collect();
    let out = run_repeats(loki(&recs), &[]);
    // Five identical calls hold one non-overlapping triple, below --min-count 2.
    assert!(
        !has(&out, "sequence:Bash>Bash>Bash"),
        "overlapping windows reported as repeated triples: {out}"
    );
}

#[test]
fn sequence_run_of_seven_counts_two_occurrences() {
    let recs: Vec<Rec> = (0..7)
        .map(|i| Rec("s1", "main", "Bash", "h", "p", 10, i, i))
        .collect();
    let out = run_repeats(loki(&recs), &["--format", "detailed"]);
    let r = row(&out, "sequence:Bash>Bash>Bash");
    assert_eq!(r["calls"], json!(2), "{out}");
    assert_eq!(r["calls_covered"], json!(6), "{out}");
}

#[test]
fn sequences_do_not_cross_agents() {
    let mut recs = Vec::new();
    for s in ["s1", "s2"] {
        recs.push(Rec(s, "main", "Read", "a", "a", 10, 1, 0));
        recs.push(Rec(s, "sub", "Edit", "b", "b", 10, 1, 1));
        recs.push(Rec(s, "main", "Grep", "c", "c", 10, 1, 2));
        recs.push(Rec(s, "sub", "Edit", "d", "d", 10, 1, 3));
        recs.push(Rec(s, "main", "Bash", "e", "e", 10, 1, 4));
    }
    let out = run_repeats(loki(&recs), &[]);
    assert!(
        !has(&out, "sequence:Read>Edit>Grep"),
        "main and subagent calls interleaved into one sequence: {out}"
    );
}
