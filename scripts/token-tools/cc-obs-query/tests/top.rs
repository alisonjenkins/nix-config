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
fn cache_hit_ratio_never_exceeds_one() {
    let fake = serve(with_own(vec![
        ("count by (session_id)", vector("session_id", &[("s", "6")])),
        ("type=\"cacheRead\"", vector("session_id", &[("s", "105")])),
        (
            "type=~\"cacheRead|cacheCreation|input\"",
            vector("session_id", &[("s", "100")]),
        ),
    ]));
    let run = cli(&fake, &["top", "session", "--by", "cache-hit"]);
    assert_eq!(run.code, 0, "{}", run.err);
    let out = run.json();
    let value = rows(&out)[0]["value"].as_f64().unwrap();
    assert!(value <= 1.0, "ratio {value}: {out}");
}

const EMPTY_PROM: &str = r#"{"status":"success","data":{"resultType":"vector","result":[]}}"#;
const EMPTY_LOKI: &str = r#"{"status":"success","data":{"resultType":"streams","result":[]}}"#;

fn catch_all(mut rules: Vec<(&'static str, String)>) -> Vec<(&'static str, String)> {
    rules.push(("event_name=", EMPTY_LOKI.to_owned()));
    rules.push(("/prom/", EMPTY_PROM.to_owned()));
    rules
}

fn loki_streams(session_ids: &[&str]) -> String {
    let streams: Vec<Value> = session_ids
        .iter()
        .map(|id| {
            json!({
                "stream": {"service_name": "claude-code", "event_name": "compaction", "session_id": id},
                "values": [["1760000000000000001", "compaction"]],
            })
        })
        .collect();
    json!({"status": "success", "data": {"resultType": "streams", "result": streams}}).to_string()
}

const REVIEW_ONLY: &str = "review_run=\"1\"";
const REVIEW_EXCLUDED: &str = "review_run!=\"1\"";

const REVIEW_COMMANDS: [&[&str]; 9] = [
    &["top", "skill"],
    &["top", "mcp"],
    &["top", "subagent"],
    &["top", "session"],
    &["top", "fixed"],
    &["top", "memory"],
    &["top", "session", "--by", "cache-hit"],
    &["top", "session", "--by", "compactions"],
    &["top", "memory", "--by", "hit-rate"],
];

#[test]
fn every_top_category_and_ranking_excludes_review_runs() {
    for args in REVIEW_COMMANDS {
        let fake = serve(catch_all(vec![]));
        let run = cli(&fake, args);
        assert_eq!(run.code, 0, "{args:?}: {}", run.err);
        let data: Vec<String> = fake
            .seen()
            .into_iter()
            .filter(|r| r.contains("/prom/api") || r.contains("/loki/api"))
            .filter(|r| !r.contains(REVIEW_ONLY))
            .collect();
        assert!(!data.is_empty(), "{args:?} sent no data query");
        for request in &data {
            assert!(
                request.contains(REVIEW_EXCLUDED),
                "{args:?} did not exclude review data: {request}"
            );
        }
        let mut full = args.to_vec();
        full.push("--include-review");
        let fake = serve(catch_all(vec![]));
        let run = cli(&fake, &full);
        assert_eq!(run.code, 0, "{full:?}: {}", run.err);
        for request in fake.seen() {
            assert!(
                !request.contains("review_run"),
                "{full:?} still filtered: {request}"
            );
        }
    }
}

#[test]
fn compactions_logql_excludes_review_runs() {
    let fake = serve(catch_all(vec![]));
    cli(&fake, &["top", "session", "--by", "compactions"]);
    let sent = fake.seen_matching("event_name=\"compaction\"");
    assert!(!sent.is_empty(), "{:?}", fake.seen());
    assert!(sent.iter().all(|r| r.contains(REVIEW_EXCLUDED)), "{sent:?}");
}

#[test]
fn compactions_skip_records_without_a_session_id() {
    let fake = serve(catch_all(vec![(
        "event_name=\"compaction\"",
        loki_streams(&["a", "", "a", "b"]),
    )]));
    let out = cli(&fake, &["top", "session", "--by", "compactions"]).json();
    let keys: Vec<(&str, i64)> = rows(&out)
        .iter()
        .map(|r| (r["key"].as_str().unwrap(), r["value"].as_i64().unwrap()))
        .collect();
    assert_eq!(keys, vec![("a", 2), ("b", 1)], "{out}");
}

#[test]
fn equal_values_sort_by_key_then_model() {
    let result = json!({"status": "success", "data": {"resultType": "vector", "result": [
        {"metric": {"agent_name": "b", "model": "x"}, "value": [1.0, "10"]},
        {"metric": {"agent_name": "a", "model": "z"}, "value": [1.0, "10"]},
        {"metric": {"agent_name": "a", "model": "y"}, "value": [1.0, "10"]},
    ]}})
    .to_string();
    let fake = serve(with_own(vec![("by (agent_name, model)", result)]));
    let out = cli(&fake, &["top", "subagent", "--by", "tokens"]).json();
    let order: Vec<&str> = rows(&out)
        .iter()
        .map(|r| r["evidence"].as_str().unwrap())
        .collect();
    assert_eq!(
        order,
        vec!["subagent:a@y", "subagent:a@z", "subagent:b@x"],
        "{out}"
    );
}

#[test]
fn cache_hit_min_requests_boundary_is_inclusive() {
    let rules = || {
        with_own(vec![
            (
                "count by (session_id)",
                vector("session_id", &[("five", "5"), ("four", "4"), ("one", "1")]),
            ),
            (
                "type=\"cacheRead\"",
                vector("session_id", &[("five", "1"), ("four", "1"), ("one", "1")]),
            ),
            (
                "type=~\"cacheRead|cacheCreation|input\"",
                vector(
                    "session_id",
                    &[("five", "10"), ("four", "10"), ("one", "10")],
                ),
            ),
        ])
    };
    let keys = |extra: &[&str]| {
        let fake = serve(rules());
        let mut args = vec!["top", "session", "--by", "cache-hit"];
        args.extend_from_slice(extra);
        let run = cli(&fake, &args);
        assert_eq!(run.code, 0, "{}", run.err);
        let out = run.json();
        let mut keys: Vec<String> = rows(&out)
            .iter()
            .map(|r| r["key"].as_str().unwrap().to_owned())
            .collect();
        keys.sort();
        keys
    };
    assert_eq!(keys(&["--min-requests", "5"]), vec!["five"]);
    assert_eq!(keys(&["--min-requests", "4"]), vec!["five", "four"]);
    assert_eq!(keys(&["--min-requests", "0"]), vec!["five", "four", "one"]);
}

#[test]
fn hit_rate_counts_missing_hits_as_zero_and_skips_zero_requests() {
    let fake = serve(with_own(vec![
        (
            "recall_requests_total",
            vector("service", &[("busy", "10"), ("idle", "0"), ("hit", "4")]),
        ),
        ("recall_hits_total", vector("service", &[("hit", "2")])),
    ]));
    let out = cli(&fake, &["top", "memory", "--by", "hit-rate"]).json();
    let got: Vec<(&str, f64)> = rows(&out)
        .iter()
        .map(|r| (r["key"].as_str().unwrap(), r["value"].as_f64().unwrap()))
        .collect();
    assert_eq!(got, vec![("busy", 0.0), ("hit", 0.5)], "{out}");
}

#[test]
fn by_that_does_not_fit_the_category_is_unavailable_with_a_message() {
    let fake = serve(catch_all(vec![]));
    for (args, only) in [
        (vec!["top", "model", "--by", "cache-hit"], "session"),
        (vec!["top", "model", "--by", "compactions"], "session"),
        (vec!["top", "session", "--by", "hit-rate"], "memory"),
    ] {
        let run = cli(&fake, &args);
        assert_eq!(run.code, 0, "{args:?}: {}", run.err);
        let out = run.json();
        let why = out["unavailable"].as_str().unwrap();
        assert!(
            why.contains(&format!("`top {only}` only")),
            "{args:?}: {out}"
        );
        assert_eq!(rows(&out).len(), 0, "{out}");
    }
}

#[test]
fn share_is_zero_when_every_value_is_zero() {
    let fake = serve(with_own(vec![(
        "by (model)",
        vector("model", &[("a", "0"), ("b", "0")]),
    )]));
    let out = cli(&fake, &["top", "model", "--by", "tokens"]).json();
    assert_eq!(share_of(&out, "a"), Some(0.0), "{out}");
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
