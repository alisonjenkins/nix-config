#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]

mod common;

use common::{cli, row, serve, with_own};
use serde_json::{json, Value};

fn vector(series: &[(Value, &str)]) -> String {
    let result: Vec<Value> = series
        .iter()
        .map(|(labels, value)| json!({"metric": labels, "value": [1760000000.0, value]}))
        .collect();
    json!({"status": "success", "data": {"resultType": "vector", "result": result}}).to_string()
}

fn recall_with(outcomes: &[(&str, &str)], hits: &str, tokens: &str) -> Vec<(&'static str, String)> {
    let by_outcome: Vec<(Value, &str)> = outcomes
        .iter()
        .map(|(o, v)| (json!({"outcome": o}), *v))
        .collect();
    with_own(vec![
        ("by (outcome)", vector(&by_outcome)),
        (
            "sum(increase(recall_hits_total",
            vector(&[(json!({}), hits)]),
        ),
        (
            "sum(increase(recall_tokens_injected_total",
            vector(&[(json!({}), tokens)]),
        ),
    ])
}

fn recall_value(out: &Value, key: &str) -> Value {
    row(out, key)["value"].clone()
}

/// A figure is a bare number, or `{"value": null, "unavailable": why}`.
fn val(cell: &Value) -> Value {
    cell.get("value").cloned().unwrap_or_else(|| cell.clone())
}

fn why(cell: &Value) -> String {
    cell["unavailable"].as_str().unwrap_or_default().to_owned()
}

#[test]
fn recall_per_prompt_still_divides_by_all_requests() {
    let fake = serve(recall_with(
        &[("success", "50"), ("empty", "30"), ("error", "20")],
        "40",
        "5000",
    ));
    let out = cli(&fake, &["recall"]).json();
    assert_eq!(recall_value(&out, "injected_tokens_per_prompt"), json!(50));
}

#[test]
fn recall_per_injection_divides_by_requests_that_injected() {
    let fake = serve(recall_with(
        &[("success", "50"), ("empty", "30"), ("error", "20")],
        "40",
        "5000",
    ));
    let out = cli(&fake, &["recall"]).json();
    assert_eq!(
        recall_value(&out, "injected_tokens_per_injection"),
        json!(100),
        "{out}"
    );
}

#[test]
fn recall_per_injection_unavailable_when_every_request_was_empty_or_error() {
    let fake = serve(recall_with(&[("empty", "30"), ("error", "20")], "0", "0"));
    let out = cli(&fake, &["recall"]).json();
    let field = recall_value(&out, "injected_tokens_per_injection");
    assert_eq!(val(&field), json!(null), "{out}");
    assert!(!why(&field).is_empty(), "{out}");
}

fn compare_run(question_command: &str, rules: Vec<(&'static str, String)>) -> Value {
    let dir = tempfile::tempdir().unwrap();
    let yaml = common::TOOL_PACK.replace("top tool --by tokens", question_command);
    let pack = common::write_pack(dir.path(), &yaml);
    let fake = serve(rules);
    let run = cli(
        &fake,
        &[
            "compare",
            "tool-result-size",
            "--a",
            "2026-09-01..2026-09-08",
            "--b",
            "2026-09-08..2026-09-15",
            "--pack",
            common::s(&pack),
        ],
    );
    assert_eq!(run.code, 0, "{}", run.err);
    run.json()
}

const END_A: &str = "time=1788825600";
const END_B: &str = "time=1789430400";

#[test]
fn compare_key_only_in_a_is_zero_in_b_when_b_is_complete() {
    let a = vector(&[
        (json!({"model": "opus"}), "100"),
        (json!({"model": "old"}), "5"),
    ]);
    let b = vector(&[(json!({"model": "opus"}), "150")]);
    let out = compare_run("top model --by tokens", vec![(END_A, a), (END_B, b)]);
    let old = common::row(&out, "old");
    assert_eq!(val(&old["a"]), json!(5), "{out}");
    assert_eq!(val(&old["b"]), json!(0), "{out}");
    assert_eq!(val(&old["delta"]), json!(-5), "{out}");
    assert_eq!(val(&old["ratio"]), json!(0), "{out}");
}

#[test]
fn compare_key_in_both_ranges_is_unchanged() {
    let a = vector(&[(json!({"model": "opus"}), "100")]);
    let b = vector(&[(json!({"model": "opus"}), "150")]);
    let out = compare_run("top model --by tokens", vec![(END_A, a), (END_B, b)]);
    let opus = common::row(&out, "opus");
    assert_eq!(val(&opus["delta"]), json!(50), "{out}");
    assert_eq!(val(&opus["ratio"]), json!(1.5), "{out}");
}

#[test]
fn compare_zero_in_a_has_delta_but_no_ratio() {
    let a = vector(&[(json!({"model": "opus"}), "100")]);
    let b = vector(&[
        (json!({"model": "opus"}), "100"),
        (json!({"model": "new"}), "10"),
    ]);
    let out = compare_run("top model --by tokens", vec![(END_A, a), (END_B, b)]);
    let new = common::row(&out, "new");
    assert_eq!(val(&new["a"]), json!(0), "{out}");
    assert_eq!(val(&new["delta"]), json!(10), "{out}");
    assert_eq!(val(&new["ratio"]), json!(null), "{out}");
    assert!(!why(&new["ratio"]).is_empty(), "{out}");
}

/// One Loki page of `count` compaction events for session `session`, one
/// nanosecond apart. Loki-backed rankings are the only ones with a row cap.
fn compactions(session: &str, count: usize) -> String {
    let values: Vec<Value> = (0..count)
        .map(|i| {
            json!([
                (1_760_000_000_000_000_000_i64 + i as i64).to_string(),
                "compaction"
            ])
        })
        .collect();
    json!({"status": "success", "data": {"resultType": "streams", "result": [{
        "stream": {"service_name": "claude-code", "event_name": "compaction", "session_id": session},
        "values": values,
    }]}})
    .to_string()
}

const LOKI_END_A: &str = "end=1788825600000000000";
const LOKI_END_B: &str = "end=1789430400000000000";

#[test]
fn compare_key_missing_from_a_truncated_range_is_unavailable_not_zero() {
    // A full page on every request makes the fetch hit its record cap.
    let a = compactions("only-in-a", 2);
    let b = compactions("s-big", 5000);
    let out = compare_run(
        "top session --by compactions",
        vec![(LOKI_END_A, a), (LOKI_END_B, b)],
    );
    let only_a = common::row(&out, "only-in-a");
    assert_eq!(val(&only_a["a"]), json!(2), "{out}");
    assert_eq!(val(&only_a["b"]), json!(null), "{out}");
    for field in ["b", "delta", "ratio"] {
        let reason = why(&only_a[field]);
        assert!(
            reason.contains("outside top") && reason.contains("range B"),
            "{field}: {out}"
        );
    }
}
