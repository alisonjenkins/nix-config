#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]

//! `top session --by context-growth` for sub-agents that share a session id.

mod common;

use common::{cli, row, serve, with_own};
use serde_json::{json, Value};

fn vector(series: &[(Value, &str)]) -> String {
    let result: Vec<Value> = series
        .iter()
        .map(|(labels, value)| json!({"metric": labels, "value": [1760000000.0, value]}))
        .collect();
    json!({"status": "success", "data": {"resultType": "vector", "result": result}}).to_string()
}

fn gauge(agent: &str, agent_id: Option<&str>, turn: &str) -> Value {
    let mut labels = json!({
        "session_id": "s1", "agent": agent, "model": "m", "turn": turn, "project": "p",
    });
    if let Some(id) = agent_id {
        labels["agent_id"] = json!(id);
    }
    labels
}

fn growth(series: &[(Value, &str)]) -> Value {
    let fake = serve(with_own(vec![(
        "cc_obs_ledger_context_tokens",
        vector(series),
    )]));
    let run = cli(
        &fake,
        &[
            "top",
            "session",
            "--by",
            "context-growth",
            "--format",
            "detailed",
        ],
    );
    assert_eq!(run.code, 0, "{}", run.err);
    run.json()
}

#[test]
fn context_growth_ranks_each_subagent_on_its_own() {
    let at = |id: &str, turn: &str| gauge("subagent", Some(id), turn);
    let out = growth(&[
        (at("agent-a", "1"), "10000"),
        (at("agent-a", "2"), "110000"),
        (at("agent-b", "1"), "20000"),
        (at("agent-b", "2"), "25000"),
        (gauge("main", None, "1"), "30000"),
    ]);
    assert_eq!(
        row(&out, "s1/subagent/agent-a")["value"],
        json!(100000),
        "{out}"
    );
    assert_eq!(
        row(&out, "s1/subagent/agent-b")["value"],
        json!(5000),
        "{out}"
    );
    assert_eq!(row(&out, "s1")["value"], json!(0), "{out}");
}

#[test]
fn context_growth_keeps_the_old_key_for_a_subagent_without_an_id() {
    let out = growth(&[
        (gauge("subagent", None, "1"), "10000"),
        (gauge("subagent", None, "2"), "40000"),
    ]);
    assert_eq!(row(&out, "s1/subagent")["value"], json!(30000), "{out}");
}
