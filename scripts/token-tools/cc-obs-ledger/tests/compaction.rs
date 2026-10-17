#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::unwrap_in_result
)]

//! What `/compact` and synthetic user records do to turn numbering.

use cc_obs_ledger::transcript::{parse, ToolHasher};

fn hasher() -> ToolHasher {
    ToolHasher::new(b"k".to_vec())
}

fn assistant(request: &str) -> String {
    format!(
        r#"{{"type":"assistant","sessionId":"s","requestId":"{request}","timestamp":"2026-10-17T10:00:00Z","cwd":"/w","isSidechain":false,"message":{{"model":"m","role":"assistant","content":[{{"type":"text","text":"x"}}],"usage":{{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":2,"cache_creation_input_tokens":3}}}}}}"#
    )
}

fn prompt(text: &str) -> String {
    format!(
        r#"{{"type":"user","sessionId":"s","cwd":"/w","isSidechain":false,"message":{{"role":"user","content":"{text}"}}}}"#
    )
}

fn flagged_prompt(flags: &str, text: &str) -> String {
    format!(
        r#"{{"type":"user",{flags},"sessionId":"s","cwd":"/w","isSidechain":false,"message":{{"role":"user","content":"{text}"}}}}"#
    )
}

const BOUNDARY: &str = r#"{"type":"system","subtype":"compact_boundary","sessionId":"s","compactMetadata":{"trigger":"manual","preTokens":697000,"postTokens":36000}}"#;

fn turns(text: &str) -> Vec<u64> {
    parse(text, &hasher())
        .requests
        .iter()
        .map(|r| r.turn)
        .collect()
}

#[test]
fn the_compact_summary_record_is_not_a_prompt() {
    let text = [
        prompt("first"),
        assistant("r1"),
        BOUNDARY.to_owned(),
        flagged_prompt(
            r#""isCompactSummary":true,"isVisibleInTranscriptOnly":true"#,
            "summary",
        ),
        assistant("r2"),
        prompt("second"),
        assistant("r3"),
    ]
    .join("\n");
    assert_eq!(turns(&text), vec![1, 1, 2]);
}

#[test]
fn a_meta_user_record_is_not_a_prompt() {
    let text = [
        prompt("first"),
        assistant("r1"),
        flagged_prompt(r#""isMeta":true"#, "caveat"),
        assistant("r2"),
        prompt("second"),
        assistant("r3"),
    ]
    .join("\n");
    assert_eq!(turns(&text), vec![1, 1, 2]);
}

#[test]
fn a_leading_meta_record_does_not_become_the_first_prompt() {
    let text = [
        flagged_prompt(r#""isMeta":true"#, "caveat caveat caveat"),
        prompt("hi"),
        assistant("r1"),
    ]
    .join("\n");
    let parsed = parse(&text, &hasher());
    assert_eq!(parsed.first_prompt_chars, 2);
}
