#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]

mod common;

use std::fs;
use std::path::PathBuf;

use cc_obs_query::pack::{regrown, Pack, COLLECTED_SIGNALS};
use common::TOOL_PACK;
use common::{cli, cli_with, digest_rules, endpoints_file, fixture, rows, s, serve, write_pack};
use serde_json::{json, Value};

fn shipped_pack() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../docs/token-efficiency/questions.yaml")
}

fn question(signals: &str) -> String {
    format!(
        "version: 1\nquestions:\n  - id: only\n    title: Only\n    signals: [{signals}]\n    query: {{ command: \"cc-obs-query top model\" }}\n    decision_kind: configure\n"
    )
}

#[test]
fn shipped_pack_has_the_ten_starting_questions_and_no_unused_signal() {
    let pack = Pack::load(&shipped_pack()).unwrap();
    let ids: Vec<_> = pack.questions.iter().map(|q| q.id.as_str()).collect();
    assert_eq!(
        ids,
        vec![
            "tool-result-size",
            "repeat-calls",
            "skills-loaded-unused",
            "mcp-idle-servers",
            "fixed-context-share",
            "cache-hit-low-sessions",
            "subagent-overhead",
            "memory-injected-ignored",
            "compaction-frequency",
            "recall-failures",
        ]
    );
    let repeats = pack
        .questions
        .iter()
        .find(|q| q.id == "repeat-calls")
        .unwrap();
    assert!(repeats
        .signals
        .iter()
        .any(|s| s == "cc_obs_ledger.tool_call"));
    assert!(pack.unused().is_empty(), "{:?}", pack.unused());
    let (_dir, endpoints) = endpoints_file("http://127.0.0.1:1");
    let run = cli_with(
        &endpoints,
        &["unused-signals", "--pack", s(&shipped_pack())],
    );
    assert_eq!(run.code, 0, "{}", run.err);
}

#[test]
fn unknown_signal_is_rejected() {
    let dir = tempfile::tempdir().unwrap();
    let pack = write_pack(dir.path(), &question("made.up.signal"));
    let fake = serve(vec![]);
    let run = cli(&fake, &["unused-signals", "--pack", s(&pack)]);
    assert_ne!(run.code, 0);
    let err = run.err_json();
    assert!(err["error"].as_str().unwrap().contains("unknown signal"));
    assert!(err["error"].as_str().unwrap().contains("made.up.signal"));
}

#[test]
fn unused_signals_lists_what_no_question_references_and_fails() {
    let dir = tempfile::tempdir().unwrap();
    let pack = write_pack(dir.path(), &question("claude_code.token.usage"));
    let fake = serve(vec![]);
    let run = cli(
        &fake,
        &["unused-signals", "--pack", s(&pack), "--limit", "100"],
    );
    assert_eq!(run.code, 1, "{}", run.err);
    let out = run.json();
    let keys: Vec<_> = rows(&out)
        .iter()
        .map(|r| r["key"].as_str().unwrap())
        .collect();
    assert!(keys.contains(&"claude_code.api_error"));
    assert!(!keys.contains(&"claude_code.token.usage"));
}

#[test]
fn retire_removes_a_signal_from_the_unused_list() {
    let dir = tempfile::tempdir().unwrap();
    let retired: Vec<&str> = COLLECTED_SIGNALS
        .iter()
        .copied()
        .filter(|s| *s != "claude_code.token.usage")
        .collect();
    let yaml = format!(
        "{}retire: [{}]\n",
        question("claude_code.token.usage"),
        retired.join(", ")
    );
    let pack = write_pack(dir.path(), &yaml);
    let fake = serve(vec![]);
    let run = cli(&fake, &["unused-signals", "--pack", s(&pack)]);
    assert_eq!(run.code, 0, "{}", run.err);
    assert_eq!(rows(&run.json()).len(), 0);
}

#[test]
fn regrowth_rule() {
    assert!(!regrown(25_000.0, 20_000.0, 1.5));
    assert!(!regrown(30_000.0, 20_000.0, 1.5));
    assert!(regrown(31_000.0, 20_000.0, 1.5));
}

fn decision(id: &str, kind: &str, baseline: u64, acted: &str) -> String {
    format!(
        "---\nid: \"{id}\"\nhost: test-host\ndate: 2026-09-01T00:00:00Z\nfinding: 2026-09-01-test-host#1\ndecision: {kind}\nreason: because\nmetric: {{ question: tool-result-size, key: Read, baseline: {baseline}, unit: tokens/week }}\nacted_on: {acted}\noutcome: null\noutcome_review: null\n---\n"
    )
}

fn digest_with_decision(file: &str, body: &str) -> Value {
    let dir = tempfile::tempdir().unwrap();
    let pack = write_pack(dir.path(), TOOL_PACK);
    fs::create_dir(dir.path().join("decisions")).unwrap();
    fs::write(dir.path().join("decisions").join(file), body).unwrap();
    let fake = serve(digest_rules(fixture("loki_tool_results.json")));
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
    run.json()
}

fn keys(digest: &Value) -> Vec<String> {
    digest["questions"][0]["rows"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| r["key"].as_str().unwrap().to_owned())
        .collect()
}

#[test]
fn dismissed_finding_below_regrowth_is_suppressed() {
    // Read is 25000 tokens in the window; 25000 <= 1.5 * 20000
    let d = digest_with_decision("0003-read.md", &decision("0003", "dismiss", 20_000, "null"));
    assert!(!keys(&d).contains(&"Read".to_owned()));
    assert_eq!(d["questions"][0]["suppressed"], json!(1));
}

#[test]
fn dismissed_finding_resurfaces_above_regrowth() {
    let d = digest_with_decision("0003-read.md", &decision("0003", "dismiss", 10_000, "null"));
    assert!(keys(&d).contains(&"Read".to_owned()));
    let read = &d["questions"][0]["rows"][0];
    assert_eq!(read["regrowth_of"], json!("0003"));
}

#[test]
fn acted_decision_reports_before_after_and_verdict() {
    let d = digest_with_decision(
        "0007-read.md",
        &decision("0007", "build", 50_000, "abc1234"),
    );
    assert_eq!(
        d["prior_decisions"],
        json!([{"id": "0007", "status": "acted", "before": 50000, "after": 25000, "verdict": "effective"}])
    );
    assert!(keys(&d).contains(&"Read".to_owned()));
}

#[test]
fn compare_reports_the_same_figure_over_two_ranges() {
    let dir = tempfile::tempdir().unwrap();
    let yaml = TOOL_PACK.replace("top tool --by tokens", "top model --by tokens");
    let pack = write_pack(dir.path(), &yaml);
    let a = r#"{"status":"success","data":{"resultType":"vector","result":[{"metric":{"model":"claude-opus-4"},"value":[1.0,"100"]}]}}"#;
    let b = r#"{"status":"success","data":{"resultType":"vector","result":[{"metric":{"model":"claude-opus-4"},"value":[1.0,"150"]},{"metric":{"model":"claude-haiku-5"},"value":[1.0,"10"]}]}}"#;
    let fake = serve(vec![
        ("time=1788825600", a.to_owned()),
        ("time=1789430400", b.to_owned()),
    ]);
    let run = cli(
        &fake,
        &[
            "compare",
            "tool-result-size",
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
    let opus = common::row(&out, "claude-opus-4");
    assert_eq!(opus["a"], json!(100));
    assert_eq!(opus["b"], json!(150));
    assert_eq!(opus["delta"], json!(50));
    assert_eq!(opus["ratio"], json!(1.5));
    let haiku = common::row(&out, "claude-haiku-5");
    assert_eq!(haiku["a"]["value"], json!(null));
    assert_eq!(haiku["b"], json!(10));
    assert_eq!(haiku["ratio"]["value"], json!(null));
}

#[test]
fn compare_unknown_question_names_the_known_ones() {
    let dir = tempfile::tempdir().unwrap();
    let pack = write_pack(dir.path(), TOOL_PACK);
    let fake = serve(vec![]);
    let run = cli(
        &fake,
        &[
            "compare",
            "nope",
            "--a",
            "2026-09-01..2026-09-08",
            "--b",
            "2026-09-08..2026-09-15",
            "--pack",
            s(&pack),
        ],
    );
    assert_ne!(run.code, 0);
    assert!(run.err_json()["fix"]
        .as_str()
        .unwrap()
        .contains("tool-result-size"));
}
