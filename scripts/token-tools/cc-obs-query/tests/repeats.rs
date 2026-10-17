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

/// One clean case per pattern, each in its own session.
fn one_of_each() -> Vec<Rec> {
    vec![
        Rec("s1", "m", "Read", "a", "pa", 1_000, 1, 0),
        Rec("s1", "m", "Read", "a", "pa", 1_000, 2, 1),
        Rec("s2", "m", "Grep", "g1", "pg", 100, 1, 0),
        Rec("s2", "m", "Grep", "g2", "pg", 100, 2, 1),
        Rec("s3", "m", "Glob", "l1", "pl1", 30_000, 1, 0),
        Rec("s3", "m", "Glob", "l2", "pl2", 1_000, 2, 1),
        Rec("s4", "m", "Edit", "e1", "pe1", 10, 1, 0),
        Rec("s4", "m", "Write", "w1", "pw1", 10, 2, 1),
        Rec("s4", "m", "Bash", "b1", "pb1", 10, 3, 2),
        Rec("s4", "m", "Edit", "e2", "pe2", 10, 4, 3),
        Rec("s4", "m", "Write", "w2", "pw2", 10, 5, 4),
        Rec("s4", "m", "Bash", "b2", "pb2", 10, 6, 5),
    ]
}

#[test]
fn repeats_value_and_calls_semantics_per_pattern() {
    let out = run_repeats(loki(&one_of_each()), &[]);
    // value is calls saved if the pattern went away; calls is how many times the
    // pattern was seen (group size, pair, or sequence occurrences).
    let expect = [
        ("identical:Read", 1, 2),
        ("near_identical:Grep", 1, 2),
        ("large_then_narrow:Glob", 1, 2),
        // Two occurrences of a triple: one tool replacing it saves 2 calls each.
        ("sequence:Edit>Write>Bash", 4, 2),
    ];
    for (key, value, calls) in expect {
        let r = row(&out, key);
        assert_eq!(r["value"], json!(value), "{key} value in {out}");
        assert_eq!(r["calls"], json!(calls), "{key} calls in {out}");
    }
    assert_eq!(
        rows(&out)[0]["key"],
        json!("sequence:Edit>Write>Bash"),
        "rows rank by calls saved: {out}"
    );
    assert!(out["value_means"].is_string(), "{out}");
}

fn triple(session: &'static str) -> Vec<Rec> {
    vec![
        Rec(session, "m", "Edit", "e", "pe", 10, 1, 0),
        Rec(session, "m", "Write", "w", "pw", 10, 2, 1),
        Rec(session, "m", "Bash", "b", "pb", 10, 3, 2),
    ]
}

#[test]
fn min_count_is_per_session_for_groups_and_across_sessions_for_sequences() {
    // Each of three sessions holds the triple once and one repeated Read.
    let mut recs = Vec::new();
    for s in ["s1", "s2", "s3"] {
        recs.push(Rec(s, "m", "Read", "a", "pa", 10, 0, 0));
        recs.push(Rec(s, "m", "Read", "a", "pa", 10, 0, 1));
        recs.extend(triple(s));
    }
    let out = run_repeats(loki(&recs), &["--min-count", "3"]);
    assert!(!has(&out, "identical:Read"), "{out}");
    assert!(has(&out, "sequence:Edit>Write>Bash"), "{out}");
    assert!(out["min_count_means"].is_string(), "{out}");
}

#[test]
fn near_identical_counts_calls_that_also_form_an_identical_group() {
    // Three identical calls share one input: that is identical, not near-identical.
    let same: Vec<Rec> = (0..3)
        .map(|i| Rec("s1", "m", "Grep", "g", "pg", 10, i, i))
        .collect();
    let out = run_repeats(loki(&same), &[]);
    assert!(!has(&out, "near_identical:Grep"), "{out}");
    // Two identical plus one differing input: near-identical over all three calls.
    let mixed = [
        Rec("s1", "m", "Grep", "g", "pg", 10, 0, 0),
        Rec("s1", "m", "Grep", "g", "pg", 10, 1, 1),
        Rec("s1", "m", "Grep", "h", "pg", 10, 2, 2),
    ];
    let out = run_repeats(loki(&mixed), &[]);
    let near = row(&out, "near_identical:Grep");
    assert_eq!(
        (near["value"].clone(), near["calls"].clone()),
        (json!(1), json!(3))
    );
    assert_eq!(row(&out, "identical:Grep")["value"], json!(1));
}

#[test]
fn min_count_boundaries_are_inclusive_and_floor_at_two() {
    let pair = [
        Rec("s1", "m", "Read", "a", "pa", 10, 0, 0),
        Rec("s1", "m", "Read", "a", "pa", 10, 1, 1),
    ];
    for count in ["1", "2"] {
        let out = run_repeats(loki(&pair), &["--min-count", count]);
        assert!(has(&out, "identical:Read"), "min-count {count}: {out}");
    }
    let out = run_repeats(loki(&pair), &["--min-count", "3"]);
    assert!(!has(&out, "identical:Read"), "{out}");
    let three = [
        Rec("s1", "m", "Read", "a", "pa", 10, 0, 0),
        Rec("s1", "m", "Read", "a", "pa", 10, 1, 1),
        Rec("s1", "m", "Read", "a", "pa", 10, 2, 2),
    ];
    let out = run_repeats(loki(&three), &["--min-count", "3"]);
    assert!(has(&out, "identical:Read"), "{out}");
}

#[test]
fn equal_values_are_ordered_by_key() {
    let recs = [
        Rec("s1", "m", "Zed", "a", "pa", 10, 0, 0),
        Rec("s1", "m", "Zed", "a", "pa", 10, 1, 1),
        Rec("s1", "m", "Alpha", "b", "pb", 10, 2, 2),
        Rec("s1", "m", "Alpha", "b", "pb", 10, 3, 3),
    ];
    let out = run_repeats(loki(&recs), &[]);
    let keys: Vec<&Value> = rows(&out).iter().map(|r| &r["key"]).collect();
    assert_eq!(keys, [&json!("identical:Alpha"), &json!("identical:Zed")]);
}

#[test]
fn loki_truncation_is_reported_as_a_gap() {
    // A full page of 5000 records is served on every request, so the pager runs
    // until its record cap.
    let recs: Vec<Rec> = (0..5000)
        .map(|i| Rec("s1", "m", "Read", "a", "pa", 10, i, i))
        .collect();
    let out = run_repeats(loki(&recs), &[]);
    let gaps = out["gaps"].to_string();
    assert!(gaps.contains("loki: stopped at"), "{gaps}");
    assert_eq!(out["calls_analysed"], json!(50_000), "{out}");
}

#[test]
fn large_then_narrow_ignores_unrelated_next_call() {
    let recs = [
        Rec("s1", "main", "Read", "a", "pa", 30_000, 1, 0),
        Rec("s1", "main", "Bash", "x", "px", 100, 1, 1),
        Rec("s1", "main", "Grep", "y", "py", 100, 2, 2),
        Rec("s1", "main", "Read", "b", "pb", 1_000, 9, 3),
    ];
    let out = run_repeats(loki(&recs), &[]);
    assert!(
        !has(&out, "large_then_narrow:Read"),
        "a Read three calls later on another file was read as a narrowing: {out}"
    );
}

#[test]
fn large_then_narrow_flags_the_immediately_following_narrower_call() {
    let recs = [
        Rec("s1", "main", "Read", "a", "pa", 30_000, 1, 0),
        Rec("s1", "main", "Read", "b", "pb", 1_000, 1, 1),
    ];
    let out = run_repeats(loki(&recs), &[]);
    assert_eq!(row(&out, "large_then_narrow:Read")["value"], json!(1));
}
