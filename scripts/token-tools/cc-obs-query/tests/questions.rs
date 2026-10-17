#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]

//! The shipped question pack must ask what its query answers.

mod common;

use cc_obs_query::pack::Pack;
use common::{cli, digest_rules, fixture, s, serve, write_pack};
use serde_json::{json, Value};

fn vector(samples: &[(&[(&str, &str)], &str)]) -> String {
    let result: Vec<Value> = samples
        .iter()
        .map(|(labels, value)| {
            let metric: serde_json::Map<String, Value> = labels
                .iter()
                .map(|(k, v)| ((*k).to_owned(), json!(v)))
                .collect();
            json!({"metric": metric, "value": [1.0, value]})
        })
        .collect();
    json!({"status": "success", "data": {"resultType": "vector", "result": result}}).to_string()
}

fn digest_questions(pack_yaml: &str, rules: Vec<(&'static str, String)>) -> Vec<Value> {
    let dir = tempfile::tempdir().unwrap();
    let pack = write_pack(dir.path(), pack_yaml);
    let fake = serve(rules);
    let run = cli(
        &fake,
        &[
            "digest",
            "--baseline",
            "--pack",
            s(&pack),
            "--since",
            "7d",
            "--until",
            "2026-10-09",
        ],
    );
    assert_eq!(run.code, 0, "{}", run.err);
    run.json()["questions"].as_array().unwrap().clone()
}

fn recall_rules(requests: String, hits: String) -> Vec<(&'static str, String)> {
    let mut rules = vec![
        ("recall_requests_total", requests),
        ("recall_hits_total", hits),
    ];
    rules.extend(digest_rules(fixture("loki_tool_results.json")));
    rules
}

fn keys_of(question: &Value) -> Vec<String> {
    question["rows"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| r["key"].as_str().unwrap().to_owned())
        .collect()
}

const HIT_RATE_PACK: &str = "version: 1\nquestions:\n  - id: memory\n    title: Which recall services return a match on the fewest requests?\n    signals: [recall_requests_total, recall_hits_total]\n    query: { command: \"cc-obs-query top memory --by hit-rate\" }\n    decision_kind: configure\n    threshold: { max_value: 0.5 }\n";

#[test]
fn max_value_threshold_keeps_only_rows_at_or_below_it() {
    let requests = vector(&[
        (&[("service", "skills")], "100"),
        (&[("service", "notes")], "100"),
        (&[("service", "docs")], "100"),
    ]);
    let hits = vector(&[
        (&[("service", "skills")], "20"),
        (&[("service", "notes")], "50"),
        (&[("service", "docs")], "90"),
    ]);
    let questions = digest_questions(HIT_RATE_PACK, recall_rules(requests, hits));
    assert_eq!(keys_of(&questions[0]), vec!["skills", "notes"]);
}

#[test]
fn min_value_threshold_drops_rows_below_it() {
    let yaml = HIT_RATE_PACK.replace("max_value: 0.5", "min_value: 0.3");
    let requests = vector(&[
        (&[("service", "skills")], "100"),
        (&[("service", "docs")], "100"),
    ]);
    let hits = vector(&[
        (&[("service", "skills")], "20"),
        (&[("service", "docs")], "90"),
    ]);
    let questions = digest_questions(&yaml, recall_rules(requests, hits));
    assert_eq!(keys_of(&questions[0]), vec!["docs"]);
}

#[test]
fn value_thresholds_that_cannot_match_anything_are_rejected() {
    for bad in [
        "{ min_value: 0.9, max_value: 0.1 }",
        "{ min_value: .nan }",
        "{ max_value: .inf }",
    ] {
        let dir = tempfile::tempdir().unwrap();
        let yaml = HIT_RATE_PACK.replace("{ max_value: 0.5 }", bad);
        let path = write_pack(dir.path(), &yaml);
        let err = Pack::load(&path).unwrap_err().to_string();
        assert!(err.contains("threshold"), "{bad}: {err}");
    }
}
