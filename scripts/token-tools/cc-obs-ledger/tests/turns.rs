#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::unwrap_in_result
)]

//! Which string-content user records start a turn.

use cc_obs_ledger::transcript::{parse, ToolHasher};

fn hasher() -> ToolHasher {
    ToolHasher::new(b"k".to_vec())
}

fn assistant(request: &str) -> String {
    format!(
        r#"{{"type":"assistant","sessionId":"s","requestId":"{request}","timestamp":"2026-10-17T10:00:00Z","cwd":"/w","isSidechain":false,"message":{{"model":"m","role":"assistant","content":[{{"type":"text","text":"x"}}],"usage":{{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":2,"cache_creation_input_tokens":3}}}}}}"#
    )
}

fn user(text: &str) -> String {
    format!(
        r#"{{"type":"user","sessionId":"s","cwd":"/w","isSidechain":false,"message":{{"role":"user","content":"{text}"}}}}"#
    )
}

fn turns(lines: &[String]) -> Vec<u64> {
    parse(&lines.join("\n"), &hasher())
        .requests
        .iter()
        .map(|r| r.turn)
        .collect()
}

#[test]
fn only_a_real_prompt_starts_a_turn() {
    let cases: [(&str, &str, bool); 14] = [
        ("real prompt", "fix the bug", true),
        ("leading whitespace prompt", "  \\n fix the bug", true),
        ("interrupt", "[Request interrupted by user]", false),
        (
            "interrupt for tool use",
            "[Request interrupted by user for tool use]",
            false,
        ),
        ("command name", "<command-name>/clear</command-name>", false),
        (
            "command message",
            "<command-message>x</command-message>",
            false,
        ),
        ("command args", "<command-args>a</command-args>", false),
        (
            "local stdout",
            "<local-command-stdout>ok</local-command-stdout>",
            false,
        ),
        (
            "local stderr",
            "<local-command-stderr>no</local-command-stderr>",
            false,
        ),
        (
            "local caveat",
            "<local-command-caveat>c</local-command-caveat>",
            false,
        ),
        (
            "task notification",
            "<task-notification>done</task-notification>",
            false,
        ),
        (
            "indented task notification",
            "\\n  <task-notification>done",
            false,
        ),
        (
            "mid-text task notification",
            "why does <task-notification> wake me",
            true,
        ),
        (
            "mid-text interrupt",
            "I saw [Request interrupted earlier",
            true,
        ),
    ];
    for (name, text, starts) in cases {
        let got = turns(&[user(text), assistant("r1")]);
        let want = if starts { vec![1] } else { vec![0] };
        assert_eq!(got, want, "{name}: {text}");
    }
}

#[test]
fn skipped_kinds_between_prompts_do_not_add_turns() {
    let got = turns(&[
        user("first"),
        assistant("r1"),
        user("<task-notification>x</task-notification>"),
        assistant("r2"),
        user("[Request interrupted by user]"),
        user("second"),
        assistant("r3"),
    ]);
    assert_eq!(got, vec![1, 1, 2]);
}

#[test]
fn leading_skipped_records_do_not_become_the_first_prompt() {
    let lines = [
        user("<command-name>/clear</command-name>"),
        user("<local-command-stdout></local-command-stdout>"),
        user("<task-notification>x</task-notification>"),
        user("hello"),
        assistant("r1"),
    ];
    let parsed = parse(&lines.join("\n"), &hasher());
    assert_eq!(parsed.first_prompt_chars, 5);
}
