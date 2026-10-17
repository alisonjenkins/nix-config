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
