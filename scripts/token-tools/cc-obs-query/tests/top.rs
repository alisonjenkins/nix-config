#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]

mod common;

use common::{cli, rows, serve, with_own};
use serde_json::{json, Value};

fn vector(label: &str, pairs: &[(&str, &str)]) -> String {
    let result: Vec<Value> = pairs
        .iter()
        .map(|(id, v)| json!({"metric": {label: id}, "value": [1.0, v]}))
        .collect();
    json!({"status": "success", "data": {"resultType": "vector", "result": result}}).to_string()
}

fn share_of(out: &Value, key: &str) -> Option<f64> {
    rows(out)
        .iter()
        .find(|r| r["key"] == key)
        .map(|r| r["share"].as_f64().unwrap())
}

#[test]
fn top_model_keeps_series_without_a_model_label() {
    let fake = serve(with_own(vec![(
        "by (model)",
        vector("model", &[("", "50"), ("opus", "50")]),
    )]));
    let run = cli(&fake, &["top", "model", "--by", "tokens"]);
    assert_eq!(run.code, 0, "{}", run.err);
    let out = run.json();
    assert_eq!(share_of(&out, "opus"), Some(0.5), "{out}");
    assert_eq!(share_of(&out, "(unattributed)"), Some(0.5), "{out}");
}

#[test]
fn top_subagent_keeps_series_without_an_agent_name() {
    let result = json!({"status": "success", "data": {"resultType": "vector", "result": [
        {"metric": {"agent_name": "", "model": "opus"}, "value": [1.0, "30"]},
        {"metric": {"agent_name": "Explore", "model": "opus"}, "value": [1.0, "70"]},
    ]}})
    .to_string();
    let fake = serve(with_own(vec![("by (agent_name, model)", result)]));
    let out = cli(&fake, &["top", "subagent", "--by", "tokens"]).json();
    assert_eq!(share_of(&out, "Explore"), Some(0.7), "{out}");
    assert_eq!(share_of(&out, "(unattributed)"), Some(0.3), "{out}");
}

#[test]
fn cache_hit_help_says_what_min_requests_counts() {
    let fake = serve(vec![]);
    let run = cli(&fake, &["top", "--help"]);
    assert!(
        run.out.contains("turn"),
        "help does not say the count is per turn/model/agent series: {}",
        run.out
    );
}

#[test]
fn top_fixed_does_not_rank_or_count_the_total_series() {
    let fake = serve(with_own(vec![(
        "by (component)",
        vector(
            "component",
            &[("total", "10000"), ("skills", "3000"), ("other", "7000")],
        ),
    )]));
    let run = cli(&fake, &["top", "fixed", "--by", "tokens"]);
    assert_eq!(run.code, 0, "{}", run.err);
    let out = run.json();
    assert_eq!(share_of(&out, "total"), None, "total ranked: {out}");
    let sum: f64 = rows(&out)
        .iter()
        .map(|r| r["share"].as_f64().unwrap())
        .sum();
    assert!((sum - 1.0).abs() < 1e-9, "shares sum to {sum}: {out}");
    assert!(
        (share_of(&out, "skills").unwrap() - 0.3).abs() < 1e-9,
        "{out}"
    );
    assert!(
        (share_of(&out, "other").unwrap() - 0.7).abs() < 1e-9,
        "{out}"
    );
}
