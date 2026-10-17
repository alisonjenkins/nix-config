#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]

mod common;

use common::{cli, row, rows, serve, with_own};
use serde_json::{json, Value};

const REQUESTS: &str = "cc_obs_ledger_requests_total";
const CACHE_READ: &str = "type=\"cacheRead\"";
const PROMPT: &str = "type=~\"cacheRead|cacheCreation|input\"";

fn by_session(pairs: &[(&str, &str)]) -> String {
    let result: Vec<Value> = pairs
        .iter()
        .map(|(id, v)| json!({"metric": {"session_id": id}, "value": [1.0, v]}))
        .collect();
    json!({"status": "success", "data": {"resultType": "vector", "result": result}}).to_string()
}

fn cache_rules() -> Vec<(&'static str, String)> {
    with_own(vec![
        (
            REQUESTS,
            by_session(&[("big", "10"), ("mid", "6"), ("cold", "1")]),
        ),
        (
            CACHE_READ,
            by_session(&[("big", "900"), ("mid", "300"), ("cold", "0")]),
        ),
        (
            PROMPT,
            by_session(&[("big", "1000"), ("mid", "1000"), ("cold", "1000")]),
        ),
    ])
}

fn ranked_keys(out: &Value) -> Vec<String> {
    rows(out)
        .iter()
        .map(|r| r["key"].as_str().unwrap().to_owned())
        .collect()
}

#[test]
fn cache_hit_drops_sessions_under_the_default_five_requests() {
    let fake = serve(cache_rules());
    let run = cli(&fake, &["top", "session", "--by", "cache-hit"]);
    assert_eq!(run.code, 0, "{}", run.err);
    assert_eq!(ranked_keys(&run.json()), vec!["mid", "big"]);
}

#[test]
fn cache_hit_min_requests_is_adjustable() {
    let fake = serve(cache_rules());
    let run = cli(
        &fake,
        &["top", "session", "--by", "cache-hit", "--min-requests", "1"],
    );
    assert_eq!(run.code, 0, "{}", run.err);
    assert_eq!(ranked_keys(&run.json()), vec!["cold", "mid", "big"]);
}

#[test]
fn cache_hit_is_cache_read_over_all_prompt_tokens() {
    let fake = serve(cache_rules());
    let out = cli(
        &fake,
        &[
            "top",
            "session",
            "--by",
            "cache-hit",
            "--format",
            "detailed",
        ],
    )
    .json();
    assert_eq!(row(&out, "mid")["value"], json!(0.3));
    assert_eq!(row(&out, "big")["value"], json!(0.9));
    assert_eq!(row(&out, "big")["requests"], json!(10));
    let read = fake.seen_matching(CACHE_READ);
    assert!(
        read[0].contains("increase(") && read[0].contains("claude_code_token_usage_tokens_total"),
        "{read:?}"
    );
}

#[test]
fn cache_hit_help_names_its_definition() {
    let fake = serve(vec![]);
    let run = cli(&fake, &["top", "--help"]);
    assert!(run.out.contains("--min-requests"), "{}", run.out);
    assert!(run.out.contains("cacheRead"), "{}", run.out);
}
