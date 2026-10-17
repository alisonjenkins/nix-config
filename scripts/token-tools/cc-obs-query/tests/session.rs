#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]

mod common;

use common::{cli, fixture, rows, serve, with_own};
use serde_json::{json, Value};

/// One instant-vector body; each series is (labels, value).
fn vector(series: &[(Value, &str)]) -> String {
    let result: Vec<Value> = series
        .iter()
        .map(|(labels, value)| json!({"metric": labels, "value": [1760000000.0, value]}))
        .collect();
    json!({"status": "success", "data": {"resultType": "vector", "result": result}}).to_string()
}

fn ledger(agent: &str, turn: &str) -> Value {
    json!({"session_id": "s1", "agent": agent, "model": "m", "turn": turn})
}

fn session_rules(context: String, cache: String, fixed: String) -> Vec<(&'static str, String)> {
    with_own(vec![
        ("cc_obs_ledger_context_tokens", context),
        ("cc_obs_ledger_cache_hit_ratio", cache),
        ("cc_obs_ledger_fixed_context_tokens", fixed),
    ])
}

fn main_and_subagent(main_first: bool) -> Vec<(&'static str, String)> {
    let main_ctx = (ledger("main", "3"), "500000");
    let sub_ctx = (ledger("subagent", "3"), "40000");
    let main_cache = (ledger("main", "3"), "0.9");
    let sub_cache = (ledger("subagent", "3"), "0.1");
    let (context, cache) = if main_first {
        (
            vector(&[main_ctx, sub_ctx]),
            vector(&[main_cache, sub_cache]),
        )
    } else {
        (
            vector(&[sub_ctx, main_ctx]),
            vector(&[sub_cache, main_cache]),
        )
    };
    session_rules(context, cache, fixture("prom_session_fixed.json"))
}

#[test]
fn session_new_tokens_unavailable_when_fixed_exceeds_max_context() {
    let context = vector(&[(ledger("main", "1"), "8000")]);
    let cache = vector(&[(ledger("main", "1"), "0.5")]);
    let fixed = vector(&[(json!({"component": "total"}), "10000")]);
    let fake = serve(session_rules(context, cache, fixed));
    let out = cli(&fake, &["session", "s1"]).json();
    assert_eq!(out["new_tokens"]["value"], json!(null), "{out}");
    assert!(
        out["new_tokens"]["unavailable"]
            .as_str()
            .unwrap()
            .contains("fixed"),
        "{out}"
    );
}

fn gaps(out: &Value) -> String {
    out["gaps"].to_string()
}

#[test]
fn session_series_without_turn_label_reported_as_gap() {
    let no_turn = json!({"session_id": "s1", "agent": "main", "model": "m"});
    let bad_turn = json!({"session_id": "s1", "agent": "main", "model": "m", "turn": "x"});

    let partial = vector(&[(ledger("main", "1"), "9000"), (no_turn.clone(), "70000")]);
    let fake = serve(session_rules(
        partial,
        vector(&[]),
        fixture("prom_session_fixed.json"),
    ));
    let out = cli(&fake, &["session", "s1"]).json();
    assert_eq!(out["max_context_tokens"], json!(9000), "{out}");
    assert!(
        gaps(&out).contains("turn"),
        "partial drop not reported: {out}"
    );

    let all_dropped = vector(&[(no_turn, "70000"), (bad_turn, "80000")]);
    let fake = serve(session_rules(
        all_dropped,
        vector(&[]),
        fixture("prom_session_fixed.json"),
    ));
    let out = cli(&fake, &["session", "s1"]).json();
    assert_eq!(out["value"], json!(null), "{out}");
    let why = out["unavailable"].as_str().unwrap();
    assert!(why.contains("turn"), "{out}");
    assert!(
        gaps(&out).contains("turn"),
        "total drop not reported: {out}"
    );
}

#[test]
fn session_main_and_subagent_in_one_turn_do_not_collide() {
    for main_first in [true, false] {
        let fake = serve(main_and_subagent(main_first));
        let out = cli(&fake, &["session", "s1"]).json();
        assert_eq!(
            out["max_context_tokens"],
            json!(500000),
            "main_first={main_first}: {out}"
        );
        assert_eq!(out["turns"], json!(1), "main_first={main_first}: {out}");
        let detail = cli(&fake, &["session", "s1", "--detail"]).json();
        assert_eq!(rows(&detail).len(), 1, "{detail}");
        assert_eq!(rows(&detail)[0]["context_tokens"], json!(500000));
        assert_eq!(
            rows(&detail)[0]["cache_hit_ratio"],
            json!(0.9),
            "ratio must come from the same series as the context: {detail}"
        );
    }
}

fn health_rules(guard: Option<String>, tempo_up: bool) -> Vec<(&'static str, String)> {
    let mut rules = vec![
        ("/prom/-/ready", "ready".to_owned()),
        ("/loki/ready", "ready".to_owned()),
    ];
    if tempo_up {
        rules.push(("/tempo/ready", "ready".to_owned()));
    }
    if let Some(body) = guard {
        rules.push(("observability_guard_over_budget", body));
    }
    rules
}

fn guards(values: &[&str]) -> String {
    let series: Vec<(Value, &str)> = values
        .iter()
        .enumerate()
        .map(|(i, v)| (json!({"host": format!("h{i}")}), *v))
        .collect();
    vector(&series)
}

#[test]
fn health_guard_over_budget_when_any_series_is_one() {
    for order in [["0", "1"], ["1", "0"]] {
        let fake = serve(health_rules(Some(guards(&order)), true));
        let out = cli(&fake, &["health"]).json();
        assert_eq!(out["guard"], json!("over_budget"), "order {order:?}: {out}");
    }
}

#[test]
fn health_guard_ok_when_every_series_is_zero() {
    let fake = serve(health_rules(Some(guards(&["0", "0"])), true));
    let out = cli(&fake, &["health"]).json();
    assert_eq!(out["guard"], json!("ok"), "{out}");
}

#[test]
fn health_guard_absent_is_unavailable() {
    let fake = serve(health_rules(Some(guards(&[])), true));
    let out = cli(&fake, &["health"]).json();
    assert_eq!(out["guard"]["value"], json!(null), "{out}");
    assert!(out["guard"]["unavailable"].is_string(), "{out}");
}

#[test]
fn health_store_down_with_guard_unknown_reports_both() {
    let fake = serve(health_rules(None, false));
    let run = cli(&fake, &["health"]);
    assert_eq!(run.code, 0, "{}", run.err);
    let out = run.json();
    assert_eq!(out["stores_ok"], json!(false), "{out}");
    assert_eq!(out["guard"]["value"], json!(null), "{out}");
    assert_eq!(common::row(&out, "tempo")["value"], json!("down"));
}

#[test]
fn health_guard_nan_is_pinned() {
    // Pinned current behaviour: a NaN sample is discarded on parse, so the guard
    // reads as having published nothing.
    let fake = serve(health_rules(Some(guards(&["NaN"])), true));
    let out = cli(&fake, &["health"]).json();
    assert_eq!(out["guard"]["value"], json!(null), "{out}");
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

#[test]
fn recall_counts_are_whole_numbers() {
    // increase() extrapolates, so a window of integer counters yields fractions.
    let fake = serve(recall_with(
        &[("success", "79.6"), ("empty", "15.2"), ("error", "5.1")],
        "59.7",
        "24000.4",
    ));
    let out = cli(&fake, &["recall"]).json();
    let value = |key: &str| common::row(&out, key)["value"].clone();
    assert_eq!(value("requests"), json!(100), "{out}");
    assert_eq!(value("empty_requests"), json!(15), "{out}");
    assert_eq!(value("failures"), json!(5), "{out}");
    assert_eq!(value("matches_used"), json!(60), "{out}");
}

#[test]
fn recall_denominator_is_all_requests_including_empty_and_error() {
    // Pinned, not endorsed: specs/007 does not say what "per prompt" divides by.
    let fake = serve(recall_with(
        &[("success", "50"), ("empty", "30"), ("error", "20")],
        "40",
        "5000",
    ));
    let out = cli(&fake, &["recall"]).json();
    assert_eq!(
        common::row(&out, "injected_tokens_per_prompt")["value"],
        json!(50),
        "{out}"
    );
}

#[test]
fn recall_error_only_window_reports_failures_and_no_hits() {
    let fake = serve(recall_with(&[("error", "7")], "0", "0"));
    let out = cli(&fake, &["recall"]).json();
    let value = |key: &str| common::row(&out, key)["value"].clone();
    assert_eq!(value("requests"), json!(7), "{out}");
    assert_eq!(value("failures"), json!(7), "{out}");
    assert_eq!(value("empty_requests"), json!(0), "{out}");
    assert_eq!(value("injected_tokens_per_prompt"), json!(0), "{out}");
}

#[test]
fn recall_empty_outcome_is_counted_separately() {
    let fake = serve(recall_with(
        &[("success", "10"), ("empty", "4")],
        "10",
        "100",
    ));
    let out = cli(&fake, &["recall"]).json();
    let value = |key: &str| common::row(&out, key)["value"].clone();
    assert_eq!(value("empty_requests"), json!(4), "{out}");
    assert_eq!(value("failures"), json!(0), "{out}");
    assert_eq!(value("requests"), json!(14), "{out}");
}
