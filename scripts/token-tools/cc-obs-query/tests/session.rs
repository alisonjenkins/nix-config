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
