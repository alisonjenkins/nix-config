#![allow(
    clippy::panic,
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]

//! `top` options added for the token-review questions: request counts, context
//! growth, fixed-context share, MCP and skill usage, recall tokens per request,
//! and the `repeats --tool` filter.

mod common;

use common::{cli, row, rows, serve, with_own};
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

fn keys(out: &Value) -> Vec<String> {
    rows(out)
        .iter()
        .map(|r| r["key"].as_str().unwrap().to_owned())
        .collect()
}

#[test]
fn top_session_by_requests_ranks_main_and_subagent_separately() {
    let fake = serve(with_own(vec![(
        "cc_obs_ledger_requests_total",
        vector(&[
            (&[("session_id", "s1"), ("agent", "main")], "40"),
            (&[("session_id", "s1"), ("agent", "subagent")], "559"),
            (&[("session_id", "s2"), ("agent", "main")], "12"),
        ]),
    )]));
    let run = cli(&fake, &["top", "session", "--by", "requests"]);
    assert_eq!(run.code, 0, "{}", run.err);
    let out = run.json();
    assert_eq!(keys(&out), vec!["s1/subagent", "s1", "s2"]);
    assert_eq!(row(&out, "s1/subagent")["value"], json!(559));
}

#[test]
fn top_session_by_requests_without_the_counter_says_what_is_missing() {
    let fake = serve(with_own(vec![(
        "cc_obs_ledger_requests_total",
        vector(&[]),
    )]));
    let out = cli(&fake, &["top", "session", "--by", "requests"]).json();
    assert_eq!(out["value"], json!(null));
    assert!(
        out["unavailable"]
            .as_str()
            .unwrap()
            .contains("cc_obs_ledger_requests_total"),
        "{out}"
    );
}

#[test]
fn top_session_by_context_growth_is_max_minus_first_turn_per_agent() {
    // the sub-agent grows 53k to 847k; the main agent of the same session stays flat
    let fake = serve(with_own(vec![(
        "cc_obs_ledger_context_tokens",
        vector(&[
            (
                &[
                    ("session_id", "s1"),
                    ("agent", "subagent"),
                    ("model", "m"),
                    ("turn", "1"),
                ],
                "53000",
            ),
            (
                &[
                    ("session_id", "s1"),
                    ("agent", "subagent"),
                    ("model", "m"),
                    ("turn", "2"),
                ],
                "847000",
            ),
            (
                &[
                    ("session_id", "s1"),
                    ("agent", "subagent"),
                    ("model", "m"),
                    ("turn", "3"),
                ],
                "700000",
            ),
            (
                &[
                    ("session_id", "s1"),
                    ("agent", "main"),
                    ("model", "m"),
                    ("turn", "1"),
                ],
                "90000",
            ),
            (
                &[
                    ("session_id", "s1"),
                    ("agent", "main"),
                    ("model", "m"),
                    ("turn", "2"),
                ],
                "95000",
            ),
            (
                &[
                    ("session_id", "s2"),
                    ("agent", "main"),
                    ("model", "m"),
                    ("turn", "1"),
                ],
                "20000",
            ),
        ]),
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
    let out = run.json();
    assert_eq!(keys(&out), vec!["s1/subagent", "s1", "s2"]);
    assert_eq!(row(&out, "s1/subagent")["value"], json!(794000));
    assert_eq!(row(&out, "s1")["value"], json!(5000));
    assert_eq!(row(&out, "s2")["value"], json!(0));
    assert_eq!(
        row(&out, "s1/subagent")["max_context_tokens"],
        json!(847000)
    );
}

#[test]
fn requests_and_context_growth_belong_to_session_only() {
    let fake = serve(with_own(vec![]));
    for by in ["requests", "context-growth"] {
        let out = cli(&fake, &["top", "model", "--by", by]).json();
        assert!(
            out["unavailable"].as_str().unwrap().contains("session"),
            "{by}: {out}"
        );
    }
}

fn fixed_rules() -> Vec<(&'static str, String)> {
    with_own(vec![
        (
            "avg(avg_over_time(cc_obs_ledger_context_tokens",
            vector(&[(&[], "100000")]),
        ),
        (
            "cc_obs_ledger_fixed_context_tokens",
            vector(&[
                (&[("component", "total")], "30000"),
                (&[("component", "instructions")], "20000"),
                (&[("component", "skills_listing")], "10000"),
            ]),
        ),
    ])
}

#[test]
fn top_fixed_by_share_divides_fixed_by_the_average_request_context() {
    let fake = serve(fixed_rules());
    let run = cli(&fake, &["top", "fixed", "--by", "share"]);
    assert_eq!(run.code, 0, "{}", run.err);
    let out = run.json();
    assert_eq!(keys(&out), vec!["total", "instructions", "skills_listing"]);
    assert_eq!(row(&out, "total")["value"], json!(0.3));
    assert_eq!(row(&out, "instructions")["value"], json!(0.2));
    assert_eq!(row(&out, "skills_listing")["value"], json!(0.1));
    assert!(
        row(&out, "total").get("share").is_none(),
        "a ratio has no share of a sum"
    );
}

#[test]
fn top_fixed_by_share_without_request_context_is_unavailable() {
    let mut rules = vec![(
        "avg(avg_over_time(cc_obs_ledger_context_tokens",
        vector(&[]),
    )];
    rules.extend(fixed_rules());
    let out = cli(&serve(rules), &["top", "fixed", "--by", "share"]).json();
    assert_eq!(out["value"], json!(null));
    assert!(
        out["unavailable"]
            .as_str()
            .unwrap()
            .contains("cc_obs_ledger_context_tokens"),
        "{out}"
    );
}

#[test]
fn share_belongs_to_fixed_only() {
    let out = cli(&serve(with_own(vec![])), &["top", "model", "--by", "share"]).json();
    assert!(
        out["unavailable"].as_str().unwrap().contains("fixed"),
        "{out}"
    );
}

fn tool_results(calls: &[(&str, &str)]) -> String {
    let streams: Vec<Value> = calls
        .iter()
        .enumerate()
        .map(|(i, (tool, bytes))| {
            json!({
                "stream": {
                    "service_name": "claude-code",
                    "event_name": "tool_result",
                    "tool_name": tool,
                    "tool_result_size_bytes": bytes,
                    "session_id": "s1",
                },
                "values": [[format!("{}", 1_760_000_000_000_000_000_u64 + i as u64), "tool_result"]],
            })
        })
        .collect();
    json!({"status": "success", "data": {"resultType": "streams", "result": streams}}).to_string()
}

fn mcp_results() -> String {
    tool_results(&[
        ("Read", "10000"),
        ("mcp__alpha__search", "40000"),
        ("mcp__alpha__fetch", "8000"),
        ("mcp__beta__ping", "4000"),
        ("mcp__plugin_x_gw__invoke", "400"),
    ])
}

#[test]
fn top_mcp_sums_tool_result_tokens_by_server_name_prefix() {
    let fake = serve(with_own(vec![(
        "event_name=\"tool_result\"",
        mcp_results(),
    )]));
    let run = cli(&fake, &["top", "mcp"]);
    assert_eq!(run.code, 0, "{}", run.err);
    let out = run.json();
    assert_eq!(keys(&out), vec!["alpha", "beta", "plugin_x_gw"]);
    assert_eq!(row(&out, "alpha")["value"], json!(12000));
    assert_eq!(row(&out, "alpha")["calls"], json!(2));
    assert_eq!(row(&out, "alpha")["evidence"], json!("mcp:alpha"));
}

fn connected(servers: &[(&str, &str)]) -> String {
    let samples: Vec<(Vec<(&str, &str)>, &str)> = servers
        .iter()
        .map(|(name, up)| (vec![("mcp_server_name", *name)], *up))
        .collect();
    let borrowed: Vec<(&[(&str, &str)], &str)> =
        samples.iter().map(|(l, v)| (l.as_slice(), *v)).collect();
    vector(&borrowed)
}

#[test]
fn top_mcp_idle_is_connected_servers_minus_called_ones() {
    let fake = serve(with_own(vec![
        ("event_name=\"tool_result\"", mcp_results()),
        (
            "cc_obs_ledger_mcp_server_connected",
            connected(&[
                ("alpha", "1"),
                ("idle_one", "1"),
                ("idle_two", "1"),
                ("gone", "0"),
            ]),
        ),
    ]));
    let run = cli(&fake, &["top", "mcp", "--idle"]);
    assert_eq!(run.code, 0, "{}", run.err);
    assert_eq!(keys(&run.json()), vec!["idle_one", "idle_two"]);
}

#[test]
fn top_mcp_idle_without_the_connected_metric_names_the_gap() {
    let fake = serve(with_own(vec![
        ("event_name=\"tool_result\"", mcp_results()),
        ("cc_obs_ledger_mcp_server_connected", vector(&[])),
    ]));
    let out = cli(&fake, &["top", "mcp", "--idle"]).json();
    assert_eq!(out["value"], json!(null));
    assert!(
        out["unavailable"]
            .as_str()
            .unwrap()
            .contains("cc_obs_ledger_mcp_server_connected"),
        "{out}"
    );
}

#[test]
fn idle_belongs_to_mcp_only() {
    let out = cli(&serve(with_own(vec![])), &["top", "tool", "--idle"]).json();
    assert!(
        out["unavailable"].as_str().unwrap().contains("mcp"),
        "{out}"
    );
}

#[test]
fn mcp_question_ranks_servers_from_tool_result_prefixes() {
    let question = shipped_question(
        "mcp-idle-servers",
        vec![("event_name=\"tool_result\"", mcp_results())],
    );
    // alpha has 12000 of 13100 result tokens; plugin_x_gw's 100 is under the 2% floor
    assert_eq!(row_keys(&question), vec!["alpha", "beta"]);
}

fn skill_rules(listed: String) -> Vec<(&'static str, String)> {
    with_own(vec![
        ("cc_obs_ledger_skill_listed_tokens", listed),
        (
            "claude_code_token_usage_tokens_total",
            vector(&[(&[("skill_name", "used")], "9000")]),
        ),
    ])
}

#[test]
fn top_skill_unactivated_lists_installed_skills_without_activations_by_listing_cost() {
    let listed = vector(&[
        (&[("skill_name", "used")], "300"),
        (&[("skill_name", "big")], "500"),
        (&[("skill_name", "small")], "100"),
    ]);
    let run = cli(
        &serve(skill_rules(listed)),
        &["top", "skill", "--unactivated"],
    );
    assert_eq!(run.code, 0, "{}", run.err);
    let out = run.json();
    assert_eq!(keys(&out), vec!["big", "small"]);
    assert_eq!(row(&out, "big")["value"], json!(500));
    assert_eq!(row(&out, "big")["share"], json!(0.8333));
}

#[test]
fn top_skill_unactivated_without_the_listed_metric_names_the_gap() {
    let run = cli(
        &serve(skill_rules(vector(&[]))),
        &["top", "skill", "--unactivated"],
    );
    let out = run.json();
    assert_eq!(out["value"], json!(null));
    assert!(
        out["unavailable"]
            .as_str()
            .unwrap()
            .contains("cc_obs_ledger_skill_listed_tokens"),
        "{out}"
    );
}

#[test]
fn skills_question_digest_row_is_an_unactivated_skill() {
    let listed = vector(&[
        (&[("skill_name", "used")], "300"),
        (&[("skill_name", "big")], "500"),
        (&[("skill_name", "tiny")], "1"),
    ]);
    let question = shipped_question("skills-loaded-unused", skill_rules(listed));
    // tiny is 0.1% of the unactivated listing tokens, under the 2% floor
    assert_eq!(row_keys(&question), vec!["big"]);
}

fn recall_rules() -> Vec<(&'static str, String)> {
    with_own(vec![
        (
            "recall_requests_total",
            vector(&[
                (&[("service", "skills")], "100"),
                (&[("service", "docs")], "50"),
                (&[("service", "idle")], "0"),
            ]),
        ),
        (
            "recall_tokens_injected_total",
            vector(&[
                (&[("service", "skills")], "20000"),
                (&[("service", "docs")], "30000"),
                (&[("service", "idle")], "0"),
            ]),
        ),
    ])
}

#[test]
fn top_memory_by_tokens_per_request_divides_injected_tokens_by_requests() {
    let run = cli(
        &serve(recall_rules()),
        &[
            "top",
            "memory",
            "--by",
            "tokens-per-request",
            "--format",
            "detailed",
        ],
    );
    assert_eq!(run.code, 0, "{}", run.err);
    let out = run.json();
    assert_eq!(keys(&out), vec!["docs", "skills"]);
    assert_eq!(row(&out, "docs")["value"], json!(600));
    assert_eq!(row(&out, "skills")["value"], json!(200));
    assert_eq!(row(&out, "docs")["requests"], json!(50));
    assert!(row(&out, "docs").get("share").is_none());
}

#[test]
fn tokens_per_request_belongs_to_memory_only() {
    let out = cli(
        &serve(with_own(vec![])),
        &["top", "model", "--by", "tokens-per-request"],
    )
    .json();
    assert!(
        out["unavailable"].as_str().unwrap().contains("memory"),
        "{out}"
    );
}

#[test]
fn unactivated_belongs_to_skill_only() {
    let out = cli(&serve(with_own(vec![])), &["top", "mcp", "--unactivated"]).json();
    assert!(
        out["unavailable"].as_str().unwrap().contains("skill"),
        "{out}"
    );
}

#[test]
fn fixed_context_share_question_keeps_shares_at_or_above_five_percent() {
    let mut rules = vec![(
        "cc_obs_ledger_fixed_context_tokens",
        vector(&[
            (&[("component", "total")], "30000"),
            (&[("component", "instructions")], "28000"),
            (&[("component", "memory_index")], "2000"),
        ]),
    )];
    rules.push((
        "avg(avg_over_time(cc_obs_ledger_context_tokens",
        vector(&[(&[], "100000")]),
    ));
    let question = shipped_question("fixed-context-share", rules);
    assert_eq!(row_keys(&question), vec!["total", "instructions"]);
}

fn shipped_pack_text() -> String {
    std::fs::read_to_string(
        std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../../docs/token-efficiency/questions.yaml"),
    )
    .unwrap()
}

/// Runs the shipped pack through the baseline digest and returns one question.
fn shipped_question(id: &str, rules: Vec<(&'static str, String)>) -> Value {
    let dir = tempfile::tempdir().unwrap();
    let pack = common::write_pack(dir.path(), &shipped_pack_text());
    let mut all = rules;
    all.extend(common::digest_rules(common::fixture(
        "loki_tool_results.json",
    )));
    let fake = serve(all);
    let run = cli(
        &fake,
        &[
            "digest",
            "--baseline",
            "--pack",
            common::s(&pack),
            "--since",
            "7d",
            "--until",
            "2026-10-09",
        ],
    );
    assert_eq!(run.code, 0, "{}", run.err);
    run.json()["questions"]
        .as_array()
        .unwrap()
        .iter()
        .find(|q| q["id"] == id)
        .unwrap_or_else(|| panic!("no question {id} in the digest"))
        .clone()
}

fn row_keys(question: &Value) -> Vec<String> {
    question["rows"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| r["key"].as_str().unwrap().to_owned())
        .collect()
}

#[test]
fn agent_run_length_question_surfaces_the_long_subagent_and_drops_short_runs() {
    let question = shipped_question(
        "agent-run-length",
        vec![(
            "cc_obs_ledger_requests_total",
            vector(&[
                (&[("session_id", "s1"), ("agent", "subagent")], "559"),
                (&[("session_id", "s1"), ("agent", "main")], "40"),
            ]),
        )],
    );
    assert_eq!(row_keys(&question), vec!["s1/subagent"]);
}

#[test]
fn agent_context_growth_question_surfaces_the_runaway_context() {
    let labels = |agent: &'static str, turn: &'static str| {
        vec![
            ("session_id", "s1"),
            ("agent", agent),
            ("model", "m"),
            ("turn", turn),
        ]
    };
    let owned = [
        (labels("subagent", "1"), "53000"),
        (labels("subagent", "2"), "847000"),
        (labels("main", "1"), "90000"),
        (labels("main", "2"), "95000"),
    ];
    let borrowed: Vec<(&[(&str, &str)], &str)> =
        owned.iter().map(|(l, v)| (l.as_slice(), *v)).collect();
    let question = shipped_question(
        "agent-context-growth",
        vec![("cc_obs_ledger_context_tokens", vector(&borrowed))],
    );
    assert_eq!(row_keys(&question), vec!["s1/subagent"]);
}
