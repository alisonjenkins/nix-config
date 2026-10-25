#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]

mod common;

use std::fs;

use common::{cli, digest_rules, fixture, rows, s, serve, with_own, write_pack};
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

const SPLIT: &str = "by (agent_name, model)";

fn subagent_body() -> String {
    vector(&[
        (
            &[
                ("agent_name", "general-purpose"),
                ("model", "claude-sonnet-5-5"),
            ],
            "5",
        ),
        (
            &[
                ("agent_name", "general-purpose"),
                ("model", "claude-haiku-5-5"),
            ],
            "3",
        ),
        (
            &[("agent_name", "Explore"), ("model", "claude-haiku-5-5")],
            "2",
        ),
    ])
}

fn model_of_rows(out: &Value) -> Vec<(String, String, String)> {
    rows(out)
        .iter()
        .map(|r| {
            (
                r["key"].as_str().unwrap().to_owned(),
                r["model"].as_str().unwrap_or("").to_owned(),
                r["evidence"].as_str().unwrap().to_owned(),
            )
        })
        .collect()
}

#[test]
fn top_subagent_by_cost_groups_by_agent_and_model() {
    let fake = serve(with_own(vec![(SPLIT, subagent_body())]));
    let run = cli(
        &fake,
        &[
            "top", "subagent", "--by", "cost", "--since", "7d", "--format", "detailed",
        ],
    );
    assert_eq!(run.code, 0, "{}", run.err);
    let out = run.json();
    assert_eq!(
        model_of_rows(&out),
        vec![
            (
                "general-purpose@claude-sonnet-5-5".to_owned(),
                "claude-sonnet-5-5".to_owned(),
                "subagent:general-purpose@claude-sonnet-5-5".to_owned()
            ),
            (
                "general-purpose@claude-haiku-5-5".to_owned(),
                "claude-haiku-5-5".to_owned(),
                "subagent:general-purpose@claude-haiku-5-5".to_owned()
            ),
            (
                "Explore@claude-haiku-5-5".to_owned(),
                "claude-haiku-5-5".to_owned(),
                "subagent:Explore@claude-haiku-5-5".to_owned()
            ),
        ]
    );
    let queries = fake.seen_matching(SPLIT);
    assert!(
        queries[0].contains("claude_code_cost_usage_USD_total")
            && queries[0].contains("query_source=\"subagent\"")
            && queries[0].contains("increase("),
        "{queries:?}"
    );
}

#[test]
fn top_subagent_by_tokens_splits_by_model_too() {
    let fake = serve(with_own(vec![(SPLIT, subagent_body())]));
    let out = cli(&fake, &["top", "subagent", "--by", "tokens"]).json();
    assert_eq!(rows(&out).len(), 3);
    assert_eq!(
        rows(&out)[1]["evidence"],
        json!("subagent:general-purpose@claude-haiku-5-5")
    );
    let queries = fake.seen_matching(SPLIT);
    assert!(
        queries[0].contains("claude_code_token_usage_tokens_total"),
        "{queries:?}"
    );
}

#[test]
fn top_model_is_not_split_further() {
    let fake = serve(with_own(vec![(
        "by (model)",
        fixture("prom_tokens_by_model.json"),
    )]));
    let out = cli(&fake, &["top", "model"]).json();
    assert_eq!(rows(&out)[0]["evidence"], json!("model:claude-opus-4"));
}

const SUBAGENT_PACK: &str = "version: 1\nquestions:\n  - id: subagent-overhead\n    title: Sub-agents\n    signals: [claude_code.token.usage]\n    query: { command: \"cc-obs-query top subagent --by cost\" }\n    decision_kind: configure\n";

#[test]
fn a_digest_with_split_subagent_rows_stays_schema_valid() {
    let dir = tempfile::tempdir().unwrap();
    let pack = write_pack(dir.path(), SUBAGENT_PACK);
    let mut rules = vec![(SPLIT, subagent_body())];
    rules.extend(digest_rules(fixture("loki_tool_results.json")));
    let fake = serve(rules);
    fn common_args<'a>(pack: &'a str, extra: &[&'a str]) -> Vec<&'a str> {
        let mut args = vec!["digest", "--pack", pack, "--until", "2026-10-09"];
        args.extend_from_slice(extra);
        args
    }
    let run = cli(
        &fake,
        &common_args(s(&pack), &["--baseline", "--since", "7d"]),
    );
    assert_eq!(run.code, 0, "{}", run.err);
    let mut digest = run.json();
    assert_eq!(digest["schema"], json!(1));
    assert_eq!(
        digest["questions"][0]["rows"][0]["evidence"],
        json!("subagent:general-purpose@claude-sonnet-5-5")
    );
    digest["stage1"] = json!("model");
    let file = dir.path().join("in.json");
    fs::write(&file, digest.to_string()).unwrap();
    let write = cli(&fake, &common_args(s(&pack), &["--write", s(&file)]));
    assert_eq!(write.code, 0, "{}", write.err);
    assert_eq!(write.json()["valid"], json!(true));
}

#[test]
fn a_sub_agent_decision_metric_resolves_by_agent_and_model() {
    let dir = tempfile::tempdir().unwrap();
    let pack = write_pack(dir.path(), SUBAGENT_PACK);
    fs::create_dir(dir.path().join("decisions")).unwrap();
    fs::write(
        dir.path().join("decisions/0001-subagent.md"),
        "---\nid: \"0001\"\nhost: test-host\ndate: 2026-09-01T00:00:00Z\nfinding: 2026-09-01-test-host#1\ndecision: configure\nreason: because\nmetric: { question: subagent-overhead, key: general-purpose@claude-sonnet-5-5, baseline: 49.83, unit: usd/week }\nacted_on: abc1234\noutcome: null\noutcome_review: null\n---\n",
    )
    .unwrap();
    let mut rules = vec![(SPLIT, subagent_body())];
    rules.extend(digest_rules(fixture("loki_tool_results.json")));
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
    let after = &run.json()["prior_decisions"][0]["after"];
    assert!(after.is_number(), "{after}");
}

#[test]
fn compare_finds_a_sub_agent_row_by_agent_and_model() {
    let dir = tempfile::tempdir().unwrap();
    let pack = write_pack(dir.path(), SUBAGENT_PACK);
    let fake = serve(vec![(SPLIT, subagent_body())]);
    let run = cli(
        &fake,
        &[
            "compare",
            "subagent-overhead",
            "--a",
            "2026-09-01..2026-09-08",
            "--b",
            "2026-09-08..2026-09-15",
            "--pack",
            s(&pack),
        ],
    );
    assert_eq!(run.code, 0, "{}", run.err);
    let out = run.json();
    assert_eq!(
        common::row(&out, "general-purpose@claude-sonnet-5-5")["b"],
        json!(5)
    );
}
