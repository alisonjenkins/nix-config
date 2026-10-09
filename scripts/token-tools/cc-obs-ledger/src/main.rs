//! Claude Code hook entry points. Every subcommand reads the hook JSON on stdin,
//! prints nothing, and exits 0 even on failure (the reason goes to the local log),
//! so it can never get in the way of a prompt. `--check` makes it exit 1 on error,
//! for tests.

use std::env;
use std::fs;
use std::io::{Read, Write};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command as Process, ExitCode, Stdio};
use std::time::Duration;

use cc_obs_ledger::census::{self, Census, CensusInput};
use cc_obs_ledger::config::{
    create_dir, endpoints_path, home_dir, load_endpoints, load_or_create_key, log_line, state_dir,
    write_atomic,
};
use cc_obs_ledger::error::LedgerError;
use cc_obs_ledger::notice::{notice_line, review_state_dir, stack_line, stack_state_dir};
use cc_obs_ledger::otlp::{session_payloads, turn_payloads, Payload, Resource};
use cc_obs_ledger::ship::{ship_spool, write_spool};
use cc_obs_ledger::transcript::{
    complete_lines, parse, parse_from, read_unread, Position, ToolHasher,
};
use clap::{Parser, Subcommand};
use serde::{Deserialize, Serialize};

const SEND_TIMEOUT: Duration = Duration::from_secs(3);

/// Largest unread transcript a hook parses; hooks have a 5 s timeout and parsing is synchronous.
const MAX_UNREAD_BYTES: u64 = 64 * 1024 * 1024;

#[derive(Parser)]
#[command(version, about = "Token-spend ledger hooks for Claude Code")]
struct Cli {
    /// Exit 1 on error instead of 0.
    #[arg(long, global = true)]
    check: bool,
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// SessionStart: estimate the fixed context and store it for the session.
    Census,
    /// Stop: send context size, cache hit ratio and tool-call records for the new turns.
    Turn,
    /// SessionEnd: send the fixed-context split and the session summary.
    End,
    /// SessionStart: print a line if the observability stack is over its disk budget, and one if a token review waits to be promoted or dismissed.
    Notice,
    /// Internal: post spooled payloads to the collector.
    Ship,
}

#[derive(Deserialize)]
struct Hook {
    session_id: Option<String>,
    transcript_path: Option<String>,
    cwd: Option<String>,
}

/// Where the last Stop stopped reading. `turn` and `seq` carry the session-wide
/// numbering across Stops; cursor files from before they existed read as 0.
#[derive(Serialize, Deserialize, Default, Debug, PartialEq, Eq)]
struct Cursor {
    offset: u64,
    #[serde(default)]
    turn: u64,
    #[serde(default)]
    seq: u64,
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    let state = state_dir();
    let result = match cli.command {
        Command::Census => census_cmd(&state),
        Command::Turn => turn_cmd(&state),
        Command::End => end_cmd(&state),
        Command::Notice => notice_cmd(),
        Command::Ship => ship_cmd(&state),
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            log_line(&state, &format!("{}: {error}", name(&cli.command)));
            if cli.check {
                ExitCode::FAILURE
            } else {
                ExitCode::SUCCESS
            }
        }
    }
}

fn name(command: &Command) -> &'static str {
    match command {
        Command::Census => "census",
        Command::Turn => "turn",
        Command::End => "end",
        Command::Notice => "notice",
        Command::Ship => "ship",
    }
}

fn read_hook() -> Result<Hook, LedgerError> {
    let mut input = String::new();
    std::io::stdin()
        .read_to_string(&mut input)
        .map_err(LedgerError::Stdin)?;
    serde_json::from_str(&input).map_err(LedgerError::HookJson)
}

/// Session ids become file names, so keep them to safe characters.
fn session_file(hook: &Hook) -> Result<String, LedgerError> {
    let id = hook
        .session_id
        .as_deref()
        .filter(|id| !id.is_empty())
        .ok_or(LedgerError::MissingField {
            field: "session_id",
        })?;
    Ok(id
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '-' || c == '_' {
                c
            } else {
                '_'
            }
        })
        .collect())
}

fn write_file(path: &Path, text: &str) -> Result<(), LedgerError> {
    if let Some(parent) = path.parent() {
        create_dir(parent)?;
    }
    write_atomic(path, text.as_bytes())
}

fn census_cmd(state: &Path) -> Result<(), LedgerError> {
    let hook = read_hook()?;
    let session = session_file(&hook)?;
    let cwd = hook
        .cwd
        .map(PathBuf::from)
        .or_else(|| env::current_dir().ok())
        .unwrap_or_default();
    let home = home_dir();
    let census = census::run(&CensusInput {
        cwd: &cwd,
        home: &home,
    });
    let text = serde_json::to_string(&census).map_err(|source| LedgerError::ParseFile {
        path: PathBuf::from("census"),
        source,
    })?;
    write_file(&state.join("census").join(format!("{session}.json")), &text)
}

fn resource() -> Resource {
    let host = load_endpoints(&endpoints_path())
        .map(|e| e.host)
        .unwrap_or_else(|_| "unknown".to_owned());
    let pairs = env::var("OTEL_RESOURCE_ATTRIBUTES").unwrap_or_default();
    Resource::from_env_string(&host, &pairs)
}

fn spawn_ship() -> Result<(), LedgerError> {
    let exe = env::current_exe().map_err(|source| LedgerError::Spawn {
        exe: PathBuf::from("cc-obs-ledger"),
        source,
    })?;
    Process::new(&exe)
        .arg("ship")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .process_group(0)
        .spawn()
        .map(|_| ())
        .map_err(|source| LedgerError::Spawn { exe, source })
}

/// Spooled payloads are durable, so a failure to start the sender is only logged:
/// the next `ship` run drains the spool, and failing here would make the caller
/// skip its cursor write and spool the same payloads again.
fn spool_and_ship(
    state: &Path,
    payloads: &[Payload],
    spawn: &dyn Fn() -> Result<(), LedgerError>,
) -> Result<(), LedgerError> {
    if payloads.is_empty() {
        return Ok(());
    }
    let spool = state.join("spool");
    for payload in payloads {
        write_spool(&spool, payload)?;
    }
    if let Err(error) = spawn() {
        log_line(
            state,
            &format!("ship not started, payloads stay spooled: {error}"),
        );
    }
    Ok(())
}

fn cursor_path(state: &Path, session: &str) -> PathBuf {
    state.join("cursors").join(format!("{session}.json"))
}

fn read_error(path: &Path) -> impl FnOnce(std::io::Error) -> LedgerError + '_ {
    |source| LedgerError::Read {
        path: path.to_owned(),
        source,
    }
}

fn read_hook_transcript(hook: Hook) -> Result<(String, PathBuf), LedgerError> {
    let session = session_file(&hook)?;
    let transcript = PathBuf::from(hook.transcript_path.ok_or(LedgerError::MissingField {
        field: "transcript_path",
    })?);
    Ok((session, transcript))
}

fn turn_cmd(state: &Path) -> Result<(), LedgerError> {
    let (session, transcript) = read_hook_transcript(read_hook()?)?;
    turn_run(state, &session, &transcript, MAX_UNREAD_BYTES, &spawn_ship)
}

fn turn_run(
    state: &Path,
    session: &str,
    transcript: &Path,
    limit: u64,
    spawn: &dyn Fn() -> Result<(), LedgerError>,
) -> Result<(), LedgerError> {
    let cursor_file = cursor_path(state, session);
    let cursor: Cursor = fs::read_to_string(&cursor_file)
        .ok()
        .and_then(|text| serde_json::from_str(&text).ok())
        .unwrap_or_default();

    let mut file = fs::File::open(transcript).map_err(read_error(transcript))?;
    let length = file.metadata().map_err(read_error(transcript))?.len();
    // A transcript shorter than the cursor was replaced: start over, counters too.
    let (start, position) = if cursor.offset > length {
        (0, Position::default())
    } else {
        (
            cursor.offset,
            Position {
                turn: cursor.turn,
                seq: cursor.seq,
            },
        )
    };
    let unread = read_unread(&mut file, start, limit).map_err(read_error(transcript))?;
    if unread.skipped > 0 {
        log_line(
            state,
            &format!(
                "turn: {session}: skipped {} bytes of old transcript, over the {limit}-byte limit",
                unread.skipped
            ),
        );
    }
    // Split on raw bytes: the offset advances by file bytes, which lossy decoding changes.
    let complete = complete_lines(&unread.bytes);
    let text = String::from_utf8_lossy(complete);

    let hasher = ToolHasher::new(load_or_create_key(state)?);
    let parsed = parse_from(&text, &hasher, position);
    spool_and_ship(state, &turn_payloads(&resource(), &parsed), spawn)?;

    let next = Cursor {
        offset: start
            .saturating_add(unread.skipped)
            .saturating_add(complete.len() as u64),
        turn: parsed.end.turn,
        seq: parsed.end.seq,
    };
    let text = serde_json::to_string(&next).map_err(|source| LedgerError::ParseFile {
        path: cursor_file.clone(),
        source,
    })?;
    write_file(&cursor_file, &text)
}

fn end_cmd(state: &Path) -> Result<(), LedgerError> {
    let (session, transcript) = read_hook_transcript(read_hook()?)?;
    let mut file = fs::File::open(&transcript).map_err(read_error(&transcript))?;
    let unread = read_unread(&mut file, 0, MAX_UNREAD_BYTES).map_err(read_error(&transcript))?;
    if unread.skipped > 0 {
        log_line(
            state,
            &format!(
                "end: {session}: skipped {} bytes of old transcript, over the {MAX_UNREAD_BYTES}-byte limit",
                unread.skipped
            ),
        );
    }
    let text = String::from_utf8_lossy(&unread.bytes);
    let hasher = ToolHasher::new(load_or_create_key(state)?);
    let parsed = parse(&text, &hasher);

    let census_file = state.join("census").join(format!("{session}.json"));
    let census: Option<Census> = fs::read_to_string(&census_file)
        .ok()
        .and_then(|text| serde_json::from_str(&text).ok());
    spool_and_ship(
        state,
        &session_payloads(&resource(), &parsed, census.as_ref()),
        &spawn_ship,
    )?;

    // The session is over: its cursor and census are no longer needed.
    let _ = fs::remove_file(cursor_path(state, &session));
    let _ = fs::remove_file(census_file);
    Ok(())
}

fn notice_cmd() -> Result<(), LedgerError> {
    let stack = stack_state_dir().and_then(|dir| stack_line(&dir));
    let review = notice_line(&review_state_dir());
    for line in stack.into_iter().chain(review) {
        // `println!` panics on a closed stdout; a notice must never fail the hook.
        let _ = writeln!(std::io::stdout(), "{line}");
    }
    Ok(())
}

fn ship_cmd(state: &Path) -> Result<(), LedgerError> {
    let endpoints = load_endpoints(&endpoints_path())?;
    let report = ship_spool(
        &state.join("spool"),
        &endpoints.urls.otlp_http,
        SEND_TIMEOUT,
    );
    if let Some(summary) = report.summary() {
        log_line(state, &summary);
    }
    Ok(())
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]
mod tests {
    use super::*;

    const USER: &str = r#"{"type":"user","sessionId":"s","promptId":"p","cwd":"/w/p","message":{"role":"user","content":"PROMPT"}}"#;

    fn tool(n: u32) -> String {
        format!(
            r#"{{"type":"assistant","sessionId":"s","requestId":"r-{n}","cwd":"/w/p","isSidechain":false,"message":{{"id":"m-{n}","model":"m","content":[{{"type":"tool_use","id":"t-{n}","name":"Read","input":{{"n":{n}}}}}],"usage":{{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}}}}"#
        )
    }

    fn lines(items: &[String]) -> Vec<u8> {
        let mut text = items.join("\n");
        text.push('\n');
        text.into_bytes()
    }

    fn no_spawn() -> Result<(), LedgerError> {
        Ok(())
    }

    fn run(state: &Path, transcript: &Path, limit: u64) {
        turn_run(state, "s", transcript, limit, &no_spawn).unwrap();
    }

    fn cursor(state: &Path) -> Cursor {
        serde_json::from_str(&fs::read_to_string(cursor_path(state, "s")).unwrap()).unwrap()
    }

    /// The `seq` attribute of every spooled tool-call record, sorted.
    fn spooled_seqs(state: &Path) -> Vec<String> {
        let mut seqs = Vec::new();
        for entry in fs::read_dir(state.join("spool")).unwrap() {
            let path = entry.unwrap().path();
            if !path.to_string_lossy().ends_with(".logs.json") {
                continue;
            }
            let body: serde_json::Value =
                serde_json::from_str(&fs::read_to_string(&path).unwrap()).unwrap();
            let records = body
                .pointer("/resourceLogs/0/scopeLogs/0/logRecords")
                .and_then(serde_json::Value::as_array)
                .unwrap();
            for record in records {
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

    #[test]
    fn two_stops_over_a_split_transcript_match_one_stop_over_the_whole() {
        let all = lines(&[USER.into(), tool(1), tool(2), USER.into(), tool(3)]);
        let split = lines(&[USER.into(), tool(1)]).len();

        let whole_state = tempfile::tempdir().unwrap();
        let whole_file = whole_state.path().join("t.jsonl");
        fs::write(&whole_file, &all).unwrap();
        run(whole_state.path(), &whole_file, u64::MAX);

        let state = tempfile::tempdir().unwrap();
        let file = state.path().join("t.jsonl");
        fs::write(&file, &all[..split]).unwrap();
        run(state.path(), &file, u64::MAX);
        fs::write(&file, &all).unwrap();
        run(state.path(), &file, u64::MAX);

        assert_eq!(cursor(state.path()), cursor(whole_state.path()));
        assert_eq!(
            cursor(state.path()),
            Cursor {
                offset: all.len() as u64,
                turn: 2,
                seq: 3
            }
        );
        assert_eq!(spooled_seqs(state.path()), ["0", "1", "2"]);
        assert_eq!(spooled_seqs(whole_state.path()), ["0", "1", "2"]);
    }

    #[test]
    fn a_cursor_file_from_before_turn_and_seq_still_loads() {
        let old: Cursor = serde_json::from_str(r#"{"offset":42}"#).unwrap();
        assert_eq!(
            old,
            Cursor {
                offset: 42,
                turn: 0,
                seq: 0
            }
        );
    }

    #[test]
    fn a_stray_temp_file_beside_the_cursor_is_not_read_as_the_cursor() {
        let state = tempfile::tempdir().unwrap();
        let file = state.path().join("t.jsonl");
        fs::write(&file, lines(&[USER.to_owned(), tool(1)])).unwrap();
        run(state.path(), &file, u64::MAX);
        let cursors = state.path().join("cursors");
        fs::write(cursors.join(".s.json.1.1.tmp"), b"{\"offs").unwrap();
        run(state.path(), &file, u64::MAX);
        assert_eq!(spooled_seqs(state.path()), ["0"]);
        assert_eq!(cursor(state.path()).seq, 1);
    }

    #[test]
    fn an_invalid_utf8_byte_does_not_push_the_cursor_past_the_next_line() {
        let state = tempfile::tempdir().unwrap();
        let file = state.path().join("t.jsonl");
        let mut first = USER.as_bytes().to_vec();
        first.splice(first.len() - 12..first.len() - 12, [0xff]);
        first.push(b'\n');
        let second = lines(&[tool(1)]);
        let (head, tail) = second.split_at(20);

        let mut written = first.clone();
        written.extend_from_slice(head);
        fs::write(&file, &written).unwrap();
        run(state.path(), &file, u64::MAX);
        assert_eq!(cursor(state.path()).offset, first.len() as u64);

        written.extend_from_slice(tail);
        fs::write(&file, &written).unwrap();
        run(state.path(), &file, u64::MAX);
        assert_eq!(cursor(state.path()).offset, written.len() as u64);
        assert_eq!(spooled_seqs(state.path()), ["0"]);
    }

    #[test]
    fn a_failure_to_start_the_sender_still_advances_the_cursor() {
        let state = tempfile::tempdir().unwrap();
        let file = state.path().join("t.jsonl");
        let all = lines(&[USER.into(), tool(1)]);
        fs::write(&file, &all).unwrap();
        let failing = || {
            Err(LedgerError::Spawn {
                exe: PathBuf::from("cc-obs-ledger"),
                source: std::io::Error::other("no exec"),
            })
        };
        turn_run(state.path(), "s", &file, u64::MAX, &failing).unwrap();
        assert_eq!(cursor(state.path()).offset, all.len() as u64);
        assert_eq!(spooled_seqs(state.path()), ["0"]);
        let log = fs::read_to_string(state.path().join("ledger.log")).unwrap();
        assert!(log.contains("ship not started"), "{log}");

        run(state.path(), &file, u64::MAX);
        assert_eq!(spooled_seqs(state.path()), ["0"], "re-spooled");
    }

    #[test]
    fn an_oversized_backlog_is_cut_to_whole_newest_lines_and_logged() {
        let state = tempfile::tempdir().unwrap();
        let file = state.path().join("t.jsonl");
        let all = lines(&[USER.into(), tool(1), tool(2), tool(3)]);
        fs::write(&file, &all).unwrap();
        let limit = lines(&[tool(2), tool(3)]).len() as u64 + 5;
        run(state.path(), &file, limit);

        assert_eq!(cursor(state.path()).offset, all.len() as u64);
        assert_eq!(spooled_seqs(state.path()), ["0", "1"]);
        let log = fs::read_to_string(state.path().join("ledger.log")).unwrap();
        assert!(log.contains("skipped"), "{log}");
        assert_eq!(log.lines().count(), 1);
    }
}
