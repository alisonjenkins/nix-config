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
