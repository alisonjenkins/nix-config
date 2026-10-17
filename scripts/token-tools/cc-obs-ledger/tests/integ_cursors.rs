#![allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]

//! `end` keeps cursors so a resume does not re-emit history and prunes idle ones;
//! the per-agent cursors the `subagent` hook writes live in the same directory and
//! must be pruned by the same rule.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, SystemTime};

const SESSION: &str = "sess-1";

const USER: &str = r#"{"type":"user","sessionId":"sess-1","cwd":"/work/proj","isSidechain":true,"message":{"role":"user","content":"task"}}"#;
const CALL: &str = r#"{"type":"assistant","sessionId":"sess-1","requestId":"r-1","cwd":"/work/proj","isSidechain":true,"message":{"id":"m-1","model":"m","content":[{"type":"tool_use","id":"t-1","name":"Read","input":{"n":1}}],"usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#;

fn run(root: &Path, subcommand: &str, input: &str) {
    let mut child = Command::new(env!("CARGO_BIN_EXE_cc-obs-ledger"))
        .args(["--check", subcommand])
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
        .write_all(input.as_bytes())
        .unwrap();
    assert!(child.wait().unwrap().success(), "{subcommand} failed");
}

fn agent_cursor(root: &Path, agent: &str) -> PathBuf {
    root.join("state/cc-obs-ledger/cursors")
        .join(format!("{SESSION}.agent-{agent}.json"))
}

fn age(path: &Path, days: u32) {
    let file = fs::File::options().write(true).open(path).unwrap();
    let idle = Duration::from_secs(60 * 60 * 24).saturating_mul(days);
    file.set_modified(SystemTime::now().checked_sub(idle).unwrap())
        .unwrap();
}

#[test]
fn idle_subagent_cursors_are_pruned_at_end_and_recent_ones_kept() {
    let root = tempfile::tempdir().unwrap();
    let root = root.path();
    let main = root.join("t.jsonl");
    fs::write(&main, format!("{USER}\n")).unwrap();
    let sub = root.join("sub.jsonl");
    fs::write(&sub, format!("{USER}\n{CALL}\n")).unwrap();
    for agent in ["stale", "recent"] {
        let hook = format!(
            r#"{{"session_id":"{SESSION}","transcript_path":"{}","agent_id":"{agent}","agent_transcript_path":"{}"}}"#,
            main.display(),
            sub.display()
        );
        run(root, "subagent", &hook);
    }
    age(&agent_cursor(root, "stale"), 90);
    age(&agent_cursor(root, "recent"), 2);

    let end = format!(
        r#"{{"session_id":"{SESSION}","transcript_path":"{}","cwd":"/work/proj"}}"#,
        main.display()
    );
    run(root, "end", &end);

    assert!(
        !agent_cursor(root, "stale").exists(),
        "idle agent cursor kept"
    );
    assert!(
        agent_cursor(root, "recent").exists(),
        "recent agent cursor pruned"
    );
}
