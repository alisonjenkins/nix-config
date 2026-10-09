#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]

mod common;

use common::{cli, fixture, serve, Fake};
use serde_json::json;

fn rules() -> Vec<(&'static str, String)> {
    vec![
        (
            "claude_code_token_usage_tokens_total{review_run=\"1\"",
            fixture("prom_scalar_review_tokens.json"),
        ),
        (
            "claude_code_cost_usage_USD_total{review_run=\"1\"}",
            fixture("prom_scalar_review_cost.json"),
        ),
        ("by (model)", fixture("prom_tokens_by_model.json")),
        (
            "event_name=\"tool_result\"",
            fixture("loki_tool_results.json"),
        ),
        (
            "event_name=\"cc_obs_ledger.tool_call\"",
            fixture("loki_ledger_calls.json"),
        ),
        (
            "cc_obs_ledger_context_tokens",
            fixture("prom_session_context.json"),
        ),
        (
            "cc_obs_ledger_cache_hit_ratio",
            fixture("prom_session_cache.json"),
        ),
        (
            "cc_obs_ledger_fixed_context_tokens",
            fixture("prom_session_fixed.json"),
        ),
        ("by (outcome)", fixture("prom_recall_requests.json")),
        (
            "sum(increase(recall_hits_total",
            fixture("prom_scalar_recall_hits.json"),
        ),
        (
            "sum(increase(recall_tokens_injected_total",
            fixture("prom_scalar_recall_tokens.json"),
        ),
    ]
}

const SELECTING: [&str; 5] = [
    "claude_code_token_usage_tokens_total{",
    "event_name=\"tool_result\"",
    "event_name=\"cc_obs_ledger.tool_call\"",
    "cc_obs_ledger_context_tokens{",
    "recall_requests_total{",
];

fn data_requests(fake: &Fake) -> Vec<String> {
    fake.seen()
        .into_iter()
        .filter(|r| SELECTING.iter().any(|n| r.contains(n)))
        .filter(|r| !r.contains("review_run=\"1\""))
        .collect()
}

const COMMANDS: [&[&str]; 5] = [
    &["top", "model"],
    &["tool", "Read"],
    &["session", "s1"],
    &["repeats"],
    &["recall"],
];

#[test]
fn review_runs_are_excluded_by_default() {
    for args in COMMANDS {
        let fake = serve(rules());
        let run = cli(&fake, args);
        assert_eq!(run.code, 0, "{args:?}: {}", run.err);
        let sent = data_requests(&fake);
        assert!(!sent.is_empty(), "{args:?} sent no data query");
        for request in &sent {
            assert!(
                request.contains("review_run!=\"1\""),
                "{args:?} did not exclude review data: {request}"
            );
        }
    }
}

#[test]
fn excluded_spend_is_reported_as_own_cost() {
    let fake = serve(rules());
    let out = cli(&fake, &["top", "model"]).json();
    assert_eq!(
        out["own_cost"],
        json!({"tokens": 5000, "est_cost_usd": 0.31})
    );
}

#[test]
fn include_review_drops_the_filter_and_the_own_cost() {
    for args in COMMANDS {
        let fake = serve(rules());
        let mut full = args.to_vec();
        full.push("--include-review");
        let run = cli(&fake, &full);
        assert_eq!(run.code, 0, "{full:?}: {}", run.err);
        for request in data_requests(&fake) {
            assert!(
                !request.contains("review_run"),
                "{full:?} still filtered: {request}"
            );
        }
        assert!(run.json().get("own_cost").is_none(), "{full:?}");
    }
}

#[test]
fn own_cost_is_unavailable_when_the_review_left_no_samples() {
    let mut r = rules();
    r.insert(
        0,
        ("tokens_total{review_run=\"1\"", fixture("prom_empty.json")),
    );
    let fake = serve(r);
    let out = cli(&fake, &["top", "model"]).json();
    assert_eq!(out["own_cost"]["tokens"]["value"], json!(null));
}
