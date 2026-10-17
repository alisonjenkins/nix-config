#![allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]

//! The `cc_obs_ledger.session` record is cumulative per session. Each end numbers
//! itself and carries the delta since the previous end, so a consumer can sum the
//! deltas or take the last record without double counting a resumed session.

use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};

use serde_json::Value;

const SESSION: &str = "sess-1";

struct Env {
    root: tempfile::TempDir,
}

impl Env {
    fn new() -> Self {
        Self {
            root: tempfile::tempdir().unwrap(),
        }
    }

    fn state(&self) -> PathBuf {
        self.root.path().join("state/cc-obs-ledger")
    }

    fn write(&self, lines: &[String]) {
        let mut text = lines.join("\n");
        text.push('\n');
        fs::write(self.root.path().join("t.jsonl"), text).unwrap();
    }

    fn hook(&self, subcommand: &str) {
        let mut child = Command::new(env!("CARGO_BIN_EXE_cc-obs-ledger"))
            .args(["--check", subcommand])
            .env("HOME", self.root.path())
            .env("XDG_STATE_HOME", self.root.path().join("state"))
            .env("XDG_CONFIG_HOME", self.root.path().join("config"))
            .env_remove("OTEL_RESOURCE_ATTRIBUTES")
            .stdin(Stdio::piped())
            .spawn()
            .unwrap();
        let input = format!(
            r#"{{"session_id":"{SESSION}","transcript_path":"{}","cwd":"/work/proj"}}"#,
            self.root.path().join("t.jsonl").display()
        );
        child
            .stdin
            .take()
            .unwrap()
            .write_all(input.as_bytes())
            .unwrap();
        assert!(child.wait().unwrap().success(), "{subcommand} failed");
    }

    fn spool_files(&self) -> BTreeSet<PathBuf> {
        match fs::read_dir(self.state().join("spool")) {
            Ok(entries) => entries
                .map(|e| e.unwrap().path())
                .filter(|p| p.extension().is_some_and(|e| e == "json"))
                .collect(),
            Err(_) => BTreeSet::new(),
        }
    }

    /// Ends the session and returns the attributes of the session records it spooled.
    fn end(&self) -> Vec<BTreeMap<String, String>> {
        let before = self.spool_files();
        self.hook("end");
        let mut records = Vec::new();
        for path in self.spool_files().difference(&before) {
            let body: Value = serde_json::from_str(&fs::read_to_string(path).unwrap()).unwrap();
            let Some(logs) = body.pointer("/resourceLogs/0/scopeLogs/0/logRecords") else {
                continue;
            };
            for record in logs.as_array().unwrap() {
                let attrs: BTreeMap<String, String> = record["attributes"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|a| {
                        let value = &a["value"];
                        let text = value["intValue"]
                            .as_str()
                            .map(str::to_owned)
                            .or_else(|| value["stringValue"].as_str().map(str::to_owned))
                            .or_else(|| value["boolValue"].as_bool().map(|b| b.to_string()))
                            .unwrap();
                        (a["key"].as_str().unwrap().to_owned(), text)
                    })
                    .collect();
                if attrs.get("event.name").map(String::as_str) == Some("cc_obs_ledger.session") {
                    records.push(attrs);
                }
            }
        }
        records
    }
}

const USER: &str = r#"{"type":"user","sessionId":"sess-1","promptId":"p","cwd":"/work/proj","isSidechain":false,"message":{"role":"user","content":"hello"}}"#;

fn tool(n: u32) -> String {
    format!(
        r#"{{"type":"assistant","sessionId":"sess-1","requestId":"r-{n}","cwd":"/work/proj","isSidechain":false,"message":{{"id":"m-{n}","model":"m","content":[{{"type":"tool_use","id":"t-{n}","name":"Read","input":{{"n":{n}}}}}],"usage":{{"input_tokens":2,"output_tokens":3,"cache_read_input_tokens":5,"cache_creation_input_tokens":7}}}}}}"#
    )
}

fn only(mut records: Vec<BTreeMap<String, String>>) -> BTreeMap<String, String> {
    assert_eq!(records.len(), 1, "expected one session record");
    records.remove(0)
}

fn get(record: &BTreeMap<String, String>, key: &str) -> String {
    record.get(key).expect(key).clone()
}

#[test]
fn the_first_end_is_end_one_and_its_delta_is_the_cumulative_total() {
    let env = Env::new();
    env.write(&[USER.to_owned(), tool(1), tool(2)]);
    let record = only(env.end());

    assert_eq!(get(&record, "end_index"), "1");
    assert_eq!(get(&record, "cumulative"), "true");
    assert_eq!(get(&record, "requests"), "2");
    assert_eq!(get(&record, "requests_delta"), "2");
    assert_eq!(get(&record, "tool_calls_delta"), "2");
    assert_eq!(get(&record, "input_tokens_delta"), "4");
    assert_eq!(get(&record, "output_tokens_delta"), "6");
    assert_eq!(get(&record, "cache_read_tokens_delta"), "10");
    assert_eq!(get(&record, "cache_creation_tokens_delta"), "14");
}

#[test]
fn a_second_end_stays_cumulative_and_its_delta_is_only_the_new_part() {
    let env = Env::new();
    let mut all = vec![USER.to_owned(), tool(1), tool(2)];
    env.write(&all);
    env.end();
    all.push(tool(3));
    env.write(&all);
    let record = only(env.end());

    assert_eq!(get(&record, "end_index"), "2");
    assert_eq!(get(&record, "requests"), "3");
    assert_eq!(get(&record, "tool_calls"), "3");
    assert_eq!(get(&record, "input_tokens"), "6");
    assert_eq!(get(&record, "requests_delta"), "1");
    assert_eq!(get(&record, "tool_calls_delta"), "1");
    assert_eq!(get(&record, "input_tokens_delta"), "2");
    assert_eq!(get(&record, "output_tokens_delta"), "3");
    assert_eq!(get(&record, "cache_read_tokens_delta"), "5");
    assert_eq!(get(&record, "cache_creation_tokens_delta"), "7");
}

#[test]
fn an_end_with_no_new_activity_emits_no_record_and_keeps_the_index() {
    let env = Env::new();
    let mut all = vec![USER.to_owned(), tool(1)];
    env.write(&all);
    env.end();
    assert!(env.end().is_empty(), "idle end emitted a record");
    all.push(tool(2));
    env.write(&all);
    let record = only(env.end());

    assert_eq!(get(&record, "end_index"), "2");
    assert_eq!(get(&record, "requests_delta"), "1");
}
