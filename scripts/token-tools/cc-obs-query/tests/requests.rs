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
const OLD_SERIES: &str = "count by (session_id)";
const CACHE_READ: &str = "type=\"cacheRead\"";
const PROMPT: &str = "type=~\"cacheRead|cacheCreation|input\"";

fn by_session(pairs: &[(&str, &str)]) -> String {
    let result: Vec<Value> = pairs
        .iter()
        .map(|(id, v)| json!({"metric": {"session_id": id}, "value": [1.0, v]}))
        .collect();
    json!({"status": "success", "data": {"resultType": "vector", "result": result}}).to_string()
}

fn rules(counter: String, old_series: String) -> Vec<(&'static str, String)> {
    with_own(vec![
        (COUNTER, counter),
        (OLD_SERIES, old_series),
        (CACHE_READ, by_session(&[("loop", "900"), ("cold", "0")])),
        (PROMPT, by_session(&[("loop", "1000"), ("cold", "1000")])),
    ])
}

fn keys(out: &Value) -> Vec<String> {
    rows(out)
        .iter()
        .map(|r| r["key"].as_str().unwrap().to_owned())
        .collect()
}

#[test]
fn a_tool_loop_of_many_requests_in_one_turn_is_not_dropped() {
    // the old series count sees one series for "loop"; the counter sees 12 requests
    let fake = serve(rules(
        by_session(&[("loop", "12"), ("cold", "1")]),
        by_session(&[("loop", "1"), ("cold", "1")]),
    ));
    let run = cli(
        &fake,
        &[
            "top",
            "session",
            "--by",
            "cache-hit",
            "--format",
            "detailed",
        ],
    );
    assert_eq!(run.code, 0, "{}", run.err);
    let out = run.json();
    assert_eq!(keys(&out), vec!["loop"], "{out}");
    assert_eq!(row(&out, "loop")["requests"], json!(12));
    let sent = fake.seen_matching(COUNTER);
    assert!(
        sent[0].contains("round(sum by (session_id)(increase("),
        "{sent:?}"
    );
}

#[test]
fn without_the_counter_it_falls_back_to_the_series_count_and_says_so() {
    let empty = r#"{"status":"success","data":{"resultType":"vector","result":[]}}"#;
    let fake = serve(rules(
        empty.to_owned(),
        by_session(&[("loop", "6"), ("cold", "1")]),
    ));
    let run = cli(&fake, &["top", "session", "--by", "cache-hit"]);
    assert_eq!(run.code, 0, "{}", run.err);
    let out = run.json();
    assert_eq!(keys(&out), vec!["loop"], "{out}");
    assert!(
        out.to_string().contains(COUNTER),
        "no gap names the missing counter: {out}"
    );
}
