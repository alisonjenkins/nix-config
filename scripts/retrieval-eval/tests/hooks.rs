//! Drives the real `memory-recall` and `skill-recall` binaries against a fake
//! embeddings server: a text containing "alpha" embeds to [1, 0], anything else
//! to [0, 1], so which document matches a prompt is checkable by hand.
#![allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]
use std::fs;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::path::Path;
use std::process::{Command, Output, Stdio};
use std::thread;

use retrieval_eval::recall_log::{parse_log, Entry};

const MEMORY_BIN: &str = env!("CARGO_BIN_EXE_memory-recall");
const SKILL_BIN: &str = env!("CARGO_BIN_EXE_skill-recall");
/// Nothing listens here, so every request is refused at once.
const DEAD_URL: &str = "http://127.0.0.1:1";

fn serve() -> String {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    thread::spawn(move || serve_on(listener));
    base
}

fn serve_on(listener: TcpListener) {
    {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { continue };
            let mut request = Vec::new();
            let mut buf = vec![0_u8; 65536];
            loop {
                let n = stream.read(&mut buf).unwrap_or(0);
                request.extend_from_slice(&buf[..n]);
                let text = String::from_utf8_lossy(&request).into_owned();
                let Some((head, body)) = text.split_once("\r\n\r\n") else {
                    if n == 0 {
                        break;
                    }
                    continue;
                };
                let len: usize = head
                    .lines()
                    .find_map(|l| {
                        l.to_lowercase()
                            .strip_prefix("content-length: ")
                            .map(str::to_owned)
                    })
                    .and_then(|v| v.trim().parse().ok())
                    .unwrap_or(0);
                if body.len() >= len || n == 0 {
                    break;
                }
            }
            let text = String::from_utf8_lossy(&request).into_owned();
            let body = text.split_once("\r\n\r\n").map_or("", |(_, b)| b);
            let parsed: serde_json::Value = serde_json::from_str(body).unwrap_or_default();
            let data: Vec<serde_json::Value> = parsed["input"]
                .as_array()
                .map(|inputs| {
                    inputs
                        .iter()
                        .enumerate()
                        .map(|(index, input)| {
                            let alpha = input.as_str().is_some_and(|s| s.contains("alpha"));
                            let embedding = if alpha { [1.0, 0.0] } else { [0.0, 1.0] };
                            serde_json::json!({"index": index, "embedding": embedding})
                        })
                        .collect()
                })
                .unwrap_or_default();
            let payload = serde_json::json!({"model": "fake-model", "data": data}).to_string();
            let reply = format!(
                "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{payload}",
                payload.len()
            );
            let _ = stream.write_all(reply.as_bytes());
        }
    }
}

fn run(bin: &str, args: &[&str], stdin: &str) -> Output {
    let mut child = Command::new(bin)
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(stdin.as_bytes())
        .unwrap();
    child.wait_with_output().unwrap()
}

fn memory_args<'a>(dir: &'a str, embedder: &'a str, cache: &'a str) -> Vec<&'a str> {
    vec![
        "--memory-dir",
        dir,
        "--embedder",
        embedder,
        "--cache",
        cache,
    ]
}

fn skill_args<'a>(root: &'a str, embedder: &'a str, cache: &'a str) -> Vec<&'a str> {
    vec![
        "--skills-root",
        root,
        "--embedder",
        embedder,
        "--cache",
        cache,
    ]
}

fn embedder(url: &str) -> String {
    format!("t=none@{url}")
}

fn payload(prompt: &str) -> String {
    serde_json::json!({ "prompt": prompt }).to_string()
}

fn context(output: &Output) -> String {
    if output.stdout.is_empty() {
        return String::new();
    }
    let value: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    value["hookSpecificOutput"]["additionalContext"]
        .as_str()
        .unwrap()
        .to_owned()
}

fn log_entries(path: &Path) -> Vec<Entry> {
    parse_log(&fs::read_to_string(path).unwrap_or_default())
}

fn write_memories(dir: &Path) {
    fs::create_dir_all(dir).unwrap();
    fs::write(
        dir.join("alpha-note.md"),
        "---\nname: alpha-note\ndescription: about alpha\n---\nthe alpha fix is to restart it\n",
    )
    .unwrap();
}

fn write_skills(root: &Path) {
    let skill = root.join("s1");
    fs::create_dir_all(&skill).unwrap();
    fs::write(
        skill.join("SKILL.md"),
        "---\nname: s1\ndescription: x\n---\n## Alpha\nalpha steps go here\n",
    )
    .unwrap();
}

#[test]
fn memory_hook_injects_a_match_and_logs_it_without_the_prompt() {
    let tmp = tempfile::tempdir().unwrap();
    write_memories(&tmp.path().join("mem"));
    let (mem, cache, log) = (
        tmp.path().join("mem"),
        tmp.path().join("cache.json"),
        tmp.path().join("recall.jsonl"),
    );
    let emb = embedder(&serve());
    let base = memory_args(mem.to_str().unwrap(), &emb, cache.to_str().unwrap());

    let mut index = base.clone();
    index.push("index");
    assert!(run(MEMORY_BIN, &index, "").status.success());

    let mut hook = base.clone();
    hook.extend(["hook", "--log", log.to_str().unwrap()]);
    let out = run(
        MEMORY_BIN,
        &hook,
        &payload("how do I fix the alpha problem"),
    );
    assert!(out.status.success());
    assert!(context(&out).contains("alpha-note.md"), "{out:?}");

    let entries = log_entries(&log);
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].kind, "memory");
    assert!(entries[0].matches >= 1 && !entries[0].failed);
    assert!(!fs::read_to_string(&log).unwrap().contains("alpha problem"));
}

#[test]
fn memory_hook_injects_nothing_for_an_unrelated_prompt_but_still_logs_the_score() {
    let tmp = tempfile::tempdir().unwrap();
    write_memories(&tmp.path().join("mem"));
    let (mem, cache, log) = (
        tmp.path().join("mem"),
        tmp.path().join("cache.json"),
        tmp.path().join("recall.jsonl"),
    );
    let emb = embedder(&serve());
    let base = memory_args(mem.to_str().unwrap(), &emb, cache.to_str().unwrap());
    let mut index = base.clone();
    index.push("index");
    assert!(run(MEMORY_BIN, &index, "").status.success());

    let mut hook = base.clone();
    hook.extend(["hook", "--log", log.to_str().unwrap()]);
    let out = run(
        MEMORY_BIN,
        &hook,
        &payload("write a haiku about autumn leaves"),
    );
    assert!(out.status.success());
    assert!(out.stdout.is_empty());
    let entries = log_entries(&log);
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].matches, 0);
    assert!(entries[0].best_score.is_some());
}

#[test]
fn memory_hook_falls_back_to_keyword_matches_when_the_server_is_down() {
    let tmp = tempfile::tempdir().unwrap();
    write_memories(&tmp.path().join("mem"));
    let (mem, cache, log) = (
        tmp.path().join("mem"),
        tmp.path().join("cache.json"),
        tmp.path().join("recall.jsonl"),
    );
    let emb = embedder(DEAD_URL);
    let mut hook = memory_args(mem.to_str().unwrap(), &emb, cache.to_str().unwrap());
    hook.extend(["hook", "--log", log.to_str().unwrap()]);
    let out = run(
        MEMORY_BIN,
        &hook,
        &payload("how do I fix the alpha problem"),
    );
    assert!(
        out.status.success(),
        "a dead server must not fail the prompt"
    );
    assert!(
        context(&out).contains("alpha-note.md"),
        "the prompt still gets the memory that shares its words: {out:?}"
    );
    let entries = log_entries(&log);
    assert_eq!(entries.len(), 1);
    assert!(entries[0].fallback && !entries[0].failed && entries[0].matches >= 1);
}

#[test]
fn memory_hook_rides_out_a_server_that_comes_back_within_a_second() {
    let tmp = tempfile::tempdir().unwrap();
    write_memories(&tmp.path().join("mem"));
    let (mem, cache, log) = (
        tmp.path().join("mem"),
        tmp.path().join("cache.json"),
        tmp.path().join("recall.jsonl"),
    );
    let live = embedder(&serve());
    let mut index = memory_args(mem.to_str().unwrap(), &live, cache.to_str().unwrap());
    index.push("index");
    assert!(run(MEMORY_BIN, &index, "").status.success());

    // A port nothing listens on yet; the server binds it 400 ms into the hook.
    let port = TcpListener::bind("127.0.0.1:0")
        .unwrap()
        .local_addr()
        .unwrap()
        .port();
    thread::spawn(move || {
        thread::sleep(std::time::Duration::from_millis(400));
        serve_on(TcpListener::bind(("127.0.0.1", port)).unwrap());
    });
    let restarting = embedder(&format!("http://127.0.0.1:{port}"));
    let mut hook = memory_args(mem.to_str().unwrap(), &restarting, cache.to_str().unwrap());
    hook.extend(["hook", "--log", log.to_str().unwrap()]);
    let out = run(
        MEMORY_BIN,
        &hook,
        &payload("how do I fix the alpha problem"),
    );
    assert!(context(&out).contains("alpha-note.md"));
    assert!(
        !log_entries(&log)[0].fallback,
        "the retry reached the server"
    );
}

#[test]
fn memory_hook_logs_a_failure_only_when_there_is_nothing_to_search() {
    let tmp = tempfile::tempdir().unwrap();
    let log = tmp.path().join("recall.jsonl");
    let emb = embedder(DEAD_URL);
    let missing = tmp.path().join("no-such-dir");
    let cache = tmp.path().join("cache.json");
    let mut hook = memory_args(missing.to_str().unwrap(), &emb, cache.to_str().unwrap());
    hook.extend(["hook", "--log", log.to_str().unwrap()]);
    let out = run(
        MEMORY_BIN,
        &hook,
        &payload("how do I fix the alpha problem"),
    );
    assert!(out.status.success() && out.stdout.is_empty());
    assert!(log_entries(&log)[0].failed);
}

#[test]
fn skill_hook_injects_a_section_and_counts_it_as_shown_in_full() {
    let tmp = tempfile::tempdir().unwrap();
    write_skills(&tmp.path().join("skills"));
    let (root, cache, log) = (
        tmp.path().join("skills"),
        tmp.path().join("skills.json"),
        tmp.path().join("recall.jsonl"),
    );
    let emb = embedder(&serve());
    let base = skill_args(root.to_str().unwrap(), &emb, cache.to_str().unwrap());
    let mut index = base.clone();
    index.push("index");
    assert!(run(SKILL_BIN, &index, "").status.success());

    let mut hook = base.clone();
    hook.extend(["hook", "--log", log.to_str().unwrap()]);
    let out = run(
        SKILL_BIN,
        &hook,
        &payload("what are the alpha steps please"),
    );
    assert!(out.status.success());
    let text = context(&out);
    assert!(text.contains("s1/SKILL.md#Alpha") && text.contains("alpha steps go here"));
    let entries = log_entries(&log);
    assert_eq!(entries[0].kind, "skills");
    assert_eq!(entries[0].full, entries[0].matches);
    assert!(entries[0].matches >= 1);
}

#[test]
fn skill_hook_falls_back_to_keyword_matches_when_the_server_is_down() {
    let tmp = tempfile::tempdir().unwrap();
    write_skills(&tmp.path().join("skills"));
    let (root, cache, log) = (
        tmp.path().join("skills"),
        tmp.path().join("skills.json"),
        tmp.path().join("recall.jsonl"),
    );
    let emb = embedder(DEAD_URL);
    let mut hook = skill_args(root.to_str().unwrap(), &emb, cache.to_str().unwrap());
    hook.extend(["hook", "--log", log.to_str().unwrap()]);
    let out = run(
        SKILL_BIN,
        &hook,
        &payload("what are the alpha steps please"),
    );
    assert!(out.status.success());
    assert!(context(&out).contains("s1/SKILL.md#Alpha"));
    let entries = log_entries(&log);
    assert!(entries[0].fallback && !entries[0].failed);
}

#[test]
fn short_prompts_are_ignored_and_not_logged() {
    let tmp = tempfile::tempdir().unwrap();
    let log = tmp.path().join("recall.jsonl");
    let emb = embedder(DEAD_URL);
    let mut hook = memory_args("/nonexistent", &emb, "/nonexistent/cache.json");
    hook.extend(["hook", "--log", log.to_str().unwrap()]);
    let out = run(MEMORY_BIN, &hook, &payload("yes"));
    assert!(out.status.success() && out.stdout.is_empty());
    assert!(!log.exists());
}

#[test]
fn log_summary_reads_the_log_and_its_rotated_files() {
    let tmp = tempfile::tempdir().unwrap();
    let log = tmp.path().join("recall.jsonl");
    let line = |matches: usize| {
        retrieval_eval::recall_log::to_line(&Entry {
            at: "2026-10-07T12:00:00Z".to_owned(),
            kind: "memory".to_owned(),
            best_score: Some(0.8),
            matches,
            full: 0,
            tokens: 10,
            failed: false,
            fallback: false,
        })
    };
    fs::write(&log, line(1)).unwrap();
    let mut gz_path = log.as_os_str().to_owned();
    gz_path.push(".1.gz");
    let mut encoder = flate2::write::GzEncoder::new(
        fs::File::create(&gz_path).unwrap(),
        flate2::Compression::default(),
    );
    encoder.write_all(line(0).as_bytes()).unwrap();
    encoder.finish().unwrap();

    let out = run(MEMORY_BIN, &["log-summary", log.to_str().unwrap()], "");
    assert!(out.status.success());
    let table = String::from_utf8(out.stdout).unwrap();
    assert!(table.contains("| memory | 2 | 1 (50%)"), "{table}");
}
