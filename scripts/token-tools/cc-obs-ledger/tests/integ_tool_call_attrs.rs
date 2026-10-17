#![allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]

//! A sub-agent's Bash call carries both the sub-agent's `agent_id` and the call's
//! `command_shape` on its `cc_obs_ledger.tool_call` record.

use std::fs;
use std::io::Write;
use std::process::{Command, Stdio};

use serde_json::Value;

const USER: &str = r#"{"type":"user","sessionId":"sess-1","cwd":"/work/proj","isSidechain":true,"message":{"role":"user","content":"task"}}"#;
const BASH: &str = r#"{"type":"assistant","sessionId":"sess-1","requestId":"r-1","cwd":"/work/proj","isSidechain":true,"message":{"id":"m-1","model":"m","content":[{"type":"tool_use","id":"t-1","name":"Bash","input":{"command":"cargo test"}}],"usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#;

fn attr(record: &Value, key: &str) -> Option<String> {
    record["attributes"]
        .as_array()?
        .iter()
        .find(|a| a["key"] == key)
        .and_then(|a| a["value"]["stringValue"].as_str())
        .map(str::to_owned)
}

#[test]
fn a_subagent_bash_call_carries_agent_id_and_command_shape() {
    let root = tempfile::tempdir().unwrap();
    let root = root.path();
    let sub = root.join("sub.jsonl");
    fs::write(&sub, format!("{USER}\n{BASH}\n")).unwrap();
    let hook = format!(
        r#"{{"session_id":"sess-1","transcript_path":"{}","agent_id":"a1","agent_transcript_path":"{}"}}"#,
        root.join("t.jsonl").display(),
        sub.display()
    );
    let mut child = Command::new(env!("CARGO_BIN_EXE_cc-obs-ledger"))
        .args(["--check", "subagent"])
        .env("HOME", root)
        .env("XDG_STATE_HOME", root.join("state"))
        .env("XDG_CONFIG_HOME", root.join("config"))
        .env_remove("OTEL_RESOURCE_ATTRIBUTES")
        .stdin(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(hook.as_bytes())
        .unwrap();
    assert!(child.wait().unwrap().success());

    let mut calls = Vec::new();
    for entry in fs::read_dir(root.join("state/cc-obs-ledger/spool")).unwrap() {
        let path = entry.unwrap().path();
        if path.extension().is_none_or(|e| e != "json") {
            continue;
        }
        let body: Value = serde_json::from_str(&fs::read_to_string(path).unwrap()).unwrap();
        if let Some(records) = body.pointer("/resourceLogs/0/scopeLogs/0/logRecords") {
            calls.extend(records.as_array().unwrap().iter().cloned());
        }
    }
    assert_eq!(calls.len(), 1, "{calls:?}");
    assert_eq!(attr(&calls[0], "agent_id").as_deref(), Some("a1"));
    assert_eq!(
        attr(&calls[0], "command_shape").as_deref(),
        Some("cargo test")
    );
}
