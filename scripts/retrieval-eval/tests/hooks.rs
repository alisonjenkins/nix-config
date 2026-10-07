//! Drives the real `memory-recall` and `skill-recall` binaries against a fake
//! embeddings server: a text containing "alpha" embeds to [1, 0], anything else
//! to [0, 1], so which document matches a prompt is checkable by hand.
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]
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
    hook.extend([
        "hook",
        "--on-unavailable",
        "keyword",
        "--log",
        log.to_str().unwrap(),
    ]);
    let out = run(
        MEMORY_BIN,
        &hook,
        &payload("how do I fix the alpha problem"),
    );
    assert!(out.status.success());
    assert!(
        context(&out).contains("alpha-note.md"),
        "the prompt still gets the memory that shares its words: {out:?}"
    );
    let entries = log_entries(&log);
    assert_eq!(entries.len(), 1);
    assert!(entries[0].fallback && !entries[0].failed && entries[0].matches >= 1);
}

#[test]
fn memory_hook_blocks_the_prompt_by_default_when_it_cannot_retrieve_memories() {
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
    assert_eq!(
        out.status.code(),
        Some(2),
        "exit 2 blocks a prompt: {out:?}"
    );
    assert!(out.stdout.is_empty());
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("blocked") && stderr.contains("--on-unavailable"),
        "the message says what happened and how to change it: {stderr}"
    );
    assert!(log_entries(&log)[0].failed);
}

#[test]
fn memory_hook_lets_the_prompt_through_with_nothing_when_told_to_allow() {
    let tmp = tempfile::tempdir().unwrap();
    write_memories(&tmp.path().join("mem"));
    let (mem, cache, log) = (
        tmp.path().join("mem"),
        tmp.path().join("cache.json"),
        tmp.path().join("recall.jsonl"),
    );
    let emb = embedder(DEAD_URL);
    let mut hook = memory_args(mem.to_str().unwrap(), &emb, cache.to_str().unwrap());
    hook.extend([
        "hook",
        "--on-unavailable",
        "allow",
        "--log",
        log.to_str().unwrap(),
    ]);
    let out = run(
        MEMORY_BIN,
        &hook,
        &payload("how do I fix the alpha problem"),
    );
    assert!(out.status.success() && out.stdout.is_empty());
    assert!(log_entries(&log)[0].failed);
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
fn a_fresh_setup_with_no_memories_can_prompt_even_with_the_server_down() {
    let tmp = tempfile::tempdir().unwrap();
    let emb = embedder(DEAD_URL);
    let cache = tmp.path().join("cache.json");
    let empty = tmp.path().join("empty");
    fs::create_dir_all(&empty).unwrap();
    for dir in [tmp.path().join("no-such-dir"), empty] {
        let log = tmp.path().join("recall.jsonl");
        let mut hook = memory_args(dir.to_str().unwrap(), &emb, cache.to_str().unwrap());
        hook.extend(["hook", "--log", log.to_str().unwrap()]);
        let out = run(
            MEMORY_BIN,
            &hook,
            &payload("how do I fix the alpha problem"),
        );
        assert!(out.status.success(), "{dir:?}: {out:?}");
        assert!(out.stdout.is_empty());
        let entries = log_entries(&log);
        assert!(
            !entries.last().unwrap().failed,
            "nothing to retrieve is not a failure"
        );
        let _ = fs::remove_file(&log);
    }
}

#[test]
fn memories_that_are_not_indexed_yet_do_not_block_the_first_prompts() {
    let tmp = tempfile::tempdir().unwrap();
    write_memories(&tmp.path().join("mem"));
    let (mem, cache) = (tmp.path().join("mem"), tmp.path().join("never-built.json"));
    let emb = embedder(&serve());
    let mut hook = memory_args(mem.to_str().unwrap(), &emb, cache.to_str().unwrap());
    hook.push("hook");
    let out = run(
        MEMORY_BIN,
        &hook,
        &payload("how do I fix the alpha problem"),
    );
    assert!(out.status.success() && out.stdout.is_empty(), "{out:?}");
}

#[test]
fn a_fresh_setup_with_no_skills_can_prompt_even_with_the_server_down() {
    let tmp = tempfile::tempdir().unwrap();
    let emb = embedder(DEAD_URL);
    let cache = tmp.path().join("skills.json");
    let empty = tmp.path().join("empty");
    fs::create_dir_all(&empty).unwrap();
    for root in [tmp.path().join("no-such-dir"), empty] {
        let mut hook = skill_args(root.to_str().unwrap(), &emb, cache.to_str().unwrap());
        hook.push("hook");
        let out = run(
            SKILL_BIN,
            &hook,
            &payload("what are the alpha steps please"),
        );
        assert!(out.status.success(), "{root:?}: {out:?}");
        assert!(out.stdout.is_empty());
    }
}

#[test]
fn the_catalogue_keeper_does_nothing_for_a_fresh_setup() {
    let tmp = tempfile::tempdir().unwrap();
    let missing = tmp.path().join("no-memories-yet");
    let target = missing.join("MEMORY.md");
    let emb = embedder(DEAD_URL);
    let cache = tmp.path().join("c.json");
    let mut args = memory_args(missing.to_str().unwrap(), &emb, cache.to_str().unwrap());
    args.extend(["catalogue", "--write", target.to_str().unwrap()]);
    let out = run(MEMORY_BIN, &args, "");
    assert!(out.status.success(), "{out:?}");
    assert!(
        !missing.exists(),
        "no memory directory is created for nothing"
    );
}

#[test]
fn the_index_commands_accept_a_fresh_setup() {
    let tmp = tempfile::tempdir().unwrap();
    let emb = embedder(&serve());
    let missing = tmp.path().join("nothing-here");
    let (memory_cache, skills_cache) = (tmp.path().join("m.json"), tmp.path().join("s.json"));
    let mut index = memory_args(
        missing.to_str().unwrap(),
        &emb,
        memory_cache.to_str().unwrap(),
    );
    index.push("index");
    assert!(run(MEMORY_BIN, &index, "").status.success());
    let mut skills = skill_args(
        missing.to_str().unwrap(),
        &emb,
        skills_cache.to_str().unwrap(),
    );
    skills.push("index");
    assert!(run(SKILL_BIN, &skills, "").status.success());
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
    hook.extend([
        "hook",
        "--on-unavailable",
        "keyword",
        "--log",
        log.to_str().unwrap(),
    ]);
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
fn skill_hook_blocks_the_prompt_by_default_when_it_cannot_retrieve_skills() {
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
    assert_eq!(out.status.code(), Some(2));
    assert!(out.stdout.is_empty());
    assert!(String::from_utf8_lossy(&out.stderr).contains("blocked"));
    assert!(log_entries(&log)[0].failed);
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
            duration_ms: None,
            embed_ms: None,
            session_id: None,
            prompt_id: None,
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

/// What a fake Loki or Tempo received: request path, lowercased headers, body.
type Captured = std::sync::Arc<std::sync::Mutex<Vec<(String, String, String)>>>;

/// Answers every POST with 204 and records it.
fn capture() -> (String, Captured) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let seen: Captured = Captured::default();
    let sink = std::sync::Arc::clone(&seen);
    thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { continue };
            let mut request = Vec::new();
            let mut buf = vec![0_u8; 65536];
            loop {
                let n = stream.read(&mut buf).unwrap_or(0);
                request.extend_from_slice(&buf[..n]);
                let text = String::from_utf8_lossy(&request).into_owned();
                if let Some((head, body)) = text.split_once("\r\n\r\n") {
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
                } else if n == 0 {
                    break;
                }
            }
            let text = String::from_utf8_lossy(&request).into_owned();
            if let Some((head, body)) = text.split_once("\r\n\r\n") {
                let path = head
                    .lines()
                    .next()
                    .and_then(|l| l.split_whitespace().nth(1))
                    .unwrap_or_default()
                    .to_owned();
                sink.lock()
                    .unwrap()
                    .push((path, head.to_lowercase(), body.to_owned()));
            }
            let _ = stream.write_all(
                b"HTTP/1.1 204 No Content\r\nconnection: close\r\ncontent-length: 0\r\n\r\n",
            );
        }
    });
    (base, seen)
}

/// Waits for the detached shipper to deliver `count` requests.
fn wait_for(seen: &Captured, count: usize) {
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(10);
    while seen.lock().unwrap().len() < count && std::time::Instant::now() < deadline {
        thread::sleep(std::time::Duration::from_millis(50));
    }
}

fn indexed_memory_hook(tmp: &Path, embed: &str) -> (std::path::PathBuf, std::path::PathBuf) {
    write_memories(&tmp.join("mem"));
    let (mem, cache) = (tmp.join("mem"), tmp.join("cache.json"));
    let mut index = memory_args(mem.to_str().unwrap(), embed, cache.to_str().unwrap());
    index.push("index");
    assert!(run(MEMORY_BIN, &index, "").status.success());
    (mem, cache)
}

#[test]
fn a_hook_run_reaches_loki_and_tempo_without_the_prompt() {
    let tmp = tempfile::tempdir().unwrap();
    let emb = embedder(&serve());
    let (mem, cache) = indexed_memory_hook(tmp.path(), &emb);
    let (backend, seen) = capture();

    let mut hook = memory_args(mem.to_str().unwrap(), &emb, cache.to_str().unwrap());
    hook.extend([
        "hook",
        "--loki-url",
        &backend,
        "--otlp-endpoint",
        &backend,
        "--telemetry-tenant",
        "tenant-a",
        "--telemetry-label",
        "host=desk",
    ]);
    let out = run(
        MEMORY_BIN,
        &hook,
        &payload("how do I fix the secretword alpha problem"),
    );
    assert!(out.status.success() && context(&out).contains("alpha-note.md"));

    wait_for(&seen, 2);
    let requests = seen.lock().unwrap().clone();
    assert_eq!(requests.len(), 2, "one Loki push and one trace");
    let loki = requests
        .iter()
        .find(|r| r.0 == "/loki/api/v1/push")
        .expect("loki push");
    let tempo = requests
        .iter()
        .find(|r| r.0 == "/v1/traces")
        .expect("trace");
    for request in [loki, tempo] {
        assert!(
            request.1.contains("x-scope-orgid: tenant-a"),
            "{}",
            request.1
        );
        assert!(
            !request.2.contains("secretword"),
            "the prompt must not be shipped"
        );
    }
    assert!(loki.2.contains("\"host\":\"desk\""));
    assert!(tempo.2.contains("memory-recall.hook") && tempo.2.contains("\"embed\""));
}

#[test]
fn claude_codes_ids_and_trace_context_reach_the_log_and_the_shipped_span() {
    let tmp = tempfile::tempdir().unwrap();
    let emb = embedder(&serve());
    let (mem, cache) = indexed_memory_hook(tmp.path(), &emb);
    let log = tmp.path().join("recall.jsonl");
    let (backend, seen) = capture();
    let mut hook = memory_args(mem.to_str().unwrap(), &emb, cache.to_str().unwrap());
    hook.extend([
        "hook",
        "--log",
        log.to_str().unwrap(),
        "--otlp-endpoint",
        &backend,
    ]);
    let payload = serde_json::json!({
        "prompt": "how do I fix the alpha problem",
        "session_id": "sess-42",
        "prompt_id": "prompt-7",
    })
    .to_string();
    let mut child = Command::new(MEMORY_BIN)
        .args(&hook)
        .env(
            "TRACEPARENT",
            "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
        )
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(payload.as_bytes())
        .unwrap();
    assert!(child.wait_with_output().unwrap().status.success());

    let entry = &log_entries(&log)[0];
    assert_eq!(entry.session_id.as_deref(), Some("sess-42"));
    assert_eq!(entry.prompt_id.as_deref(), Some("prompt-7"));
    wait_for(&seen, 1);
    let body = seen.lock().unwrap()[0].2.clone();
    assert!(body.contains("sess-42") && body.contains("prompt-7"));
    assert!(body.contains("4bf92f3577b34da6a3ce929d0e0e4736"));
    assert!(
        body.contains("00f067aa0ba902b7"),
        "continues Claude Code's span"
    );
}

#[test]
fn a_blocked_prompt_is_shipped_as_a_failure() {
    let tmp = tempfile::tempdir().unwrap();
    write_memories(&tmp.path().join("mem"));
    let (mem, cache) = (tmp.path().join("mem"), tmp.path().join("cache.json"));
    let emb = embedder(DEAD_URL);
    let (backend, seen) = capture();
    let mut hook = memory_args(mem.to_str().unwrap(), &emb, cache.to_str().unwrap());
    hook.extend(["hook", "--otlp-endpoint", &backend]);
    let out = run(
        MEMORY_BIN,
        &hook,
        &payload("how do I fix the alpha problem"),
    );
    assert_eq!(out.status.code(), Some(2));
    wait_for(&seen, 1);
    let requests = seen.lock().unwrap().clone();
    assert!(requests[0].2.contains("\"code\":2"), "{}", requests[0].2);
}

#[test]
fn a_backend_that_never_answers_does_not_delay_the_prompt() {
    let tmp = tempfile::tempdir().unwrap();
    let emb = embedder(&serve());
    let (mem, cache) = indexed_memory_hook(tmp.path(), &emb);
    // Accepts connections and never replies.
    let hang = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}", hang.local_addr().unwrap());
    thread::spawn(move || {
        let mut held = Vec::new();
        for stream in hang.incoming().flatten() {
            held.push(stream);
        }
    });
    let mut hook = memory_args(mem.to_str().unwrap(), &emb, cache.to_str().unwrap());
    hook.extend(["hook", "--loki-url", &url, "--otlp-endpoint", &url]);
    let started = std::time::Instant::now();
    let out = run(
        MEMORY_BIN,
        &hook,
        &payload("how do I fix the alpha problem"),
    );
    assert!(out.status.success() && context(&out).contains("alpha-note.md"));
    assert!(
        started.elapsed() < std::time::Duration::from_millis(2500),
        "the shipper has a 3 s timeout, so a hook that waited for it would take longer: {:?}",
        started.elapsed()
    );
}
