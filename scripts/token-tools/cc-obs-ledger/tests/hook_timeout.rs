#![allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]

//! The Stop hook has a 5 s timeout in Claude Code. Whatever the collector does,
//! `turn` must return well inside it, leave the payloads spooled for a later
//! `ship`, advance the cursor, and the sender must log every run that sent
//! nothing, so a silent gap can be told apart from a quiet session.

use std::fs;
use std::io::Write;
use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

mod common;

use common::read_request;

const SESSION: &str = "sess-1";

/// Well under the 5 s hook timeout, well over what `turn` needs.
const HOOK_BUDGET: Duration = Duration::from_millis(2500);

const USER: &str = r#"{"type":"user","sessionId":"s","promptId":"p","cwd":"/w/p","message":{"role":"user","content":"PROMPT"}}"#;
const TOOL: &str = r#"{"type":"assistant","sessionId":"s","requestId":"r-1","cwd":"/w/p","isSidechain":false,"message":{"id":"m-1","model":"m","content":[{"type":"tool_use","id":"t-1","name":"Read","input":{"n":1}}],"usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#;

struct Env {
    root: tempfile::TempDir,
}

impl Env {
    fn new(collector_url: &str) -> Self {
        let env = Self {
            root: tempfile::tempdir().unwrap(),
        };
        let config = env.root.path().join("endpoints.json");
        fs::write(
            &config,
            format!(r#"{{"host":"h","urls":{{"otlpHttp":"{collector_url}"}}}}"#),
        )
        .unwrap();
        fs::write(env.transcript(), format!("{USER}\n{TOOL}\n")).unwrap();
        env
    }

    fn state(&self) -> PathBuf {
        self.root.path().join("state/cc-obs-ledger")
    }

    fn transcript(&self) -> PathBuf {
        self.root.path().join("t.jsonl")
    }

    fn command(&self, subcommand: &str) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_cc-obs-ledger"));
        command
            .args(["--check", subcommand])
            .env("HOME", self.root.path())
            .env("XDG_STATE_HOME", self.root.path().join("state"))
            .env("CC_OBS_ENDPOINTS", self.root.path().join("endpoints.json"))
            .env_remove("OTEL_RESOURCE_ATTRIBUTES");
        command
    }

    /// Runs `turn` with the hook JSON on stdin and returns how long it took.
    fn turn(&self) -> Duration {
        let started = Instant::now();
        let mut child = self.command("turn").stdin(Stdio::piped()).spawn().unwrap();
        let input = format!(
            r#"{{"session_id":"{SESSION}","transcript_path":"{}","cwd":"/w/p"}}"#,
            self.transcript().display()
        );
        child
            .stdin
            .take()
            .unwrap()
            .write_all(input.as_bytes())
            .unwrap();
        assert!(child.wait().unwrap().success(), "turn failed");
        started.elapsed()
    }

    fn spooled(&self) -> usize {
        fs::read_dir(self.state().join("spool"))
            .map(|entries| {
                entries
                    .filter(|e| {
                        e.as_ref()
                            .unwrap()
                            .file_name()
                            .to_string_lossy()
                            .ends_with(".json")
                    })
                    .count()
            })
            .unwrap_or(0)
    }

    fn log(&self) -> String {
        fs::read_to_string(self.state().join("ledger.log")).unwrap_or_default()
    }

    /// The detached sender has to finish before the temp dir goes away.
    fn wait_for_log(&self, needle: &str) -> String {
        let deadline = Instant::now().checked_add(Duration::from_secs(15)).unwrap();
        loop {
            let log = self.log();
            if log.contains(needle) {
                return log;
            }
            assert!(
                Instant::now() < deadline,
                "no `{needle}` in ledger.log:\n{log}"
            );
            thread::sleep(Duration::from_millis(50));
        }
    }

    fn cursor_offset(&self) -> u64 {
        let text = fs::read_to_string(self.state().join("cursors").join(format!("{SESSION}.json")))
            .unwrap();
        serde_json::from_str::<serde_json::Value>(&text).unwrap()["offset"]
            .as_u64()
            .unwrap()
    }
}

/// Accepts connections and never answers, like a collector that is starting up.
fn hanging_server() -> String {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    thread::spawn(move || {
        let mut held = Vec::new();
        for stream in listener.incoming().flatten() {
            held.push(stream);
        }
    });
    url
}

/// A port nothing listens on.
fn refusing_url() -> String {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    format!("http://{}", listener.local_addr().unwrap())
}

/// Answers every request with `status_line`.
fn answering_server(status_line: &'static str) -> String {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    thread::spawn(move || {
        for mut stream in listener.incoming().flatten() {
            read_request(&mut stream);
            let _ = stream.write_all(
                format!(
                    "HTTP/1.1 {status_line}\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{{}}"
                )
                .as_bytes(),
            );
        }
    });
    url
}

fn assert_hook_contract(env: &Env, expected_log: &str) {
    let elapsed = env.turn();
    assert!(
        elapsed < HOOK_BUDGET,
        "turn took {elapsed:?}, the hook timeout is 5 s"
    );
    assert_eq!(
        env.cursor_offset(),
        fs::metadata(env.transcript()).unwrap().len()
    );
    env.wait_for_log(expected_log);
    assert!(env.spooled() > 0, "payloads must stay spooled");
}

#[test]
fn turn_returns_inside_the_hook_timeout_when_the_collector_hangs() {
    let env = Env::new(&hanging_server());
    assert_hook_contract(&env, "ship: sent=0");
}

#[test]
fn turn_returns_inside_the_hook_timeout_when_the_collector_refuses() {
    let env = Env::new(&refusing_url());
    assert_hook_contract(&env, "ship: sent=0");
}

#[test]
fn turn_returns_inside_the_hook_timeout_when_the_collector_answers_503() {
    let env = Env::new(&answering_server("503 Service Unavailable"));
    assert_hook_contract(&env, "ship: sent=0");
}

#[test]
fn spooled_payloads_ship_on_the_next_run_once_the_collector_is_back() {
    let env = Env::new(&hanging_server());
    assert_hook_contract(&env, "ship: sent=0");
    let spooled = env.spooled();

    let good = answering_server("200 OK");
    fs::write(
        env.root.path().join("endpoints.json"),
        format!(r#"{{"host":"h","urls":{{"otlpHttp":"{good}"}}}}"#),
    )
    .unwrap();
    let status = env.command("ship").stdin(Stdio::null()).status().unwrap();
    assert!(status.success());
    assert_eq!(env.spooled(), 0, "{spooled} payloads were not shipped");
    assert!(
        env.log().contains(&format!("ship: sent={spooled}")),
        "{}",
        env.log()
    );
}

fn hold_lock(dir: &Path) -> fs::File {
    fs::create_dir_all(dir).unwrap();
    let lock = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(dir.join(".lock"))
        .unwrap();
    lock.try_lock().unwrap();
    lock
}

#[test]
fn a_ship_that_finds_the_spool_lock_held_logs_a_line() {
    let env = Env::new(&answering_server("200 OK"));
    let _lock = hold_lock(&env.state().join("spool"));
    let status = env.command("ship").stdin(Stdio::null()).status().unwrap();
    assert!(status.success());
    let log = env.log();
    assert!(
        log.contains("ship: skipped") && log.contains(".lock"),
        "{log}"
    );
}

#[test]
fn a_ship_with_no_endpoints_file_logs_why() {
    let env = Env::new("http://127.0.0.1:1");
    fs::remove_file(env.root.path().join("endpoints.json")).unwrap();
    let status = env.command("ship").stdin(Stdio::null()).status().unwrap();
    assert!(!status.success());
    assert!(env.log().contains("ship:"), "{}", env.log());
}
