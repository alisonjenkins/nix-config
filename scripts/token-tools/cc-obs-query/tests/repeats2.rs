#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]

//! Agent scoping, edit-aware identical repeats and record dedupe for `repeats`.
//! Records carry the ledger's real field name `agent` (main|subagent).

mod common;

use common::{cli, fixture, row, rows, serve};
use serde_json::{json, Value};

const LEDGER: &str = "event_name=\"cc_obs_ledger.tool_call\"";

/// session, agent, tool, input hash, seq.
struct Rec(&'static str, &'static str, &'static str, &'static str, u64);

fn record(r: &Rec) -> Value {
    json!({
        "session_id": r.0, "agent": r.1, "tool_name": r.2,
        "input_hash": r.3, "input_prefix_hash": format!("p_{}", r.3),
        "result_bytes": "10", "turn": r.4.to_string(), "seq": r.4.to_string(),
    })
}

fn loki_meta(metas: &[Value]) -> String {
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

fn loki(recs: &[Rec]) -> String {
    let metas: Vec<Value> = recs.iter().map(record).collect();
    loki_meta(&metas)
}

fn run_repeats(body: String) -> Value {
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
    let run = cli(&fake, &["repeats"]);
    assert_eq!(run.code, 0, "{}", run.err);
    run.json()
}

fn has(out: &Value, key: &str) -> bool {
    rows(out).iter().any(|r| r["key"] == key)
}

#[test]
fn main_and_subagent_calls_do_not_join_one_sequence() {
    // Interleaved: each agent alone holds Read>Edit>Bash only once per session.
    let mut recs = Vec::new();
    for s in ["s1", "s2"] {
        recs.push(Rec(s, "main", "Read", "a", 0));
        recs.push(Rec(s, "subagent", "Grep", "b", 1));
        recs.push(Rec(s, "main", "Glob", "c", 2));
        recs.push(Rec(s, "subagent", "Grep", "d", 3));
        recs.push(Rec(s, "main", "Bash", "e", 4));
    }
    let out = run_repeats(loki(&recs));
    assert!(
        !has(&out, "sequence:Read>Grep>Glob"),
        "agents joined into one sequence: {out}"
    );
}

#[test]
fn agent_type_is_still_read_for_old_data() {
    let mut metas = Vec::new();
    for (i, agent) in ["main", "sub", "main", "sub", "main"].iter().enumerate() {
        let mut m = record(&Rec("s1", agent, "Read", "a", i as u64));
        let obj = m.as_object_mut().unwrap();
        let v = obj.remove("agent").unwrap();
        obj.insert("agent_type".to_owned(), v);
        metas.push(m);
    }
    let out = run_repeats(loki_meta(&metas));
    // Three main calls and two sub calls: split by agent they save 2 + 1 calls, not 4.
    assert_eq!(row(&out, "identical:Read")["value"], json!(3), "{out}");
}

#[test]
fn identical_is_scoped_to_the_agent() {
    let recs = [
        Rec("s1", "main", "Read", "a", 0),
        Rec("s1", "subagent", "Read", "a", 1),
    ];
    let out = run_repeats(loki(&recs));
    assert!(
        !has(&out, "identical:Read"),
        "a subagent call repeated a main-agent call: {out}"
    );
}

#[test]
fn near_identical_is_scoped_to_the_agent() {
    let recs = [
        Rec("s1", "main", "Grep", "a", 0),
        Rec("s1", "subagent", "Grep", "b", 1),
    ];
    let mut metas: Vec<Value> = recs.iter().map(record).collect();
    for m in &mut metas {
        m["input_prefix_hash"] = json!("shared");
    }
    let out = run_repeats(loki_meta(&metas));
    assert!(!has(&out, "near_identical:Grep"), "{out}");
}
