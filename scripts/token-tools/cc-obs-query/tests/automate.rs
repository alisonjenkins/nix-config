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

/// One ledger tool_call record as the new ledger writes it.
struct Rec {
    session: &'static str,
    agent: &'static str,
    agent_id: Option<&'static str>,
    tool: &'static str,
    shape: Option<&'static str>,
    input: String,
    prefix: &'static str,
    result_bytes: u64,
    turn: u64,
    seq: u64,
}

fn bash(session: &'static str, shape: &'static str, seq: u64) -> Rec {
    Rec {
        session,
        agent: "main",
        agent_id: None,
        tool: "Bash",
        shape: Some(shape),
        input: format!("h{seq}"),
        prefix: "p",
        result_bytes: 400,
        turn: seq,
        seq,
    }
}

fn loki(recs: &[Rec]) -> String {
    let lines: Vec<String> = recs
        .iter()
        .enumerate()
        .map(|(i, r)| {
            let mut meta = json!({
                "session_id": r.session, "agent": r.agent, "tool_name": r.tool,
                "input_hash": r.input, "input_prefix_hash": r.prefix,
                "result_bytes": r.result_bytes.to_string(),
                "turn": r.turn.to_string(), "seq": r.seq.to_string(),
            });
            if let Some(shape) = r.shape {
                meta["command_shape"] = json!(shape);
            }
            if let Some(id) = r.agent_id {
                meta["agent_id"] = json!(id);
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

fn run_automate(recs: &[Rec], extra: &[&str]) -> Value {
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
    let mut args = vec!["automate"];
    args.extend_from_slice(extra);
    let run = cli(&fake, &args);
    assert_eq!(run.code, 0, "{}", run.err);
    run.json()
}

fn keys(out: &Value) -> Vec<String> {
    rows(out)
        .iter()
        .map(|r| r["key"].as_str().unwrap().to_owned())
        .collect()
}

fn near(value: &Value, expected: f64) {
    let got = value.as_f64().unwrap();
    assert!((got - expected).abs() < 1e-9, "{got} is not {expected}");
}

#[test]
fn shapes_are_scored_from_documented_constants() {
    // Three 100-token results in one run: direct = 3 x (100 + 100 call tokens),
    // carried = 100 x (2 + 1 + 0) token-turns.
    let recs: Vec<Rec> = (0..3).map(|i| bash("s1", "git status", i)).collect();
    let out = run_automate(&recs, &[]);
    let r = row(&out, "shape:git_status");
    assert_eq!(r["pattern"], json!("shape"), "{out}");
    assert_eq!(r["calls"], json!(3), "{out}");
    assert_eq!(r["sessions"], json!(1), "{out}");
    near(&r["est_usd"], 600.0 * 2e-6 + 300.0 * 0.2e-6);
    near(&r["value"], (600.0 * 2e-6 + 300.0 * 0.2e-6) * 0.8);
    assert_eq!(r["action"], json!("script"), "{out}");
    assert_eq!(r["label"], json!("git status"), "{out}");
    assert!(out["score_means"].is_string(), "{out}");
}

#[test]
fn shapes_rank_by_score_not_by_count() {
    // Four big cargo results outrank six tiny git status results.
    let mut recs = Vec::new();
    for i in 0..4 {
        let mut r = bash("s1", "cargo test | tail", i);
        r.result_bytes = 40_000;
        recs.push(r);
    }
    for i in 4..10 {
        let mut r = bash("s1", "git status", i);
        r.result_bytes = 40;
        recs.push(r);
    }
    let out = run_automate(&recs, &[]);
    let shapes: Vec<String> = keys(&out)
        .into_iter()
        .filter(|k| k.starts_with("shape:"))
        .collect();
    assert_eq!(
        shapes,
        [
            "shape:cargo_test_|_tail".replace('|', "_"),
            "shape:git_status".to_owned()
        ],
        "{out}"
    );
}

#[test]
fn a_repeated_sequence_is_one_candidate_labelled_by_its_shapes() {
    let mut recs = Vec::new();
    for s in ["s1", "s2"] {
        recs.push(bash(s, "cargo test", 0));
        recs.push(bash(s, "cargo fmt", 1));
        recs.push(bash(s, "cargo clippy", 2));
    }
    let out = run_automate(&recs, &["--min-count", "2"]);
    let r = row(&out, "sequence:cargo_test>cargo_fmt>cargo_clippy");
    assert_eq!(r["pattern"], json!("sequence"), "{out}");
    assert_eq!(r["calls"], json!(2), "{out}");
    assert_eq!(r["sessions"], json!(2), "{out}");
    assert_eq!(r["label"], json!("cargo test > cargo fmt > cargo clippy"));
    assert_eq!(r["action"], json!("script"), "{out}");
    // The pairs inside the triple occur only as part of it.
    assert!(
        !keys(&out).contains(&"sequence:cargo_test>cargo_fmt".to_owned()),
        "sub-sequence listed beside the sequence that contains it: {out}"
    );
}

#[test]
fn sequences_need_bash_calls_only() {
    let mut recs = Vec::new();
    for s in ["s1", "s2"] {
        recs.push(bash(s, "git status", 0));
        let mut read = bash(s, "x", 1);
        read.tool = "Read";
        read.shape = None;
        recs.push(read);
        recs.push(bash(s, "git diff", 2));
    }
    let out = run_automate(&recs, &["--min-count", "2"]);
    assert!(
        keys(&out).iter().all(|k| !k.starts_with("sequence:")),
        "a window holding a Read was offered for scripting: {out}"
    );
}

#[test]
fn without_command_shape_falls_back_to_prefix_hash_and_says_so() {
    let recs: Vec<Rec> = (0..3)
        .map(|i| {
            let mut r = bash("s1", "unused", i);
            r.shape = None;
            r.prefix = "pfx1";
            r
        })
        .collect();
    let out = run_automate(&recs, &[]);
    let r = row(&out, "shape:Bash@pfx1");
    assert_eq!(r["calls"], json!(3), "{out}");
    let gaps = out["gaps"].to_string();
    assert!(gaps.contains("command_shape"), "no gap note: {out}");
    assert!(gaps.contains("new ledger"), "{gaps}");
}

#[test]
fn with_command_shape_there_is_no_fallback_gap() {
    let recs: Vec<Rec> = (0..3).map(|i| bash("s1", "git status", i)).collect();
    let out = run_automate(&recs, &[]);
    assert!(out.get("gaps").is_none(), "{out}");
}

#[test]
fn main_and_subagent_occurrences_are_split() {
    let mut recs = vec![bash("s1", "git status", 0), bash("s1", "git status", 1)];
    for seq in 0..3 {
        let mut r = bash("s1", "git status", seq);
        r.agent = "subagent";
        r.agent_id = Some("a1");
        recs.push(r);
    }
    let out = run_automate(&recs, &[]);
    let r = row(&out, "shape:git_status");
    assert_eq!((r["main"].clone(), r["sub"].clone()), (json!(2), json!(3)));
    assert_eq!(r["calls"], json!(5), "{out}");
}

#[test]
fn two_subagents_of_one_session_do_not_form_sequences_together() {
    let mut recs = Vec::new();
    for (seq, (id, shape)) in [("a1", "git status"), ("a2", "git diff")]
        .into_iter()
        .cycle()
        .take(8)
        .enumerate()
    {
        let mut r = bash("s1", shape, seq as u64);
        r.agent = "subagent";
        r.agent_id = Some(id);
        recs.push(r);
    }
    let out = run_automate(&recs, &["--min-count", "2"]);
    assert!(
        !keys(&out).contains(&"sequence:git_status>git_diff".to_owned()),
        "calls of different sub-agents joined into one sequence: {out}"
    );
}

#[test]
fn a_large_result_then_a_narrower_query_suggests_a_tool() {
    let mut recs = Vec::new();
    for s in ["s1", "s2"] {
        let mut big = bash(s, "grep", 0);
        big.result_bytes = 30_000;
        let mut small = bash(s, "grep", 1);
        small.result_bytes = 1_000;
        recs.extend([big, small]);
    }
    let out = run_automate(&recs, &["--min-count", "2"]);
    let r = row(&out, "large_then_narrow:grep");
    assert_eq!(r["pattern"], json!("large_then_narrow"), "{out}");
    assert_eq!(r["calls"], json!(2), "{out}");
    assert_eq!(r["action"], json!("tool"), "{out}");
}

#[test]
fn the_other_shape_is_never_a_script_candidate() {
    let recs: Vec<Rec> = (0..5).map(|i| bash("s1", "other", i)).collect();
    let out = run_automate(&recs, &[]);
    assert_eq!(
        row(&out, "shape:other")["action"],
        json!("dismiss"),
        "{out}"
    );
}

#[test]
fn below_min_count_is_dismissed() {
    let recs: Vec<Rec> = (0..2).map(|i| bash("s1", "git status", i)).collect();
    let out = run_automate(&recs, &["--min-count", "3"]);
    assert_eq!(
        row(&out, "shape:git_status")["action"],
        json!("dismiss"),
        "{out}"
    );
}

#[test]
fn limit_and_offset_page_through_the_ranking() {
    let mut recs = Vec::new();
    let mut seq = 0;
    for (shape, bytes) in [("a one", 4_000), ("b two", 400), ("c three", 40)] {
        for _ in 0..2 {
            let mut r = bash("s1", shape, seq);
            r.result_bytes = bytes;
            recs.push(r);
            seq += 1;
        }
    }
    let first = run_automate(&recs, &["--limit", "1"]);
    assert_eq!(keys(&first), ["shape:a_one"], "{first}");
    assert_eq!(first["truncated"], json!(true), "{first}");
    assert_eq!(first["next"], json!("--offset 1"), "{first}");
    let second = run_automate(&recs, &["--limit", "1", "--offset", "1"]);
    assert_eq!(keys(&second), ["shape:b_two"], "{second}");
}

#[test]
fn no_records_is_unavailable_not_empty() {
    let out = run_automate(&[], &[]);
    assert!(out["unavailable"].is_string(), "{out}");
}
