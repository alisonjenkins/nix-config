#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]

mod common;

use common::{cli, row, rows, serve, with_own};
use serde_json::{json, Value};

const COUNTER: &str = "cc_obs_ledger_requests_total";

fn by_session(pairs: &[(&str, &str)]) -> String {
    let result: Vec<Value> = pairs
        .iter()
        .map(|(id, v)| json!({"metric": {"session_id": id, "agent": "main"}, "value": [1.0, v]}))
        .collect();
    json!({"status": "success", "data": {"resultType": "vector", "result": result}}).to_string()
}

fn counter_query(pairs: &[(&str, &str)]) -> String {
    let fake = serve(with_own(vec![(COUNTER, by_session(pairs))]));
    let run = cli(
        &fake,
        &["top", "session", "--by", "requests", "--since", "1d"],
    );
    assert_eq!(run.code, 0, "{}", run.err);
    let sent = fake.seen_matching(COUNTER);
    assert_eq!(sent.len(), 1, "{sent:?}");
    sent[0].clone()
}

#[test]
fn requests_are_the_counter_at_window_end_less_its_value_at_window_start() {
    let query = counter_query(&[("s", "2")]);
    assert!(!query.contains("increase("), "{query}");
    assert!(
        query.contains(&format!("last_over_time({COUNTER}")),
        "{query}"
    );
    assert!(
        query.contains("offset 86400s"),
        "pre-window value must be read one window back: {query}"
    );
}

#[test]
fn a_series_born_inside_the_window_counts_in_full() {
    // `or <end> * 0` stands in for a series with no value before the window, so a
    // single sample of 2 reads as 2 rather than as nothing.
    let query = counter_query(&[("s", "2")]);
    assert!(query.contains(") or last_over_time("), "{query}");
    assert!(query.contains(") * 0)"), "{query}");
}

#[test]
fn a_reset_never_makes_a_negative_count_and_idle_sessions_drop_out() {
    let query = counter_query(&[("s", "2")]);
    assert!(query.contains("clamp_min("), "{query}");
    assert!(query.trim_end().ends_with("> 0"), "{query}");
}

#[test]
fn the_counted_value_is_ranked() {
    let fake = serve(with_own(vec![(
        COUNTER,
        by_session(&[("big", "40"), ("two", "2")]),
    )]));
    let run = cli(&fake, &["top", "session", "--by", "requests"]);
    assert_eq!(run.code, 0, "{}", run.err);
    let out = run.json();
    assert_eq!(rows(&out).len(), 2, "{out}");
    assert_eq!(row(&out, "two")["value"], json!(2));
}
