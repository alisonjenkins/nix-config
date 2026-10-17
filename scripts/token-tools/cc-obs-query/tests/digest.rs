#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]

mod common;

use std::fs;

use common::{cli, digest_rules, fixture, s, serve, write_pack, Fake, TOOL_PACK};
use serde_json::{json, Value};

const UNTIL: &str = "2026-10-09";

fn baseline(fake: &Fake, pack: &str) -> common::Run {
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

fn valid_digest(fake: &Fake, pack: &str) -> Value {
    let run = baseline(fake, pack);
    assert_eq!(run.code, 0, "{}", run.err);
    run.json()
}

fn write_args<'a>(file: &'a str, pack: &'a str) -> Vec<&'a str> {
    vec!["digest", "--write", file, "--pack", pack, "--until", UNTIL]
}

/// Mutate a baseline digest and run `--write`; returns the run.
fn write_mutated(
    rules: Vec<(&'static str, String)>,
    pack_yaml: &str,
    mutate: impl FnOnce(&mut Value),
) -> common::Run {
    let dir = tempfile::tempdir().unwrap();
    let pack = write_pack(dir.path(), pack_yaml);
    let fake = serve(rules);
    let mut digest = valid_digest(&fake, s(&pack));
    mutate(&mut digest);
    let file = dir.path().join("in.json");
    fs::write(&file, digest.to_string()).unwrap();
    cli(&fake, &write_args(s(&file), s(&pack)))
}

fn rejects(mutate: impl FnOnce(&mut Value), needle: &str) {
    let run = write_mutated(
        digest_rules(fixture("loki_tool_results.json")),
        TOOL_PACK,
        mutate,
    );
    assert_ne!(run.code, 0, "accepted: {}", run.out);
    let err = run.err_json();
    assert!(
        err["error"].as_str().unwrap().contains(needle),
        "{needle} not in {err}"
    );
}

#[test]
fn digest_write_rejects_non_string_free_text_fields() {
    type Case = (&'static str, Box<dyn Fn(&mut Value)>);
    let cases: Vec<Case> = vec![
        (
            "questions[0].unavailable",
            Box::new(|d| d["questions"][0]["unavailable"] = json!({"note": "p".repeat(150)})),
        ),
        (
            "rows[0].pattern",
            Box::new(|d| d["questions"][0]["rows"][0]["pattern"] = json!(["a prose sentence"])),
        ),
        (
            "rows[0].regrowth_of",
            Box::new(|d| d["questions"][0]["rows"][0]["regrowth_of"] = json!({"x": "y z"})),
        ),
        (
            "rows[0].evidence",
            Box::new(|d| d["questions"][0]["rows"][0]["evidence"] = json!({"x": "y z"})),
        ),
        (
            "stack.gaps[0]",
            Box::new(|d| d["stack"]["gaps"] = json!([{"x": "p".repeat(150)}])),
        ),
        (
            "prior_decisions[0].id",
            Box::new(|d| {
                d["prior_decisions"] = json!([{"id": {"x": "a b"}, "status": "acted"}]);
            }),
        ),
        (
            "prior_decisions[0].status",
            Box::new(|d| d["prior_decisions"] = json!([{"id": "0001", "status": ["a b"]}])),
        ),
        (
            "prior_decisions[0].verdict",
            Box::new(|d| {
                d["prior_decisions"] =
                    json!([{"id": "0001", "status": "acted", "verdict": {"x": "a b"}}]);
            }),
        ),
    ];
    for (path, mutate) in cases {
        rejects(mutate, path);
    }
}

#[test]
fn digest_write_cap_uses_compact_size() {
    let dir = tempfile::tempdir().unwrap();
    let pack = write_pack(dir.path(), TOOL_PACK);
    let fake = serve(digest_rules(fixture("loki_tool_results.json")));
    let mut digest = valid_digest(&fake, s(&pack));
    let rows: Vec<Value> = (0..700)
        .map(|i| json!({"key": format!("k{i}"), "value": i}))
        .collect();
    digest["questions"][0]["rows"] = Value::Array(rows);
    let compact = digest.to_string().len();
    let pretty = serde_json::to_string_pretty(&digest).unwrap();
    assert!(
        compact <= 32_768 && pretty.len() > 32_768,
        "{compact} {}",
        pretty.len()
    );
    let file = dir.path().join("in.json");
    fs::write(&file, pretty).unwrap();
    let run = cli(&fake, &write_args(s(&file), s(&pack)));
    assert_eq!(run.code, 0, "{}", run.err);
}

fn decision(id_field: &str, kind: &str, baseline: u64) -> String {
    format!(
        "---\nid: {id_field}\nhost: test-host\ndate: 2026-09-01T00:00:00Z\nfinding: 2026-09-01-test-host#1\ndecision: {kind}\nreason: because\nmetric: {{ question: tool-result-size, key: Read, baseline: {baseline}, unit: tokens/week }}\nacted_on: null\noutcome: null\noutcome_review: null\n---\n"
    )
}

fn baseline_with_decisions(files: &[(&str, String)]) -> common::Run {
    let dir = tempfile::tempdir().unwrap();
    let pack = write_pack(dir.path(), TOOL_PACK);
    fs::create_dir(dir.path().join("decisions")).unwrap();
    for (name, body) in files {
        fs::write(dir.path().join("decisions").join(name), body).unwrap();
    }
    let fake = serve(digest_rules(fixture("loki_tool_results.json")));
    baseline(&fake, s(&pack))
}

#[test]
fn crlf_decision_is_loaded_or_rejected() {
    // Read is 25000 tokens in the window, under 1.5 * 20000, so a loaded dismissal hides it
    let crlf = decision("\"0003\"", "dismiss", 20_000).replace('\n', "\r\n");
    let run = baseline_with_decisions(&[("0003-read.md", crlf)]);
    if run.code == 0 {
        let d = run.json();
        assert_eq!(
            d["questions"][0]["suppressed"],
            json!(1),
            "a CRLF dismissal was silently ignored: {d}"
        );
    } else {
        assert!(run.err.contains("0003-read.md"), "{}", run.err);
    }
}

#[test]
fn decision_without_front_matter_is_reported_not_skipped() {
    let run = baseline_with_decisions(&[("0003-read.md", "just some prose\n".to_owned())]);
    assert_eq!(run.code, 0, "{}", run.err);
    let gaps = run.json()["stack"]["gaps"].to_string();
    assert!(gaps.contains("0003-read.md"), "{gaps}");
}

#[test]
fn unknown_decision_value_is_rejected() {
    let run = baseline_with_decisions(&[("0003-read.md", decision("\"0003\"", "dismis", 20_000))]);
    assert_ne!(run.code, 0, "accepted: {}", run.out);
    assert!(run.err.contains("dismis"), "{}", run.err);
}

#[test]
fn closing_fence_must_be_a_whole_line() {
    let body = format!(
        "{}----\nnot yaml: [\n",
        decision("\"0003\"", "dismiss", 20_000)
    );
    let run = baseline_with_decisions(&[("0003-read.md", body)]);
    assert_eq!(run.code, 0, "{}", run.err);
    assert_eq!(run.json()["questions"][0]["suppressed"], json!(1));
}

#[test]
fn unquoted_numeric_decision_id_is_loaded_or_clearly_rejected() {
    let run = baseline_with_decisions(&[("0007-read.md", decision("0007", "dismiss", 20_000))]);
    if run.code == 0 {
        assert_eq!(run.json()["questions"][0]["suppressed"], json!(1));
    } else {
        assert!(run.err.contains("quote"), "unhelpful error: {}", run.err);
    }
}

#[test]
fn num_rounds_token_counts_and_never_yields_null() {
    use cc_obs_query::bounds::num;
    for bad in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
        assert_ne!(num(bad), Value::Null, "num({bad}) vanished into null");
        assert!(num(bad).is_object(), "num({bad}) = {}", num(bad));
    }
    let rules: Vec<(&'static str, String)> = digest_rules(fixture("loki_tool_results.json"))
        .into_iter()
        .map(|(needle, body)| {
            if needle == "sum(increase(claude_code_token_usage_tokens_total" {
                (needle, prom_scalar(8_773_294.633_4))
            } else {
                (needle, body)
            }
        })
        .collect();
    let dir = tempfile::tempdir().unwrap();
    let pack = write_pack(dir.path(), TOOL_PACK);
    let fake = serve(rules);
    let digest = valid_digest(&fake, s(&pack));
    assert_eq!(
        digest["totals"]["tokens"],
        json!(8_773_295),
        "token totals are whole numbers"
    );
}

#[test]
fn table_cells_escape_tabs_and_newlines() {
    use cc_obs_query::bounds::{render, Bounds, Format, Report};
    let mut report = Report::new("x");
    report.rows = vec![json!({"key": "a\tb\nc", "value": 1})];
    let out = render(
        &report,
        &Bounds {
            format: Format::Table,
            ..Bounds::default()
        },
    )
    .unwrap();
    assert_eq!(out.lines().count(), 2, "header plus one row: {out:?}");
    assert_eq!(
        out.lines().nth(1).unwrap().split('\t').count(),
        2,
        "{out:?}"
    );
}

#[test]
fn unavailable_question_does_not_report_metric_absent() {
    let rules: Vec<_> = digest_rules(fixture("loki_tool_results.json"))
        .into_iter()
        .filter(|(needle, _)| *needle != "event_name=\"tool_result\"")
        .collect();
    let dir = tempfile::tempdir().unwrap();
    let pack = write_pack(dir.path(), TOOL_PACK);
    fs::create_dir(dir.path().join("decisions")).unwrap();
    let acted =
        decision("\"0007\"", "build", 50_000).replace("acted_on: null", "acted_on: abc1234");
    fs::write(dir.path().join("decisions/0007-read.md"), acted).unwrap();
    let fake = serve(rules);
    let digest = valid_digest(&fake, s(&pack));
    assert!(
        digest["questions"][0]["unavailable"].is_string(),
        "{digest}"
    );
    let after = digest["prior_decisions"][0]["after"]["unavailable"]
        .as_str()
        .unwrap();
    assert!(after.contains("unavailable"), "{after}");
    assert!(!after.contains("absent"), "{after}");
}

fn tool_pack_with(command_tail: &str) -> String {
    TOOL_PACK.replace(
        "cc-obs-query top tool --by tokens",
        &format!("cc-obs-query {command_tail}"),
    )
}

#[test]
fn pack_query_limit_zero_is_refused() {
    let dir = tempfile::tempdir().unwrap();
    let pack = write_pack(
        dir.path(),
        &tool_pack_with("top tool --by tokens --limit 0"),
    );
    let fake = serve(digest_rules(fixture("loki_tool_results.json")));
    let digest = valid_digest(&fake, s(&pack));
    let q = &digest["questions"][0];
    assert!(
        q["unavailable"]
            .as_str()
            .is_some_and(|u| u.contains("--limit 0")),
        "limit 0 silently emptied the rows: {q}"
    );
    assert_eq!(q["truncated"], json!(false), "{q}");
}

#[test]
fn digest_truncated_means_more_rows_than_limit() {
    let dir = tempfile::tempdir().unwrap();
    let fake = serve(digest_rules(fixture("loki_tool_results.json")));
    // the fixture has three tools
    for (limit, rows, truncated) in [(2, 2, true), (3, 3, false), (4, 3, false)] {
        let pack = write_pack(
            dir.path(),
            &tool_pack_with(&format!("top tool --by tokens --limit {limit}")),
        );
        let q = valid_digest(&fake, s(&pack))["questions"][0].clone();
        assert_eq!(
            q["rows"].as_array().unwrap().len(),
            rows,
            "limit {limit}: {q}"
        );
        assert_eq!(q["truncated"], json!(truncated), "limit {limit}: {q}");
    }
}

fn unused_signals_on(yaml: &str) -> common::Run {
    let dir = tempfile::tempdir().unwrap();
    let pack = write_pack(dir.path(), yaml);
    let fake = serve(vec![]);
    cli(&fake, &["unused-signals", "--pack", s(&pack)])
}

fn assert_pack_refused(yaml: &str, needle: &str) {
    let run = unused_signals_on(yaml);
    assert_ne!(run.code, 0, "accepted: {}", run.out);
    assert!(run.err.contains(needle), "{needle} not in {}", run.err);
}

#[test]
fn pack_rejects_nonpositive_regrowth() {
    for factor in ["0", "-1.5", ".nan", "0.5"] {
        let yaml = TOOL_PACK.replace(
            "regrowth_factor: 1.5",
            &format!("regrowth_factor: {factor}"),
        );
        assert_pack_refused(&yaml, "regrowth_factor");
    }
}

#[test]
fn pack_rejects_out_of_range_min_share() {
    for share in ["-0.1", "1.5"] {
        let yaml = TOOL_PACK.replace("min_share: 0.03", &format!("min_share: {share}"));
        assert_pack_refused(&yaml, "min_share");
    }
}

#[test]
fn pack_rejects_non_query_command() {
    assert_pack_refused(&tool_pack_with("digest --baseline"), "not a query command");
    assert_pack_refused(
        &tool_pack_with("compare x --a 1 --b 2"),
        "not a query command",
    );
}

#[test]
fn pack_rejects_repeated_or_contradictory_signals() {
    let twice = TOOL_PACK.replace(
        "signals: [claude_code.token.usage, claude_code.tool_result.tool_result_size_bytes]",
        "signals: [claude_code.token.usage, claude_code.token.usage]",
    );
    assert_pack_refused(&twice, "twice");
    let retired = TOOL_PACK.replace("retire: []", "retire: [claude_code.token.usage]");
    assert_pack_refused(&retired, "retire");
    let retire_twice = TOOL_PACK.replace(
        "retire: []",
        "retire: [claude_code.api_error, claude_code.api_error]",
    );
    assert_pack_refused(&retire_twice, "twice");
}

fn prom_scalar(value: f64) -> String {
    json!({"status":"success","data":{"resultType":"vector","result":[{"metric":{},"value":[1_760_000_000.0, value.to_string()]}]}}).to_string()
}

fn prom_vector(label: &str, samples: &[(&str, f64)]) -> String {
    let result: Vec<Value> = samples
        .iter()
        .map(|(key, value)| {
            json!({"metric": {label: key}, "value": [1_760_000_000.0, value.to_string()]})
        })
        .collect();
    json!({"status":"success","data":{"resultType":"vector","result":result}}).to_string()
}

const MEMORY_PACK: &str = r#"version: 1
questions:
  - id: memory-hit-rate
    title: Which recall services are injected but rarely used?
    signals: [recall_requests_total, recall_hits_total]
    query: { command: "cc-obs-query top memory --by hit-rate" }
    decision_kind: configure
"#;

#[test]
fn digest_write_accepts_baseline_evidence_for_zero_injection_service() {
    let mut rules = vec![
        (
            "increase(recall_requests_total",
            prom_vector("service", &[("svc-a", 10.0)]),
        ),
        (
            "increase(recall_hits_total",
            prom_vector("service", &[("svc-a", 4.0)]),
        ),
        (
            "increase(recall_tokens_injected_total",
            fixture("prom_empty.json"),
        ),
    ];
    rules.extend(digest_rules(fixture("loki_tool_results.json")));
    let dir = tempfile::tempdir().unwrap();
    let pack = write_pack(dir.path(), MEMORY_PACK);
    let fake = serve(rules);
    let digest = valid_digest(&fake, s(&pack));
    assert_eq!(
        digest["questions"][0]["rows"][0]["evidence"],
        json!("memory:svc-a"),
        "{digest}"
    );
    let file = dir.path().join("in.json");
    fs::write(&file, digest.to_string()).unwrap();
    let run = cli(&fake, &write_args(s(&file), s(&pack)));
    assert_eq!(run.code, 0, "{}", run.err);
}
