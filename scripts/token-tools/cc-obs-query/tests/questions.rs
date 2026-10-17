#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]

//! The shipped question pack must ask what its query answers.

mod common;

use std::path::PathBuf;

use cc_obs_query::pack::Pack;
use common::{cli, digest_rules, fixture, s, serve, write_pack};
use serde_json::{json, Value};

fn shipped_pack() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../docs/token-efficiency/questions.yaml")
}

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

fn command_of(pack: &Pack, id: &str) -> String {
    pack.question(id).unwrap().query.command.clone()
}

fn title_of(pack: &Pack, id: &str) -> String {
    pack.question(id).unwrap().title.to_lowercase()
}

/// Plain `top skill` lists activated skills only; a title about unactivated skills needs
/// `--unactivated`.
#[test]
fn skills_question_asks_for_unactivated_skills_with_the_flag_that_finds_them() {
    let pack = Pack::load(&shipped_pack()).unwrap();
    let title = title_of(&pack, "skills-loaded-unused");
    let command = command_of(&pack, "skills-loaded-unused");
    assert!(command.contains("top skill --unactivated"), "{command}");
    assert!(title.contains("without being activated"), "{title}");
}

/// `top mcp` ranks series that carry an mcp server label; it cannot see idle servers.
#[test]
fn mcp_question_does_not_claim_idle_servers() {
    let pack = Pack::load(&shipped_pack()).unwrap();
    let title = title_of(&pack, "mcp-idle-servers");
    assert!(!title.contains("idle"), "{title}");
}

/// A title about each request needs the per-request share, not the session-start snapshot.
#[test]
fn fixed_context_question_asks_the_per_request_share() {
    let pack = Pack::load(&shipped_pack()).unwrap();
    let title = title_of(&pack, "fixed-context-share");
    let command = command_of(&pack, "fixed-context-share");
    assert!(command.contains("top fixed --by share"), "{command}");
    assert!(title.contains("each request"), "{title}");
}

/// The ledger counts a request with a match once, so the ratio is requests with a
/// match, not matches used.
#[test]
fn memory_question_is_about_requests_with_a_match() {
    let pack = Pack::load(&shipped_pack()).unwrap();
    let title = title_of(&pack, "memory-injected-ignored");
    assert!(
        !title.contains("matches used"),
        "hits are requests with a match, not matches used: {title}"
    );
    let threshold = &pack.question("memory-injected-ignored").unwrap().threshold;
    assert_eq!(threshold.max_value, Some(0.5));
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

#[test]
fn shipped_pack_filters_well_matched_memory_services() {
    let requests = vector(&[
        (&[("service", "skills")], "100"),
        (&[("service", "docs")], "100"),
    ]);
    let hits = vector(&[
        (&[("service", "skills")], "20"),
        (&[("service", "docs")], "90"),
    ]);
    let pack = std::fs::read_to_string(shipped_pack()).unwrap();
    let questions = digest_questions(&pack, recall_rules(requests, hits));
    let memory = questions
        .iter()
        .find(|q| q["id"] == "memory-injected-ignored")
        .unwrap();
    assert_eq!(keys_of(memory), vec!["skills"]);
}

#[test]
fn delegation_tier_fit_names_each_agent_on_each_model() {
    let body = vector(&[
        (
            &[("agent_name", "Explore"), ("model", "claude-opus-4")],
            "8",
        ),
        (
            &[("agent_name", "Explore"), ("model", "claude-haiku-5-5")],
            "2",
        ),
    ]);
    let mut rules = vec![("by (agent_name, model)", body)];
    rules.extend(digest_rules(fixture("loki_tool_results.json")));
    let pack = std::fs::read_to_string(shipped_pack()).unwrap();
    let questions = digest_questions(&pack, rules);
    let tier = questions
        .iter()
        .find(|q| q["id"] == "delegation-tier-fit")
        .unwrap();
    let evidence: Vec<&str> = tier["rows"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| r["evidence"].as_str().unwrap())
        .collect();
    assert_eq!(
        evidence,
        vec![
            "subagent:Explore@claude-opus-4",
            "subagent:Explore@claude-haiku-5-5"
        ]
    );
}

#[test]
fn every_shipped_question_titles_what_its_command_ranks() {
    let pack = Pack::load(&shipped_pack()).unwrap();
    for id in [
        "costly-sessions",
        "model-spend",
        "delegation-tier-fit",
        "memory-injection-cost",
    ] {
        let question = pack.question(id).unwrap();
        assert!(!question.decision_kind.is_empty(), "{id}");
        assert!(
            question.threshold.min_share.is_some() || question.threshold.max_value.is_some(),
            "{id} has no threshold"
        );
    }
}
