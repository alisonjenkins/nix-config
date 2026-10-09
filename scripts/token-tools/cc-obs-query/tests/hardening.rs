#![allow(
    clippy::panic,
    clippy::unwrap_in_result,
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]

mod common;

use cc_obs_query::backend::{Backend, Endpoints, LogFetch};
use cc_obs_query::bounds::{render, Bounds, Report};
use cc_obs_query::error::Error;
use cc_obs_query::pack::Pack;
use common::{cli, digest_rules, fixture, s, serve, write_pack};
use serde_json::{json, Value};

fn backend_for(base: &str) -> Backend {
    let endpoints: Endpoints = serde_json::from_str(&common::endpoints_json(base)).unwrap();
    Backend::new(endpoints)
}

fn loki_page(timestamps: &[u64]) -> String {
    let values: Vec<Value> = timestamps
        .iter()
        .map(|ts| json!([ts.to_string(), "line"]))
        .collect();
    json!({"status":"success","data":{"resultType":"streams","result":[
        {"stream":{"service_name":"claude-code","tool_name":"Read"},"values":values}
    ]}})
    .to_string()
}

// ---- item 1: Loki pagination -------------------------------------------------

#[test]
fn loki_is_paged_until_a_short_page() {
    let t0 = 1_000_000_000_000_000_000_u64;
    let second = format!("start={}&", t0 + 2);
    let fake = serve(vec![
        (&second, loki_page(&[t0 + 3])),
        ("start=1000000000000000000&", loki_page(&[t0 + 1, t0 + 2])),
    ]);
    let backend = backend_for(&fake.base);
    let fetched = backend
        .loki_paged(
            "{x=\"y\"}",
            t0 as i64,
            (t0 + 100) as i64,
            LogFetch {
                page_size: 2,
                max_records: 100,
                max_pages: 10,
            },
        )
        .unwrap();
    assert_eq!(fetched.records.len(), 3);
    assert!(!fetched.truncated);
    let stamps: Vec<_> = fetched.records.iter().map(|r| r.ts_ns.clone()).collect();
    assert_eq!(
        stamps.first().map(String::as_str),
        Some("1000000000000000001")
    );
    assert_eq!(
        stamps.last().map(String::as_str),
        Some("1000000000000000003")
    );
}

fn loki_entries(entries: &[(u64, &str)]) -> String {
    let values: Vec<Value> = entries
        .iter()
        .map(|(ts, n)| json!([ts.to_string(), json!({"n": n}).to_string()]))
        .collect();
    json!({"status":"success","data":{"resultType":"streams","result":[
        {"stream":{"service_name":"claude-code"},"values":values}
    ]}})
    .to_string()
}

fn fetch_all(base: &str, t0: u64, page_size: usize) -> cc_obs_query::backend::LogPages {
    backend_for(base)
        .loki_paged(
            "{x=\"y\"}",
            t0 as i64,
            (t0 + 100) as i64,
            LogFetch {
                page_size,
                max_records: 100,
                max_pages: 10,
            },
        )
        .unwrap()
}

#[test]
fn loki_page_boundary_inside_a_timestamp_run_loses_and_duplicates_nothing() {
    let t0 = 1_000_000_000_000_000_000_u64;
    // Loki answers the first `limit` entries at or after `start`.
    let fake = serve(vec![
        (
            &format!("start={}&", t0 + 2),
            loki_entries(&[(t0 + 2, "b"), (t0 + 2, "c"), (t0 + 2, "d"), (t0 + 3, "e")]),
        ),
        (
            &format!("start={}&", t0 + 3),
            loki_entries(&[(t0 + 3, "e")]),
        ),
        (
            "/loki/",
            loki_entries(&[(t0 + 1, "a"), (t0 + 1, "a2"), (t0 + 2, "b"), (t0 + 2, "c")]),
        ),
    ]);
    let fetched = fetch_all(&fake.base, t0, 4);
    let mut names: Vec<_> = fetched
        .records
        .iter()
        .map(|r| r.fields["n"].clone())
        .collect();
    names.sort();
    assert_eq!(names, ["a", "a2", "b", "c", "d", "e"]);
    assert!(!fetched.truncated);
    assert!(fetched.gaps.is_empty(), "{:?}", fetched.gaps);
}

#[test]
fn loki_a_page_of_one_timestamp_advances_one_ns_and_records_a_gap() {
    let t0 = 1_000_000_000_000_000_000_u64;
    let fake = serve(vec![
        (
            &format!("start={}&", t0 + 3),
            loki_entries(&[(t0 + 3, "z")]),
        ),
        ("/loki/", loki_entries(&[(t0 + 2, "b"), (t0 + 2, "c")])),
    ]);
    let fetched = fetch_all(&fake.base, t0, 2);
    let mut names: Vec<_> = fetched
        .records
        .iter()
        .map(|r| r.fields["n"].clone())
        .collect();
    names.sort();
    assert_eq!(names, ["b", "c", "z"]);
    assert_eq!(fetched.gaps.len(), 1, "{:?}", fetched.gaps);
}

#[test]
fn loki_page_cap_reports_truncation() {
    let t0 = 1_000_000_000_000_000_000_u64;
    // every request answers a full page, so only the caps stop the loop
    let (second, third) = (format!("start={}&", t0 + 2), format!("start={}&", t0 + 3));
    let fake = serve(vec![
        (&second, loki_page(&[t0 + 2, t0 + 3])),
        (&third, loki_page(&[t0 + 3, t0 + 4])),
        ("/loki/", loki_page(&[t0 + 1, t0 + 2])),
    ]);
    let backend = backend_for(&fake.base);
    let fetched = backend
        .loki_paged(
            "{x=\"y\"}",
            t0 as i64,
            (t0 + 100) as i64,
            LogFetch {
                page_size: 2,
                max_records: 100,
                max_pages: 3,
            },
        )
        .unwrap();
    assert!(fetched.truncated);
    assert_eq!(fetched.records.len(), 4);
    assert_eq!(fake.seen_matching("query_range").len(), 3);
}

#[test]
fn loki_record_cap_reports_truncation_and_never_exceeds_it() {
    let t0 = 1_000_000_000_000_000_000_u64;
    let fake = serve(vec![("/loki/", loki_page(&[t0 + 1, t0 + 2]))]);
    let backend = backend_for(&fake.base);
    let fetched = backend
        .loki_paged(
            "{x=\"y\"}",
            t0 as i64,
            (t0 + 100) as i64,
            LogFetch {
                page_size: 2,
                max_records: 3,
                max_pages: 50,
            },
        )
        .unwrap();
    assert!(fetched.truncated);
    assert_eq!(fetched.records.len(), 3);
}

fn full_ledger_page() -> String {
    let values: Vec<Value> = (0..5000_u64)
        .map(|i| {
            json!([
                (1_760_000_000_000_000_000_u64 + i).to_string(),
                "cc_obs_ledger.tool_call",
                {"structuredMetadata": {
                    "session_id": "s1", "tool_name": "Read", "input_hash": "h",
                    "turn": i.to_string(), "seq": i.to_string(), "result_bytes": "10"
                }}
            ])
        })
        .collect();
    json!({"status":"success","data":{"resultType":"streams","result":[
        {"stream":{"service_name":"cc-obs-ledger"},"values":values}
    ]}})
    .to_string()
}

#[test]
fn a_command_over_capped_logs_says_so_in_its_output() {
    let mut rules = vec![("event_name=\"cc_obs_ledger.tool_call\"", full_ledger_page())];
    rules.extend(common::own_cost_rules());
    let fake = serve(rules);
    let out = cli(&fake, &["repeats"]).json();
    let gaps = out["gaps"].as_array().expect("a gaps note");
    assert!(gaps[0].as_str().unwrap().contains("loki"), "{gaps:?}");
}

#[test]
fn a_digest_over_capped_logs_lists_the_gap_in_stack_gaps() {
    let dir = tempfile::tempdir().unwrap();
    let pack = write_pack(
        dir.path(),
        "version: 1\nquestions:\n  - id: repeat-calls\n    title: Repeats\n    signals: [cc_obs_ledger.tool_call]\n    query: { command: \"cc-obs-query repeats\" }\n    decision_kind: configure\n",
    );
    let mut rules = vec![("event_name=\"cc_obs_ledger.tool_call\"", full_ledger_page())];
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
    let gaps = run.json()["stack"]["gaps"].clone();
    assert!(
        gaps.as_array()
            .unwrap()
            .iter()
            .any(|g| g.as_str().unwrap().contains("repeat-calls")
                && g.as_str().unwrap().contains("loki")),
        "{gaps}"
    );
}

// ---- item 3: label values are escaped ---------------------------------------

#[test]
fn session_ids_with_quotes_stay_inside_the_label_value() {
    let fake = serve(common::with_own(vec![(
        "cc_obs_ledger_context_tokens",
        fixture("prom_empty.json"),
    )]));
    let run = cli(&fake, &["session", "x\"} or vector(1) #"]);
    assert_eq!(run.code, 0, "{}", run.err);
    let sent = fake.seen_matching("cc_obs_ledger_context_tokens");
    assert!(!sent.is_empty());
    for request in sent {
        assert!(
            request.contains(r#"session_id="x\"} or vector(1) #""#),
            "value not escaped: {request}"
        );
        assert!(request.contains("review_run!=\"1\""), "{request}");
    }
}

#[test]
fn session_ids_with_control_characters_are_refused_before_any_query() {
    let fake = serve(vec![]);
    let run = cli(&fake, &["session", "a\nb"]);
    assert_ne!(run.code, 0);
    let err = run.err_json();
    assert!(err["error"].as_str().unwrap().contains("control"), "{err}");
    assert!(fake.seen().is_empty());
}

// ---- item 4: bounds ----------------------------------------------------------

fn report(n: usize) -> Report {
    let mut r = Report::new("x");
    r.rows = (0..n).map(|i| json!({"key": format!("k{i}")})).collect();
    r
}

#[test]
fn a_byte_cap_that_cannot_hold_one_row_is_a_usage_error() {
    let err = render(
        &report(3),
        &Bounds {
            max_bytes: 20,
            ..Bounds::default()
        },
    )
    .unwrap_err();
    let text = err.to_string();
    assert!(matches!(err, Error::Usage { .. }), "{text}");
    assert!(text.contains("--max-bytes 20 is too small"), "{text}");
    assert!(text.contains("need at least"), "{text}");
}

#[test]
fn limit_zero_is_rejected() {
    let err = render(
        &report(3),
        &Bounds {
            limit: 0,
            ..Bounds::default()
        },
    )
    .unwrap_err();
    assert!(err.to_string().contains("--limit"), "{err}");
}

#[test]
fn following_next_always_advances_and_terminates() {
    let report = report(9);
    let mut offset = 0;
    for _ in 0..20 {
        let out: Value = serde_json::from_str(
            &render(
                &report,
                &Bounds {
                    limit: 10,
                    max_bytes: 110,
                    offset,
                    ..Bounds::default()
                },
            )
            .unwrap(),
        )
        .unwrap();
        let Some(next) = out["next"].as_str() else {
            return;
        };
        let advanced: usize = next.trim_start_matches("--offset ").parse().unwrap();
        assert!(advanced > offset, "next {advanced} did not pass {offset}");
        offset = advanced;
    }
    panic!("never reached the end");
}

#[test]
fn the_cli_refuses_a_hopeless_byte_cap_and_limit_zero() {
    let fake = serve(common::with_own(vec![(
        "by (model)",
        fixture("prom_tokens_by_model.json"),
    )]));
    let tiny = cli(&fake, &["top", "model", "--max-bytes", "10"]);
    assert_ne!(tiny.code, 0);
    assert!(tiny.err_json()["error"]
        .as_str()
        .unwrap()
        .contains("too small"));
    let zero = cli(&fake, &["top", "model", "--limit", "0"]);
    assert_ne!(zero.code, 0);
}

// ---- item 6: pack typos ------------------------------------------------------

fn load_pack_text(yaml: &str) -> Result<Pack, Error> {
    let dir = tempfile::tempdir().unwrap();
    let path = write_pack(dir.path(), yaml);
    Pack::load(&path)
}

#[test]
fn a_typo_in_a_threshold_names_the_field_and_the_question() {
    let err = load_pack_text(
        "version: 1\nquestions:\n  - id: some-question\n    title: T\n    signals: [claude_code.token.usage]\n    query: { command: \"cc-obs-query top model\" }\n    threshold: { min_shar: 0.1 }\n",
    )
    .unwrap_err()
    .to_string();
    assert!(err.contains("min_shar"), "{err}");
    assert!(err.contains("some-question"), "{err}");
}

#[test]
fn a_typo_in_a_question_or_the_pack_is_refused() {
    let question = load_pack_text(
        "version: 1\nquestions:\n  - id: q1\n    title: T\n    signals: [claude_code.token.usage]\n    quary: { command: \"cc-obs-query top model\" }\n    query: { command: \"cc-obs-query top model\" }\n",
    )
    .unwrap_err()
    .to_string();
    assert!(
        question.contains("quary") && question.contains("q1"),
        "{question}"
    );
    let top = load_pack_text("version: 1\nregrowth_factr: 2\nquestions: []\n")
        .unwrap_err()
        .to_string();
    assert!(top.contains("regrowth_factr"), "{top}");
}

// ---- item 9: trace ids -------------------------------------------------------

#[test]
fn trace_ids_must_be_short_hex() {
    let backend = backend_for("http://127.0.0.1:1");
    for bad in ["../admin", "abc/def", "", "xyz", &"a".repeat(33), "ab?x=1"] {
        let err = backend.tempo_trace(bad).unwrap_err();
        assert!(
            matches!(err, Error::BadArgument { .. }),
            "{bad:?} reached the network: {err}"
        );
    }
}

// ---- item 8: cache tokens are not summed with new tokens ---------------------

const NO_CACHE: &str = "type!~\"cacheRead|cacheCreation\"";

#[test]
fn token_figures_leave_out_cache_reads_and_writes() {
    let fake = serve(common::with_own(vec![(
        "by (model)",
        fixture("prom_tokens_by_model.json"),
    )]));
    let run = cli(&fake, &["top", "model"]);
    assert_eq!(run.code, 0, "{}", run.err);
    assert!(!fake.seen_matching("by (model)").is_empty());
    for request in fake.seen_matching("claude_code_token_usage_tokens_total") {
        assert!(request.contains(NO_CACHE), "{request}");
    }
    // cost has no token type to filter on
    for request in fake.seen_matching("claude_code_cost_usage_USD_total") {
        assert!(!request.contains("type!~"), "{request}");
    }
}

#[test]
fn include_review_still_leaves_out_cache_tokens() {
    let fake = serve(vec![("by (model)", fixture("prom_tokens_by_model.json"))]);
    let run = cli(&fake, &["top", "model", "--include-review"]);
    assert_eq!(run.code, 0, "{}", run.err);
    for request in fake.seen_matching("by (model)") {
        assert!(
            request.contains(NO_CACHE) && !request.contains("review_run"),
            "{request}"
        );
    }
}

#[test]
fn top_help_says_what_by_tokens_counts() {
    let fake = serve(vec![]);
    let run = cli(&fake, &["top", "--help"]);
    assert_eq!(run.code, 0);
    assert!(run.out.contains("cache"), "{}", run.out);
}

// ---- item 2: repeats rows carry the group's call count -----------------------

fn ledger_rules() -> Vec<(&'static str, String)> {
    common::with_own(vec![(
        "event_name=\"cc_obs_ledger.tool_call\"",
        fixture("loki_ledger_calls.json"),
    )])
}

#[test]
fn repeats_rows_count_calls_apart_from_redundant_calls() {
    let fake = serve(ledger_rules());
    let out = cli(&fake, &["repeats"]).json();
    let identical = common::row(&out, "identical:Read");
    assert_eq!(identical["value"], json!(1), "redundant calls");
    assert_eq!(identical["calls"], json!(2), "calls in the group");
    assert_eq!(
        common::row(&out, "sequence:Read>Read>Grep")["calls"],
        json!(2)
    );
}

#[test]
fn min_calls_applies_to_the_repeat_calls_question() {
    let dir = tempfile::tempdir().unwrap();
    let pack = |min_calls: u32| {
        format!(
            "version: 1\nquestions:\n  - id: repeat-calls\n    title: Repeats\n    signals: [cc_obs_ledger.tool_call]\n    query: {{ command: \"cc-obs-query repeats\" }}\n    decision_kind: configure\n    threshold: {{ min_calls: {min_calls} }}\n"
        )
    };
    let run_with = |min_calls: u32| {
        let path = write_pack(dir.path(), &pack(min_calls));
        let mut rules = ledger_rules();
        rules.extend(digest_rules(fixture("loki_tool_results.json")));
        let fake = serve(rules);
        let run = cli(
            &fake,
            &[
                "digest",
                "--baseline",
                "--pack",
                s(&path),
                "--since",
                "7d",
                "--until",
                "2026-10-09",
            ],
        );
        assert_eq!(run.code, 0, "{}", run.err);
        run.json()["questions"][0]["rows"].as_array().unwrap().len()
    };
    assert!(run_with(1) > 0);
    assert_eq!(run_with(3), 0, "no group in the fixture has 3 calls");
}

// ---- item 7: --by values and pack command flags -------------------------------

#[test]
fn top_session_by_cache_hit_lists_the_worst_ratio_first() {
    let body = r#"{"status":"success","data":{"resultType":"vector","result":[{"metric":{"session_id":"s1"},"value":[1.0,"0.9"]},{"metric":{"session_id":"s2"},"value":[1.0,"0.2"]}]}}"#;
    let fake = serve(common::with_own(vec![(
        "cc_obs_ledger_cache_hit_ratio",
        body.to_owned(),
    )]));
    let run = cli(&fake, &["top", "session", "--by", "cache-hit"]);
    assert_eq!(run.code, 0, "{}", run.err);
    let out = run.json();
    let keys: Vec<_> = common::rows(&out)
        .iter()
        .map(|r| r["key"].clone())
        .collect();
    assert_eq!(keys, vec![json!("s2"), json!("s1")]);
    assert_eq!(common::rows(&out)[0]["value"], json!(0.2));
    assert!(common::rows(&out)[0].get("share").is_none());
    assert_eq!(out["by"], json!("cache-hit"));
}

#[test]
fn top_session_by_compactions_counts_compaction_events() {
    let line = |ts: u64, session: &str, pre: u64, post: u64| {
        json!({"stream": {"service_name": "claude-code", "event_name": "compaction",
            "session_id": session, "pre_tokens": pre.to_string(), "post_tokens": post.to_string()},
            "values": [[ts.to_string(), "compaction"]]})
    };
    let body = json!({"status":"success","data":{"resultType":"streams","result":[
        line(1_760_000_000_000_000_001, "s1", 100_000, 20_000),
        line(1_760_000_000_000_000_002, "s1", 120_000, 30_000),
        line(1_760_000_000_000_000_003, "s2", 90_000, 10_000),
    ]}})
    .to_string();
    let fake = serve(common::with_own(vec![("event_name=\"compaction\"", body)]));
    let run = cli(
        &fake,
        &[
            "top",
            "session",
            "--by",
            "compactions",
            "--format",
            "detailed",
        ],
    );
    assert_eq!(run.code, 0, "{}", run.err);
    let out = run.json();
    assert_eq!(common::row(&out, "s1")["value"], json!(2));
    assert_eq!(common::row(&out, "s1")["mean_pre_tokens"], json!(110000));
    assert_eq!(common::row(&out, "s2")["value"], json!(1));
    assert_eq!(common::rows(&out)[0]["key"], json!("s1"));
}

#[test]
fn top_memory_by_hit_rate_lists_the_lowest_ratio_first() {
    let vector = |a: &str, b: &str| {
        format!(
            r#"{{"status":"success","data":{{"resultType":"vector","result":[{{"metric":{{"service":"a"}},"value":[1.0,"{a}"]}},{{"metric":{{"service":"b"}},"value":[1.0,"{b}"]}}]}}}}"#
        )
    };
    let fake = serve(common::with_own(vec![
        ("recall_requests_total", vector("10", "10")),
        ("recall_hits_total", vector("5", "9")),
    ]));
    let run = cli(&fake, &["top", "memory", "--by", "hit-rate"]);
    assert_eq!(run.code, 0, "{}", run.err);
    let out = run.json();
    let keys: Vec<_> = common::rows(&out)
        .iter()
        .map(|r| r["key"].clone())
        .collect();
    assert_eq!(keys, vec![json!("a"), json!("b")]);
    assert_eq!(common::rows(&out)[0]["value"], json!(0.5));
}

#[test]
fn by_values_on_the_wrong_category_are_unavailable_not_wrong() {
    let fake = serve(common::with_own(vec![]));
    for args in [
        ["top", "model", "--by", "cache-hit"],
        ["top", "model", "--by", "compactions"],
        ["top", "model", "--by", "hit-rate"],
    ] {
        let out = cli(&fake, &args).json();
        assert_eq!(out["value"], json!(null), "{args:?}");
        assert!(out["unavailable"].is_string(), "{args:?}");
    }
}

#[test]
fn a_pack_command_with_a_flag_the_digest_would_ignore_is_refused() {
    let dir = tempfile::tempdir().unwrap();
    let path = write_pack(
        dir.path(),
        "version: 1\nquestions:\n  - id: windowed\n    title: T\n    signals: [claude_code.token.usage]\n    query: { command: \"cc-obs-query top model --since 30d\" }\n    decision_kind: configure\n",
    );
    let fake = serve(digest_rules(fixture("loki_tool_results.json")));
    let run = cli(
        &fake,
        &[
            "digest",
            "--baseline",
            "--pack",
            s(&path),
            "--until",
            "2026-10-09",
        ],
    );
    assert_eq!(run.code, 0, "{}", run.err);
    let digest = run.json();
    let unavailable = digest["questions"][0]["unavailable"].as_str().unwrap();
    assert!(unavailable.contains("--since"), "{unavailable}");
    assert!(digest["stack"]["gaps"].to_string().contains("windowed"));
}
