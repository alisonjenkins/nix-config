#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]

mod common;

use cc_obs_query::backend::{Backend, Endpoints};
use common::{cli, fixture, row, rows, serve};
use serde_json::json;

const REVIEW_TOKENS: &str = "claude_code_token_usage_tokens_total{review_run=\"1\"";
const REVIEW_COST: &str = "claude_code_cost_usage_USD_total{review_run=\"1\"}";

fn own_rules() -> Vec<(&'static str, String)> {
    vec![
        (REVIEW_TOKENS, fixture("prom_scalar_review_tokens.json")),
        (REVIEW_COST, fixture("prom_scalar_review_cost.json")),
    ]
}

fn with_own(mut rules: Vec<(&'static str, String)>) -> Vec<(&'static str, String)> {
    rules.extend(own_rules());
    rules
}

#[test]
fn top_model_ranks_by_tokens_with_shares() {
    let fake = serve(with_own(vec![(
        "by (model)",
        fixture("prom_tokens_by_model.json"),
    )]));
    let run = cli(&fake, &["top", "model", "--since", "7d"]);
    assert_eq!(run.code, 0, "{}", run.err);
    let out = run.json();
    let keys: Vec<_> = rows(&out).iter().map(|r| r["key"].clone()).collect();
    assert_eq!(
        keys,
        vec![
            json!("claude-opus-4"),
            json!("claude-sonnet-5"),
            json!("claude-haiku-5")
        ]
    );
    assert_eq!(rows(&out)[0]["value"], json!(90000));
    assert_eq!(rows(&out)[0]["share"], json!(0.6923));
    assert_eq!(rows(&out)[0]["evidence"], json!("model:claude-opus-4"));
    assert!(out.get("truncated").is_none());
}

#[test]
fn top_respects_limit_and_marks_truncation() {
    let fake = serve(with_own(vec![(
        "by (model)",
        fixture("prom_tokens_by_model.json"),
    )]));
    let out = cli(&fake, &["top", "model", "--limit", "2"]).json();
    assert_eq!(rows(&out).len(), 2);
    assert_eq!(out["truncated"], json!(true));
    assert_eq!(out["next"], json!("--offset 2"));
    let next = cli(&fake, &["top", "model", "--limit", "2", "--offset", "2"]).json();
    assert_eq!(rows(&next).len(), 1);
    assert_eq!(rows(&next)[0]["key"], json!("claude-haiku-5"));
    assert!(next.get("truncated").is_none());
}

#[test]
fn top_tool_estimates_tokens_from_result_bytes() {
    let fake = serve(with_own(vec![(
        "event_name=\"tool_result\"",
        fixture("loki_tool_results.json"),
    )]));
    let out = cli(&fake, &["top", "tool"]).json();
    let keys: Vec<_> = rows(&out).iter().map(|r| r["key"].clone()).collect();
    assert_eq!(keys, vec![json!("Read"), json!("Grep"), json!("Bash")]);
    assert_eq!(row(&out, "Read")["value"], json!(25000));
    assert_eq!(row(&out, "Read")["calls"], json!(2));
}

#[test]
fn top_with_no_samples_is_unavailable_not_zero() {
    let fake = serve(with_own(vec![("by (model)", fixture("prom_empty.json"))]));
    let run = cli(&fake, &["top", "model"]);
    assert_eq!(run.code, 0, "{}", run.err);
    let out = run.json();
    assert_eq!(out["value"], json!(null));
    assert!(out["unavailable"].as_str().unwrap().contains("no samples"));
    assert_eq!(rows(&out).len(), 0);
}

#[test]
fn top_fixed_by_cost_is_unavailable() {
    let fake = serve(with_own(vec![]));
    let out = cli(&fake, &["top", "fixed", "--by", "cost"]).json();
    assert_eq!(out["value"], json!(null));
    assert!(out["unavailable"].as_str().unwrap().contains("cost"));
}

#[test]
fn top_session_adds_cache_hit_ratio_detail_when_asked() {
    let fake = serve(with_own(vec![
        ("cc_obs_ledger_cache_hit_ratio", {
            r#"{"status":"success","data":{"resultType":"vector","result":[{"metric":{"session_id":"s1"},"value":[1760000000.0,"0.42"]}]}}"#.to_owned()
        }),
        ("by (session_id)", fixture("prom_tokens_by_session.json")),
    ]));
    let out = cli(&fake, &["top", "session", "--format", "detailed"]).json();
    assert_eq!(row(&out, "s1")["cache_hit_ratio"], json!(0.42));
    assert_eq!(
        row(&out, "s2")["cache_hit_ratio"]["value"],
        json!(null),
        "missing ratio must be unavailable, not zero"
    );
}

#[test]
fn tool_reports_calls_sizes_share_and_repeat_rate() {
    let fake = serve(with_own(vec![
        (
            "event_name=\"tool_result\"",
            fixture("loki_tool_results.json"),
        ),
        (
            "event_name=\"cc_obs_ledger.tool_call\"",
            fixture("loki_ledger_calls.json"),
        ),
    ]));
    let out = cli(&fake, &["tool", "Read"]).json();
    assert_eq!(row(&out, "calls")["value"], json!(2));
    assert_eq!(row(&out, "mean_result_bytes")["value"], json!(50000));
    assert_eq!(row(&out, "max_result_bytes")["value"], json!(60000));
    assert_eq!(row(&out, "share_of_tokens")["value"], json!(0.8333));
    // 4 Read calls in the ledger, one of them an identical repeat
    assert_eq!(row(&out, "repeat_rate")["value"], json!(0.25));
}

#[test]
fn tool_unknown_name_is_unavailable() {
    let fake = serve(with_own(vec![(
        "event_name=\"tool_result\"",
        fixture("loki_tool_results.json"),
    )]));
    let out = cli(&fake, &["tool", "Nope"]).json();
    assert_eq!(out["value"], json!(null));
    assert!(out["unavailable"].as_str().unwrap().contains("Nope"));
}

#[test]
fn session_summary_and_detail() {
    let fake = serve(with_own(vec![
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
    ]));
    let out = cli(&fake, &["session", "s1"]).json();
    assert_eq!(out["turns"], json!(3));
    assert_eq!(out["max_context_tokens"], json!(52000));
    assert_eq!(out["mean_cache_hit_ratio"], json!(0.7333));
    assert_eq!(out["fixed_context_tokens"], json!(10000));
    assert_eq!(out["new_tokens"], json!(42000));
    assert_eq!(rows(&out).len(), 0);

    let detail = cli(&fake, &["session", "s1", "--detail"]).json();
    assert_eq!(rows(&detail).len(), 3);
    assert_eq!(rows(&detail)[2]["turn"], json!(3));
    assert_eq!(rows(&detail)[2]["context_tokens"], json!(52000));
    assert_eq!(rows(&detail)[2]["cache_hit_ratio"], json!(0.9));
}

#[test]
fn session_without_fixed_context_marks_it_unavailable() {
    let fake = serve(with_own(vec![
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
            fixture("prom_empty.json"),
        ),
    ]));
    let out = cli(&fake, &["session", "s1"]).json();
    assert_eq!(out["fixed_context_tokens"]["value"], json!(null));
    assert!(out["fixed_context_tokens"]["unavailable"].is_string());
    assert_eq!(out["new_tokens"]["value"], json!(null));
}

#[test]
fn repeats_finds_each_pattern_without_exposing_hashes() {
    let fake = serve(with_own(vec![(
        "event_name=\"cc_obs_ledger.tool_call\"",
        fixture("loki_ledger_calls.json"),
    )]));
    let run = cli(&fake, &["repeats"]);
    assert_eq!(run.code, 0, "{}", run.err);
    let out = run.json();
    let identical = row(&out, "identical:Read");
    assert_eq!(identical["value"], json!(1));
    assert_eq!(identical["evidence"], json!("tool:Read"));
    assert_eq!(row(&out, "near_identical:Grep")["value"], json!(1));
    assert_eq!(row(&out, "large_then_narrow:Read")["value"], json!(1));
    assert_eq!(row(&out, "sequence:Read>Read>Grep")["value"], json!(2));
    assert!(!run.out.contains("h_a") && !run.out.contains("p_g"));
}

#[test]
fn repeats_min_count_filters_groups() {
    let fake = serve(with_own(vec![(
        "event_name=\"cc_obs_ledger.tool_call\"",
        fixture("loki_ledger_calls.json"),
    )]));
    let out = cli(&fake, &["repeats", "--min-count", "3"]).json();
    assert!(rows(&out)
        .iter()
        .all(|r| r["key"] != "sequence:Read>Read>Grep"));
}

#[test]
fn repeats_with_no_ledger_records_is_unavailable() {
    let fake = serve(with_own(vec![(
        "event_name=\"cc_obs_ledger.tool_call\"",
        r#"{"status":"success","data":{"resultType":"streams","result":[]}}"#.to_owned(),
    )]));
    let out = cli(&fake, &["repeats"]).json();
    assert_eq!(out["value"], json!(null));
    assert!(out["unavailable"]
        .as_str()
        .unwrap()
        .contains("cc_obs_ledger.tool_call"));
}

fn recall_rules() -> Vec<(&'static str, String)> {
    with_own(vec![
        ("by (outcome)", fixture("prom_recall_requests.json")),
        (
            "sum(increase(recall_hits_total",
            fixture("prom_scalar_recall_hits.json"),
        ),
        (
            "sum(increase(recall_tokens_injected_total",
            fixture("prom_scalar_recall_tokens.json"),
        ),
    ])
}

#[test]
fn recall_reports_injection_hits_and_failures() {
    let fake = serve(recall_rules());
    let out = cli(&fake, &["recall"]).json();
    assert_eq!(row(&out, "requests")["value"], json!(100));
    assert_eq!(row(&out, "injected_tokens_per_prompt")["value"], json!(240));
    assert_eq!(row(&out, "matches_used")["value"], json!(60));
    assert_eq!(row(&out, "empty_requests")["value"], json!(15));
    assert_eq!(row(&out, "failures")["value"], json!(5));
}

#[test]
fn recall_without_requests_is_unavailable() {
    let fake = serve(with_own(vec![("by (outcome)", fixture("prom_empty.json"))]));
    let out = cli(&fake, &["recall"]).json();
    assert_eq!(out["value"], json!(null));
    assert!(out["unavailable"].is_string());
}

#[test]
fn health_reports_stores_and_guard() {
    let ready = "ready".to_owned();
    let fake = serve(vec![
        ("/prom/-/ready", ready.clone()),
        ("/loki/ready", ready.clone()),
        ("/tempo/ready", ready),
        (
            "observability_guard_over_budget",
            fixture("prom_guard_ok.json"),
        ),
    ]);
    let out = cli(&fake, &["health"]).json();
    assert_eq!(out["stores_ok"], json!(true));
    assert_eq!(out["guard"], json!("ok"));
    assert_eq!(row(&out, "tempo")["value"], json!("up"));
}

#[test]
fn health_reports_an_over_budget_guard_as_an_identifier() {
    let ready = "ready".to_owned();
    let fake = serve(vec![
        ("/prom/-/ready", ready.clone()),
        ("/loki/ready", ready.clone()),
        ("/tempo/ready", ready),
        (
            "observability_guard_over_budget",
            fixture("prom_guard_over.json"),
        ),
    ]);
    let out = cli(&fake, &["health"]).json();
    assert_eq!(out["guard"], json!("over_budget"));
}

#[test]
fn health_flags_an_unreachable_store() {
    let fake = serve(vec![
        ("/prom/-/ready", "ready".to_owned()),
        ("/loki/ready", "ready".to_owned()),
        (
            "observability_guard_over_budget",
            fixture("prom_guard_ok.json"),
        ),
    ]);
    let run = cli(&fake, &["health"]);
    assert_eq!(run.code, 0, "{}", run.err);
    let out = run.json();
    assert_eq!(out["stores_ok"], json!(false));
    assert_eq!(row(&out, "tempo")["value"], json!("down"));
}

#[test]
fn backend_failure_is_one_json_object_on_stderr() {
    let fake = serve(vec![]);
    let run = cli(&fake, &["top", "model"]);
    assert_ne!(run.code, 0);
    assert!(run.out.is_empty());
    let err = run.err_json();
    for key in ["error", "operation", "input", "fix"] {
        assert!(err[key].is_string(), "missing {key} in {err}");
    }
    assert_eq!(run.err.trim().lines().count(), 1);
}

#[test]
fn bad_arguments_use_the_same_error_object() {
    let fake = serve(vec![]);
    let run = cli(&fake, &["top", "bogus"]);
    assert_ne!(run.code, 0);
    let err = run.err_json();
    assert!(err["error"].as_str().unwrap().contains("bogus"));
    let since = cli(&fake, &["top", "model", "--since", "yesterday"]);
    assert_ne!(since.code, 0);
    assert!(since.err_json()["input"]
        .as_str()
        .unwrap()
        .contains("yesterday"));
}

#[test]
fn missing_endpoints_file_names_the_fix() {
    let dir = tempfile::tempdir().unwrap();
    let run = common::cli_with(&dir.path().join("absent.json"), &["health"]);
    assert_ne!(run.code, 0);
    assert!(run.err_json()["fix"]
        .as_str()
        .unwrap()
        .contains("CC_OBS_ENDPOINTS"));
}

#[test]
fn library_prometheus_range_loki_and_tempo_clients() {
    let fake = serve(vec![
        (
            "/prom/api/v1/query_range",
            fixture("prom_range_context.json"),
        ),
        ("/prom/api/v1/query?", fixture("prom_tokens_by_model.json")),
        (
            "/loki/loki/api/v1/query_range",
            fixture("loki_tool_results.json"),
        ),
        ("/tempo/api/search", fixture("tempo_search.json")),
        ("/tempo/api/traces/abc123", fixture("tempo_trace.json")),
    ]);
    let endpoints: Endpoints = serde_json::from_str(&common::endpoints_json(&fake.base)).unwrap();
    let backend = Backend::new(endpoints);

    let instant = backend.prom_instant("up", None).unwrap();
    assert_eq!(instant.len(), 3);
    assert_eq!(instant[0].labels["model"], "claude-opus-4");

    let series = backend
        .prom_range("up", 1_760_000_000, 1_760_000_060, 60)
        .unwrap();
    assert_eq!(
        series[0].points,
        vec![(1_760_000_000.0, 20000.0), (1_760_000_060.0, 35000.0)]
    );

    let logs = backend
        .loki_range(
            "{service_name=\"claude-code\"}",
            0,
            1_760_000_100_000_000_000,
            100,
        )
        .unwrap();
    assert_eq!(logs.len(), 4);
    assert_eq!(logs[0].fields["tool_name"], "Read");

    let traces = backend.tempo_search("{}", 0, 1_760_000_100, 5).unwrap();
    assert_eq!(traces[0].trace_id, "abc123");
    assert_eq!(traces[0].duration_ms, Some(4200));
    let trace = backend.tempo_trace("abc123").unwrap();
    assert!(trace["batches"].is_array());
}
