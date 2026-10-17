#![allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]

//! A session that is ended and resumed (same session_id, same growing transcript)
//! must emit only the records after the point where it ended.

use std::collections::BTreeSet;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, SystemTime};

use serde_json::Value;

const SESSION: &str = "sess-1";
const REQUESTS: &str = "cc_obs_ledger_requests_total";

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

    fn transcript(&self) -> PathBuf {
        self.root.path().join("t.jsonl")
    }

    fn write(&self, lines: &[String]) {
        let mut text = lines.join("\n");
        text.push('\n');
        fs::write(self.transcript(), text).unwrap();
    }

    fn hook(&self, subcommand: &str, session: &str) {
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
            r#"{{"session_id":"{session}","transcript_path":"{}","cwd":"/work/proj"}}"#,
            self.transcript().display()
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
        let dir = self.state().join("spool");
        match fs::read_dir(dir) {
            Ok(entries) => entries
                .map(|e| e.unwrap().path())
                .filter(|p| p.extension().is_some_and(|e| e == "json"))
                .collect(),
            Err(_) => BTreeSet::new(),
        }
    }

    /// Run `f`, and return the spool files it added.
    fn added_by(&self, f: impl FnOnce()) -> Vec<Value> {
        let before = self.spool_files();
        f();
        self.spool_files()
            .difference(&before)
            .map(|p| serde_json::from_str(&fs::read_to_string(p).unwrap()).unwrap())
            .collect()
    }
}

fn tool_seqs(payloads: &[Value]) -> Vec<String> {
    let mut seqs = Vec::new();
    for body in payloads {
        let Some(records) = body.pointer("/resourceLogs/0/scopeLogs/0/logRecords") else {
            continue;
        };
        for record in records.as_array().unwrap() {
            for attr in record["attributes"].as_array().unwrap() {
                if attr["key"] == "seq" {
                    seqs.push(attr["value"]["intValue"].as_str().unwrap().to_owned());
                }
            }
        }
    }
    seqs.sort();
    seqs
}

fn requests_total(payloads: &[Value]) -> u64 {
    let mut total: u64 = 0;
    for body in payloads {
        let Some(metrics) = body.pointer("/resourceMetrics/0/scopeMetrics/0/metrics") else {
            continue;
        };
        for metric in metrics.as_array().unwrap() {
            if metric["name"] == REQUESTS {
                for point in metric["sum"]["dataPoints"].as_array().unwrap() {
                    let count = point["asInt"].as_str().unwrap().parse::<u64>().unwrap();
                    total = total.saturating_add(count);
                }
            }
        }
    }
    total
}

const USER: &str = r#"{"type":"user","sessionId":"sess-1","promptId":"p","cwd":"/work/proj","isSidechain":false,"message":{"role":"user","content":"hello"}}"#;

fn tool(n: u32) -> String {
    format!(
        r#"{{"type":"assistant","sessionId":"sess-1","requestId":"r-{n}","cwd":"/work/proj","isSidechain":false,"message":{{"id":"m-{n}","model":"m","content":[{{"type":"tool_use","id":"t-{n}","name":"Read","input":{{"n":{n}}}}}],"usage":{{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}}}}"#
    )
}

fn cursor_file(env: &Env, session: &str) -> PathBuf {
    env.state().join("cursors").join(format!("{session}.json"))
}

#[test]
fn a_resumed_session_emits_only_the_records_after_the_end() {
    let env = Env::new();
    let mut all = vec![USER.to_owned(), tool(1), tool(2)];
    env.write(&all);
    let first = env.added_by(|| env.hook("turn", SESSION));
    let ended = env.added_by(|| env.hook("end", SESSION));
    all.extend([tool(3), tool(4)]);
    env.write(&all);
    let resumed = env.added_by(|| env.hook("turn", SESSION));

    assert_eq!(tool_seqs(&first), ["0", "1"]);
    assert_eq!(tool_seqs(&ended), Vec::<String>::new());
    assert_eq!(tool_seqs(&resumed), ["2", "3"], "resume re-emitted history");
}

#[test]
fn the_requests_total_after_a_resume_continues_from_the_stored_total() {
    let env = Env::new();
    let mut all = vec![USER.to_owned(), tool(1), tool(2), tool(3)];
    env.write(&all);
    let first = env.added_by(|| env.hook("turn", SESSION));
    let ended = env.added_by(|| env.hook("end", SESSION));
    all.extend([tool(4), tool(5)]);
    env.write(&all);
    let resumed = env.added_by(|| env.hook("turn", SESSION));

    assert_eq!(requests_total(&first), 3);
    assert_eq!(requests_total(&ended), 0);
    assert_eq!(requests_total(&resumed), 5, "resume restarted the total");
}

#[test]
fn records_written_between_the_last_stop_and_the_end_are_emitted_once() {
    let env = Env::new();
    let mut all = vec![USER.to_owned(), tool(1)];
    env.write(&all);
    env.hook("turn", SESSION);
    all.push(tool(2));
    env.write(&all);
    let ended = env.added_by(|| env.hook("end", SESSION));
    all.push(tool(3));
    env.write(&all);
    let resumed = env.added_by(|| env.hook("turn", SESSION));

    assert_eq!(tool_seqs(&ended), ["1"]);
    assert_eq!(tool_seqs(&resumed), ["2"]);
}

#[test]
fn a_transcript_replaced_by_a_shorter_file_starts_over() {
    let env = Env::new();
    env.write(&[USER.to_owned(), tool(1), tool(2), tool(3)]);
    env.hook("turn", SESSION);
    env.hook("end", SESSION);
    env.write(&[USER.to_owned(), tool(9)]);
    let after = env.added_by(|| env.hook("turn", SESSION));
    assert_eq!(tool_seqs(&after), ["0"]);
    assert_eq!(requests_total(&after), 1);
}

#[test]
fn cursors_of_sessions_untouched_for_a_long_time_are_pruned_at_end() {
    let env = Env::new();
    env.write(&[USER.to_owned(), tool(1)]);
    env.hook("turn", "stale");
    env.hook("turn", "recent");
    let age = |path: &Path, days: u32| {
        let file = fs::File::options().write(true).open(path).unwrap();
        let idle = Duration::from_secs(60 * 60 * 24).saturating_mul(days);
        file.set_modified(SystemTime::now().checked_sub(idle).unwrap())
            .unwrap();
    };
    age(&cursor_file(&env, "stale"), 90);
    age(&cursor_file(&env, "recent"), 2);

    env.hook("end", SESSION);

    assert!(!cursor_file(&env, "stale").exists(), "stale cursor kept");
    assert!(cursor_file(&env, "recent").exists(), "recent cursor pruned");
    assert!(cursor_file(&env, SESSION).exists(), "ended cursor deleted");
}
