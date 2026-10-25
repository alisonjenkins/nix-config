#![allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]

//! The `subagent` hook (SubagentStop): sub-agent transcripts at
//! `<session dir>/subagents/agent-<id>.jsonl` are ingested with the main parser,
//! once, and tagged with the agent id.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use serde_json::Value;

const SESSION: &str = "sess-1";
const AGENT: &str = "a1b2c3";

fn assistant(n: u32, tool: bool) -> String {
    let content = if tool {
        format!(r#"[{{"type":"tool_use","id":"t-{n}","name":"Read","input":{{"n":{n}}}}}]"#)
    } else {
        r#"[{"type":"text","text":"done"}]"#.to_owned()
    };
    format!(
        r#"{{"type":"assistant","sessionId":"{SESSION}","agentId":"{AGENT}","requestId":"r-{n}","cwd":"/work/proj","isSidechain":true,"timestamp":"2026-10-17T10:00:0{n}Z","message":{{"id":"m-{n}","model":"m1","content":{content},"usage":{{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":1,"cache_creation_input_tokens":1}}}}}}"#
    )
}

fn user() -> String {
    format!(
        r#"{{"type":"user","sessionId":"{SESSION}","agentId":"{AGENT}","isSidechain":true,"message":{{"role":"user","content":"do it"}}}}"#
    )
}

/// 3 requests, 2 tool calls.
fn first_part() -> Vec<String> {
    vec![
        user(),
        assistant(1, true),
        assistant(2, true),
        assistant(3, false),
    ]
}

struct Env {
    home: tempfile::TempDir,
    state: tempfile::TempDir,
}

impl Env {
    fn new() -> Self {
        Self {
            home: tempfile::tempdir().unwrap(),
            state: tempfile::tempdir().unwrap(),
        }
    }

    fn main_transcript(&self) -> PathBuf {
        self.home.path().join(format!("proj/{SESSION}.jsonl"))
    }

    fn agent_file(&self, agent: &str) -> PathBuf {
        self.home
            .path()
            .join(format!("proj/{SESSION}/subagents/agent-{agent}.jsonl"))
    }

    fn write_lines(&self, path: &Path, lines: &[String]) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, format!("{}\n", lines.join("\n"))).unwrap();
    }

    fn run(&self, subcommand: &str, hook: &str) {
        let out = self.output(subcommand, hook);
        assert!(
            out.status.success(),
            "{subcommand} failed; log: {:?}",
            fs::read_to_string(self.state.path().join("cc-obs-ledger/ledger.log"))
        );
        assert!(out.stdout.is_empty(), "stdout must stay empty");
    }

    fn output(&self, subcommand: &str, hook: &str) -> std::process::Output {
        let mut child = Command::new(env!("CARGO_BIN_EXE_cc-obs-ledger"))
            .arg("--check")
            .arg(subcommand)
            .env("HOME", self.home.path())
            .env("XDG_STATE_HOME", self.state.path())
            .env("CC_OBS_ENDPOINTS", self.home.path().join("none.json"))
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        child
            .stdin
            .take()
            .unwrap()
            .write_all(hook.as_bytes())
            .unwrap();
        child.wait_with_output().unwrap()
    }

    /// SubagentStop with the transcript path derived from the main transcript's location.
    fn stop(&self, agent: &str) {
        let hook = format!(
            r#"{{"hook_event_name":"SubagentStop","session_id":"{SESSION}","transcript_path":"{}","agent_id":"{agent}","agent_type":"general-purpose"}}"#,
            self.main_transcript().display()
        );
        self.run("subagent", &hook);
    }

    fn spooled(&self, suffix: &str) -> Vec<Value> {
        let dir = self.state.path().join("cc-obs-ledger/spool");
        let Ok(entries) = fs::read_dir(dir) else {
            return Vec::new();
        };
        entries
            .map(|e| e.unwrap().path())
            .filter(|p| p.to_string_lossy().ends_with(suffix))
            .map(|p| serde_json::from_str(&fs::read_to_string(p).unwrap()).unwrap())
            .collect()
    }

    fn tool_call_records(&self) -> Vec<Value> {
        self.spooled(".logs.json")
            .iter()
            .flat_map(|body| {
                body.pointer("/resourceLogs/0/scopeLogs/0/logRecords")
                    .and_then(Value::as_array)
                    .unwrap()
                    .clone()
            })
            .filter(|record| {
                attr(record, "event.name").as_deref() == Some("cc_obs_ledger.tool_call")
            })
            .collect()
    }

    fn metrics(&self) -> Vec<Value> {
        self.spooled(".metrics.json")
            .iter()
            .flat_map(|body| {
                body.pointer("/resourceMetrics/0/scopeMetrics/0/metrics")
                    .and_then(Value::as_array)
                    .unwrap()
                    .clone()
            })
            .collect()
    }

    fn requests_total(&self) -> u64 {
        self.metrics()
            .iter()
            .filter(|m| m["name"] == "cc_obs_ledger_requests_total")
            .flat_map(|m| m["sum"]["dataPoints"].as_array().unwrap().clone())
            .map(|p| p["asInt"].as_str().unwrap().parse::<u64>().unwrap())
            .sum()
    }
}

fn attr(record: &Value, key: &str) -> Option<String> {
    let found = record["attributes"]
        .as_array()?
        .iter()
        .find(|a| a["key"] == key)?;
    found["value"]["stringValue"]
        .as_str()
        .or_else(|| found["value"]["intValue"].as_str())
        .map(str::to_owned)
}

#[test]
fn a_subagent_transcript_yields_tagged_tool_calls_and_requests() {
    let env = Env::new();
    env.write_lines(&env.agent_file(AGENT), &first_part());
    env.stop(AGENT);

    let calls = env.tool_call_records();
    assert_eq!(calls.len(), 2, "{calls:?}");
    for call in &calls {
        assert_eq!(attr(call, "agent").as_deref(), Some("subagent"));
        assert_eq!(attr(call, "agent_id").as_deref(), Some(AGENT));
        assert_eq!(attr(call, "session.id").as_deref(), Some(SESSION));
    }
    assert_eq!(env.requests_total(), 3);
    let gauges: Vec<Value> = env
        .metrics()
        .into_iter()
        .filter(|m| m["name"] == "cc_obs_ledger_context_tokens")
        .collect();
    assert_eq!(gauges.len(), 3);
    for gauge in gauges {
        let point = &gauge["gauge"]["dataPoints"][0];
        assert_eq!(attr(point, "agent").as_deref(), Some("subagent"));
        assert_eq!(attr(point, "agent_id").as_deref(), Some(AGENT));
    }
}

#[test]
fn running_the_hook_twice_emits_nothing_the_second_time() {
    let env = Env::new();
    env.write_lines(&env.agent_file(AGENT), &first_part());
    env.stop(AGENT);
    env.stop(AGENT);
    assert_eq!(env.tool_call_records().len(), 2);
    assert_eq!(env.requests_total(), 3);
}

#[test]
fn a_file_that_grew_between_stops_emits_only_the_new_records() {
    let env = Env::new();
    env.write_lines(&env.agent_file(AGENT), &first_part());
    env.stop(AGENT);
    let mut grown = first_part();
    grown.push(assistant(4, true));
    env.write_lines(&env.agent_file(AGENT), &grown);
    env.stop(AGENT);

    let calls = env.tool_call_records();
    assert_eq!(calls.len(), 3, "{calls:?}");
    let mut seqs: Vec<String> = calls.iter().map(|c| attr(c, "seq").unwrap()).collect();
    seqs.sort();
    assert_eq!(seqs, ["0", "1", "2"]);
    assert_eq!(env.requests_total(), 4);
}

#[test]
fn agents_of_one_session_keep_separate_cursors() {
    let env = Env::new();
    env.write_lines(&env.agent_file(AGENT), &first_part());
    env.write_lines(&env.agent_file("other"), &first_part());
    env.stop(AGENT);
    env.stop("other");
    assert_eq!(env.tool_call_records().len(), 4);
    assert_eq!(env.requests_total(), 6);
}

#[test]
fn sub_agents_each_number_seq_from_zero_so_agent_id_makes_a_call_unique() {
    let env = Env::new();
    env.write_lines(&env.agent_file(AGENT), &first_part());
    env.write_lines(&env.agent_file("other"), &first_part());
    env.stop(AGENT);
    env.stop("other");

    let mut keys: Vec<(String, String)> = env
        .tool_call_records()
        .iter()
        .map(|c| (attr(c, "agent_id").unwrap(), attr(c, "seq").unwrap()))
        .collect();
    keys.sort();
    assert_eq!(
        keys,
        [
            (AGENT.to_owned(), "0".to_owned()),
            (AGENT.to_owned(), "1".to_owned()),
            ("other".to_owned(), "0".to_owned()),
            ("other".to_owned(), "1".to_owned()),
        ],
        "(session, agent kind, seq) alone repeats across sub-agents; readers must key on agent_id too"
    );
}

#[test]
fn an_explicit_agent_transcript_path_wins_over_the_derived_one() {
    let env = Env::new();
    let elsewhere = env.home.path().join("elsewhere.jsonl");
    env.write_lines(&elsewhere, &first_part());
    let hook = format!(
        r#"{{"session_id":"{SESSION}","transcript_path":"{}","agent_id":"{AGENT}","agent_transcript_path":"{}"}}"#,
        env.main_transcript().display(),
        elsewhere.display()
    );
    env.run("subagent", &hook);
    assert_eq!(env.tool_call_records().len(), 2);
}

#[test]
fn an_empty_transcript_path_and_no_main_transcript_is_still_a_missing_field_error() {
    let env = Env::new();
    let hook = format!(
        r#"{{"session_id":"{SESSION}","transcript_path":"","agent_id":"{AGENT}","agent_transcript_path":""}}"#
    );
    let out = env.output("subagent", &hook);
    assert!(!out.status.success(), "must fail under --check");
    let log = fs::read_to_string(env.state.path().join("cc-obs-ledger/ledger.log")).unwrap();
    assert!(log.contains("agent_transcript_path"), "{log}");
    assert!(env.metrics().is_empty(), "no counter for a malformed hook");
}

#[test]
fn an_agent_id_cannot_walk_out_of_the_subagents_directory() {
    let env = Env::new();
    // `agent-x/../../evil.jsonl` from the subagents directory is `<session dir>/evil.jsonl`.
    fs::create_dir_all(
        env.main_transcript()
            .with_extension("")
            .join("subagents/agent-x"),
    )
    .unwrap();
    let outside = env.main_transcript().with_extension("").join("evil.jsonl");
    env.write_lines(&outside, &first_part());
    env.stop("x/../../evil");
    assert!(env.tool_call_records().is_empty());
}

#[test]
fn the_session_end_pass_does_not_re_read_ingested_subagent_files() {
    let env = Env::new();
    let main_lines = vec![
        r#"{"type":"user","sessionId":"sess-1","cwd":"/work/proj","isSidechain":false,"message":{"role":"user","content":"hi"}}"#.to_owned(),
        r#"{"type":"assistant","sessionId":"sess-1","requestId":"main-1","cwd":"/work/proj","isSidechain":false,"message":{"id":"mm","model":"m1","content":[{"type":"tool_use","id":"tm","name":"Task","input":{}}],"usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#.to_owned(),
    ];
    env.write_lines(&env.main_transcript(), &main_lines);
    env.write_lines(&env.agent_file(AGENT), &first_part());
    env.stop(AGENT);
    let before = env.tool_call_records().len();

    let hook = format!(
        r#"{{"session_id":"{SESSION}","transcript_path":"{}"}}"#,
        env.main_transcript().display()
    );
    env.run("turn", &hook);
    env.run("end", &hook);
    env.stop(AGENT);

    let calls = env.tool_call_records();
    let sub = calls
        .iter()
        .filter(|c| attr(c, "agent").as_deref() == Some("subagent"))
        .count();
    assert_eq!(sub, 2, "sub-agent calls must not be emitted again");
    assert_eq!(calls.len(), before + 1, "only the one main call is new");
    assert!(calls
        .iter()
        .filter(|c| attr(c, "agent").as_deref() == Some("main"))
        .all(|c| attr(c, "agent_id").is_none()));
}
