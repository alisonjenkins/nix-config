#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]

mod common;

use std::fs;

use cc_obs_query::bounds::{DEFAULT_LIMIT, DEFAULT_MAX_BYTES, DIGEST_MAX_BYTES};
use common::{cli, digest_rules, fixture, rows, s, serve, write_pack, TOOL_PACK};
use serde_json::{json, Value};

const UNTIL: &str = "2026-10-09";

fn many_tools(count: usize) -> String {
    let result: Vec<Value> = (0..count)
        .map(|i| {
            json!({
                "stream": {
                    "service_name": "claude-code",
                    "event_name": "tool_result",
                    "tool_name": format!("mcp__some_long_server_name__tool_number_{i:04}"),
                    "tool_result_size_bytes": format!("{}", 4000 + i),
                },
                "values": [[format!("{}", 1_760_000_000_000_000_000_u64 + i as u64), "tool_result"]]
            })
        })
        .collect();
    json!({"status":"success","data":{"resultType":"streams","result":result}}).to_string()
}

#[test]
fn documented_defaults() {
    assert_eq!(DEFAULT_LIMIT, 10);
    assert_eq!(DEFAULT_MAX_BYTES, 8192);
    assert_eq!(DIGEST_MAX_BYTES, 32768);
}

#[test]
fn default_limit_is_ten_with_continuation_flag() {
    let fake = serve(vec![("event_name=\"tool_result\"", many_tools(25))]);
    let out = cli(&fake, &["top", "tool"]).json();
    assert_eq!(rows(&out).len(), 10);
    assert_eq!(out["truncated"], json!(true));
    assert_eq!(out["next"], json!("--offset 10"));
}

#[test]
fn max_bytes_truncates_and_names_the_next_flag() {
    let fake = serve(vec![("event_name=\"tool_result\"", many_tools(200))]);
    let run = cli(
        &fake,
        &["top", "tool", "--limit", "200", "--max-bytes", "900"],
    );
    assert!(run.out.len() <= 900, "{} bytes", run.out.len());
    let out = run.json();
    assert_eq!(out["truncated"], json!(true));
    let kept = rows(&out).len();
    assert!(kept > 0 && kept < 200);
    assert_eq!(out["next"], json!(format!("--offset {kept}")));
}

#[test]
fn table_format_is_plain_text() {
    let fake = serve(vec![(
        "event_name=\"tool_result\"",
        fixture("loki_tool_results.json"),
    )]);
    let run = cli(&fake, &["top", "tool", "--format", "table"]);
    assert_eq!(run.code, 0, "{}", run.err);
    assert!(serde_json::from_str::<Value>(&run.out).is_err());
    assert!(run.out.lines().any(|l| l.contains("Read")));
}

#[test]
fn output_never_echoes_log_line_content() {
    let fake = serve(vec![(
        "event_name=\"tool_result\"",
        fixture("loki_tool_results.json"),
    )]);
    let run = cli(&fake, &["top", "tool", "--format", "detailed"]);
    assert!(!run.out.contains("SECRET-PROMPT-TEXT"));
}

fn baseline(fake: &common::Fake, pack: &str) -> common::Run {
    cli(
        fake,
        &[
            "digest",
            "--baseline",
            "--pack",
            pack,
            "--since",
            "7d",
            "--until",
            UNTIL,
        ],
    )
}

#[test]
fn baseline_digest_has_the_contract_shape() {
    let dir = tempfile::tempdir().unwrap();
    let pack = write_pack(dir.path(), TOOL_PACK);
    let fake = serve(digest_rules(fixture("loki_tool_results.json")));
    let run = baseline(&fake, s(&pack));
    assert_eq!(run.code, 0, "{}", run.err);
    assert!(!run.out.contains("SECRET-PROMPT-TEXT"));
    let d = run.json();
    assert_eq!(d["schema"], json!(1));
    assert_eq!(d["stage1"], json!("baseline"));
    assert_eq!(d["host"], json!("test-host"));
    assert_eq!(d["period"]["end"], json!("2026-10-09T00:00:00Z"));
    assert_eq!(d["period"]["start"], json!("2026-10-02T00:00:00Z"));
    assert_eq!(d["pack"]["version"], json!(1));
    assert_eq!(d["pack"]["sha"].as_str().unwrap().len(), 40);
    assert_eq!(d["stack"]["stores_ok"], json!(true));
    assert_eq!(d["stack"]["guard"], json!("ok"));
    assert_eq!(d["totals"]["tokens"], json!(130000));
    assert_eq!(d["totals"]["est_cost_usd"], json!(4.2));
    assert_eq!(d["totals"]["sessions"], json!(12));
    assert_eq!(d["own_cost"]["tokens"], json!(5000));
    assert_eq!(d["own_cost"]["est_cost_usd"], json!(0.31));
    assert_eq!(d["prior_decisions"], json!([]));
    let q = &d["questions"][0];
    assert_eq!(q["id"], json!("tool-result-size"));
    assert_eq!(q["rows"][0]["key"], json!("Read"));
    assert_eq!(q["rows"][0]["evidence"], json!("tool:Read"));
    assert_eq!(q["truncated"], json!(false));
}

#[test]
fn baseline_digest_stays_under_32_kib() {
    let dir = tempfile::tempdir().unwrap();
    let question = |n: u32| {
        format!(
            "  - id: q{n}\n    title: Question {n}\n    signals: [claude_code.token.usage]\n    query: {{ command: \"cc-obs-query top tool --by tokens --limit 100\" }}\n    decision_kind: configure\n"
        )
    };
    let yaml = format!(
        "version: 1\nquestions:\n{}",
        (0..5).map(question).collect::<String>()
    );
    let pack = write_pack(dir.path(), &yaml);
    let fake = serve(digest_rules(many_tools(400)));
    let run = baseline(&fake, s(&pack));
    assert_eq!(run.code, 0, "{}", run.err);
    assert!(run.out.len() <= DIGEST_MAX_BYTES, "{} bytes", run.out.len());
    let d = run.json();
    assert!(d["questions"]
        .as_array()
        .unwrap()
        .iter()
        .any(|q| q["truncated"] == json!(true)));
}

fn valid_digest(fake: &common::Fake, pack: &str) -> Value {
    let run = baseline(fake, pack);
    assert_eq!(run.code, 0, "{}", run.err);
    run.json()
}

fn write_args<'a>(file: &'a str, pack: &'a str) -> Vec<&'a str> {
    vec!["digest", "--write", file, "--pack", pack, "--until", UNTIL]
}

#[test]
fn digest_write_accepts_a_valid_digest_and_saves_it() {
    let dir = tempfile::tempdir().unwrap();
    let pack = write_pack(dir.path(), TOOL_PACK);
    let fake = serve(digest_rules(fixture("loki_tool_results.json")));
    let mut digest = valid_digest(&fake, s(&pack));
    digest["stage1"] = json!("model");
    digest["questions"][0]["rows"][0]["evidence"] = json!("session:s1");
    let file = dir.path().join("in.json");
    fs::write(&file, digest.to_string()).unwrap();
    let out = dir.path().join("out.json");
    let mut args = write_args(s(&file), s(&pack));
    args.extend(["--out", s(&out)]);
    let run = cli(&fake, &args);
    assert_eq!(run.code, 0, "{}", run.err);
    assert_eq!(run.json()["valid"], json!(true));
    let saved: Value = serde_json::from_str(&fs::read_to_string(out).unwrap()).unwrap();
    assert_eq!(saved["stage1"], json!("model"));
}

fn rejects(mutate: impl FnOnce(&mut Value), needle: &str) {
    let dir = tempfile::tempdir().unwrap();
    let pack = write_pack(dir.path(), TOOL_PACK);
    let fake = serve(digest_rules(fixture("loki_tool_results.json")));
    let mut digest = valid_digest(&fake, s(&pack));
    mutate(&mut digest);
    let file = dir.path().join("in.json");
    fs::write(&file, digest.to_string()).unwrap();
    let run = cli(&fake, &write_args(s(&file), s(&pack)));
    assert_ne!(run.code, 0, "accepted: {}", run.out);
    let err = run.err_json();
    assert!(
        err["error"].as_str().unwrap().contains(needle),
        "{needle} not in {err}"
    );
}

#[test]
fn digest_write_rejects_an_oversize_digest() {
    rejects(
        |d| {
            let extra: Vec<Value> = (0..600)
                .map(
                    |i| json!({"key": format!("padding-row-key-{i:05}"), "value": i, "share": 0.0}),
                )
                .collect();
            d["questions"][0]["rows"] = Value::Array(extra);
        },
        "32768",
    );
}

#[test]
fn digest_write_rejects_content_like_fields() {
    rejects(
        |d| d["questions"][0]["prompt"] = json!("please refactor my secret thing"),
        "prompt",
    );
    rejects(
        |d| d["questions"][0]["rows"][0]["note"] = json!("x".repeat(400)),
        "note",
    );
}

#[test]
fn digest_write_rejects_prose_in_a_row_key() {
    let sentence = "please summarise the confidential migration plan for the payments team and email it to the whole company before friday";
    assert!(sentence.chars().count() > 100);
    rejects(
        |d| d["questions"][0]["rows"][0]["key"] = json!(sentence),
        "key",
    );
    rejects(
        |d| d["questions"][0]["rows"][0]["key"] = json!("fix my bug"),
        "key",
    );
}

#[test]
fn digest_write_rejects_unknown_fields_in_any_case() {
    rejects(|d| d["questions"][0]["Prompt"] = json!("hi"), "Prompt");
    rejects(|d| d["extra"] = json!(1), "extra");
    rejects(|d| d["stack"]["notes"] = json!("hi"), "notes");
}

#[test]
fn digest_write_caps_free_text_fields() {
    rejects(
        |d| d["questions"][0]["title"] = json!("t".repeat(130)),
        "title",
    );
    rejects(
        |d| d["stack"]["gaps"] = json!(["this is a gap\nwith a second line"]),
        "gaps",
    );
    rejects(|d| d["stack"]["gaps"] = json!(["g".repeat(201)]), "gaps");
}

#[test]
fn digest_write_accepts_the_identifier_shapes_the_commands_emit() {
    let dir = tempfile::tempdir().unwrap();
    let pack = write_pack(dir.path(), TOOL_PACK);
    let fake = serve(digest_rules(fixture("loki_tool_results.json")));
    let mut digest = valid_digest(&fake, s(&pack));
    digest["questions"][0]["rows"][0]["key"] = json!("sequence:Read>Grep>mcp__srv__tool@1.2+x/y");
    let file = dir.path().join("in.json");
    fs::write(&file, digest.to_string()).unwrap();
    let run = cli(&fake, &write_args(s(&file), s(&pack)));
    assert_eq!(run.code, 0, "{}", run.err);
}

#[test]
fn digest_write_rejects_unknown_evidence() {
    rejects(
        |d| d["questions"][0]["rows"][0]["evidence"] = json!("session:ghost"),
        "session:ghost",
    );
}

#[test]
fn digest_write_rejects_a_wrong_schema() {
    rejects(|d| d["schema"] = json!(2), "schema");
}

fn accepts(mutate: impl FnOnce(&mut Value)) {
    let dir = tempfile::tempdir().unwrap();
    let pack = write_pack(dir.path(), TOOL_PACK);
    let fake = serve(digest_rules(fixture("loki_tool_results.json")));
    let mut digest = valid_digest(&fake, s(&pack));
    mutate(&mut digest);
    let file = dir.path().join("in.json");
    fs::write(&file, digest.to_string()).unwrap();
    let run = cli(&fake, &write_args(s(&file), s(&pack)));
    assert_eq!(run.code, 0, "{}", run.err);
}

#[test]
fn an_over_budget_guard_still_yields_a_digest_that_validates() {
    let dir = tempfile::tempdir().unwrap();
    let pack = write_pack(dir.path(), TOOL_PACK);
    let mut rules = digest_rules(fixture("loki_tool_results.json"));
    rules.insert(
        0,
        (
            "observability_guard_over_budget",
            fixture("prom_guard_over.json"),
        ),
    );
    let fake = serve(rules);
    let digest = valid_digest(&fake, s(&pack));
    assert_eq!(digest["stack"]["guard"], json!("over_budget"));
    let file = dir.path().join("in.json");
    fs::write(&file, digest.to_string()).unwrap();
    let run = cli(&fake, &write_args(s(&file), s(&pack)));
    assert_eq!(run.code, 0, "{}", run.err);
}

#[test]
fn digest_write_accepts_long_mcp_row_keys() {
    let tool = "mcp__plugin_claude-code-home-manager_mcp-gateway__gateway_list_tools";
    let single = format!("near_identical:{tool}");
    assert!(single.len() > 80);
    let sequence = format!("sequence:{tool}>{tool}>{tool}");
    assert!(sequence.len() > 200 && sequence.len() <= 256);
    accepts(|d| {
        d["questions"][0]["rows"][0]["key"] = json!(single);
        d["questions"][0]["rows"][1] = json!({"key": sequence, "value": 3});
    });
}

#[test]
fn digest_write_still_rejects_overlong_and_spaced_row_keys() {
    rejects(
        |d| d["questions"][0]["rows"][0]["key"] = json!(format!("sequence:{}", "a".repeat(250))),
        "key",
    );
    rejects(
        |d| d["questions"][0]["rows"][0]["key"] = json!("near_identical:two words"),
        "key",
    );
}

type Mutation = Box<dyn FnOnce(&mut Value)>;

#[test]
fn digest_write_rejects_figures_of_the_wrong_type() {
    let long = "p".repeat(200);
    let row = "questions[0].rows[0]";
    let cases: Vec<(String, Mutation)> = vec![
        (
            format!("{row}.value"),
            Box::new(move |d| d["questions"][0]["rows"][0]["value"] = json!(long)),
        ),
        (
            format!("{row}.share"),
            Box::new(|d| d["questions"][0]["rows"][0]["share"] = json!("lots")),
        ),
        (
            format!("{row}.calls"),
            Box::new(|d| d["questions"][0]["rows"][0]["calls"] = json!("x y")),
        ),
        (
            format!("{row}.sessions"),
            Box::new(|d| d["questions"][0]["rows"][0]["sessions"] = json!(-1)),
        ),
        (
            format!("{row}.sessions"),
            Box::new(|d| d["questions"][0]["rows"][0]["sessions"] = json!(1.5)),
        ),
        (
            "questions[0].truncated".into(),
            Box::new(|d| d["questions"][0]["truncated"] = json!("no")),
        ),
        (
            "questions[0].suppressed".into(),
            Box::new(|d| d["questions"][0]["suppressed"] = json!("two")),
        ),
        (
            "questions[0].suppressed".into(),
            Box::new(|d| d["questions"][0]["suppressed"] = json!(-2)),
        ),
        (
            "totals.tokens".into(),
            Box::new(|d| d["totals"]["tokens"] = json!("many")),
        ),
        (
            "totals.sessions".into(),
            Box::new(|d| d["totals"]["sessions"] = json!(true)),
        ),
        (
            "own_cost.tokens".into(),
            Box::new(|d| d["own_cost"]["tokens"] = json!([1])),
        ),
        (
            "own_cost.est_cost_usd".into(),
            Box::new(|d| d["own_cost"]["est_cost_usd"] = json!({"value": "x"})),
        ),
        (
            "totals.tokens".into(),
            Box::new(|d| d["totals"]["tokens"] = json!({"value": null, "unavailable": "a\nb"})),
        ),
        (
            "totals.tokens".into(),
            Box::new(|d| d["totals"]["tokens"] = json!({"value": null, "unavailable": 7})),
        ),
        (
            "totals.tokens".into(),
            Box::new(|d| d["totals"]["tokens"] = json!({"unavailable": "no value"})),
        ),
        (
            "pack.version".into(),
            Box::new(|d| d["pack"]["version"] = json!("one")),
        ),
        (
            "prior_decisions[0].before".into(),
            Box::new(
                |d| d["prior_decisions"] = json!([{"id": "d1", "status": "acted", "before": "lots", "after": 1, "verdict": "effective"}]),
            ),
        ),
        (
            "prior_decisions[0].after".into(),
            Box::new(
                |d| d["prior_decisions"] = json!([{"id": "d1", "status": "acted", "before": 1, "after": "prose here", "verdict": "effective"}]),
            ),
        ),
    ];
    for (pointer, mutate) in cases {
        rejects(mutate, &pointer);
    }
}

#[test]
fn digest_write_accepts_null_and_unavailable_figures() {
    accepts(|d| {
        d["totals"]["tokens"] = json!(null);
        d["totals"]["est_cost_usd"] =
            json!({"value": null, "unavailable": "no samples in the window"});
        d["questions"][0]["rows"][0]["share"] = json!(null);
        d["questions"][0]["suppressed"] = json!(2);
        d["prior_decisions"] = json!([{"id": "d1", "status": "acted", "before": 5, "after": {"value": null, "unavailable": "metric absent"}, "verdict": "inconclusive"}]);
    });
}
