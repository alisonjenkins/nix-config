#![allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]

use cc_obs_ledger::transcript::{parse, parse_from, read_unread, Position, ToolHasher};

const FIXTURE: &str = include_str!("fixtures/transcript.jsonl");

fn hasher() -> ToolHasher {
    ToolHasher::new(b"test-key".to_vec())
}

fn request<'a>(
    parsed: &'a cc_obs_ledger::transcript::Parsed,
    id: &str,
) -> &'a cc_obs_ledger::transcript::Request {
    parsed.requests.iter().find(|r| r.request_id == id).unwrap()
}

#[test]
fn counts_each_request_once_although_its_usage_repeats_on_every_block() {
    let parsed = parse(FIXTURE, &hasher());
    assert_eq!(parsed.requests.len(), 3);
    let a = request(&parsed, "req-A");
    assert_eq!(a.usage.input, 10);
    assert_eq!(a.usage.output, 50);
    assert_eq!(a.usage.cache_read, 20_000);
    assert_eq!(a.usage.cache_creation, 5_000);
}

#[test]
fn session_totals_sum_unique_requests() {
    let parsed = parse(FIXTURE, &hasher());
    let total = parsed.total_usage();
    assert_eq!(total.input, 25);
    assert_eq!(total.output, 89);
    assert_eq!(total.cache_read, 49_000);
    assert_eq!(total.cache_creation, 5_200);
}

#[test]
fn context_size_and_cache_hit_ratio_per_request() {
    let parsed = parse(FIXTURE, &hasher());
    let a = request(&parsed, "req-A");
    assert_eq!(a.usage.context_tokens(), 25_010);
    let ratio = a.usage.cache_hit_ratio().unwrap();
    assert!((ratio - 20_000.0 / 25_010.0).abs() < 1e-9, "ratio {ratio}");
}

#[test]
fn an_empty_request_has_no_cache_hit_ratio() {
    let usage = cc_obs_ledger::transcript::Usage::default();
    assert_eq!(usage.cache_hit_ratio(), None);
}

#[test]
fn sub_agent_requests_are_flagged() {
    let parsed = parse(FIXTURE, &hasher());
    assert!(!request(&parsed, "req-A").sidechain);
    assert!(request(&parsed, "req-C").sidechain);
}

#[test]
fn requests_carry_the_prompt_turn_and_project() {
    let parsed = parse(FIXTURE, &hasher());
    let b = request(&parsed, "req-B");
    assert_eq!(b.turn, 1);
    assert_eq!(b.session_id, "sess-1");
    assert_eq!(b.project, "proj");
    assert_eq!(b.model, "claude-sonnet-5-5");
}

#[test]
fn a_line_that_is_not_json_is_skipped_and_counted() {
    let parsed = parse(FIXTURE, &hasher());
    assert_eq!(parsed.skipped_lines, 1);
}

#[test]
fn tool_calls_record_sizes_and_the_result_size() {
    let parsed = parse(FIXTURE, &hasher());
    assert_eq!(parsed.tool_calls.len(), 2);
    let first = &parsed.tool_calls[0];
    assert_eq!(first.name, "Read");
    assert_eq!(first.request_id, "req-A");
    assert!(first.input_bytes > 0);
    assert_eq!(
        first.result_bytes,
        Some("CANARY-7f3a file body that is 41 bytes long.".len() as u64)
    );
    assert_eq!(first.prompt_id.as_deref(), Some("prompt-1"));
    assert_eq!(parsed.tool_calls[1].result_bytes, None);
    assert!(parsed.tool_calls[1].sidechain);
}

#[test]
fn identical_inputs_hash_alike_and_the_key_changes_the_hash() {
    let parsed = parse(FIXTURE, &hasher());
    assert_eq!(
        parsed.tool_calls[0].input_hash,
        parsed.tool_calls[1].input_hash
    );
    assert_eq!(parsed.tool_calls[0].input_hash.len(), 16);
    let other = parse(FIXTURE, &ToolHasher::new(b"other-key".to_vec()));
    assert_ne!(
        parsed.tool_calls[0].input_hash,
        other.tool_calls[0].input_hash
    );
}

#[test]
fn near_identical_inputs_share_the_prefix_hash_only() {
    let line = |id: &str, path: &str| {
        format!(
            r#"{{"type":"assistant","sessionId":"s","requestId":"r-{id}","cwd":"/w/p","isSidechain":false,"message":{{"id":"m-{id}","model":"m","content":[{{"type":"tool_use","id":"t-{id}","name":"Read","input":{{"file_path":"{path}"}}}}],"usage":{{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}}}}"#
        )
    };
    let text = format!(
        "{}\n{}\n",
        line(
            "1",
            "/work/some/long/path/that/is/shared/by/both/calls/a.rs"
        ),
        line(
            "2",
            "/work/some/long/path/that/is/shared/by/both/calls/b.rs"
        )
    );
    let parsed = parse(&text, &hasher());
    assert_ne!(
        parsed.tool_calls[0].input_hash,
        parsed.tool_calls[1].input_hash
    );
    assert_eq!(
        parsed.tool_calls[0].input_prefix_hash,
        parsed.tool_calls[1].input_prefix_hash
    );
}

#[test]
fn an_unfinished_last_line_is_left_for_the_next_read() {
    let bytes = b"{\"type\":\"user\"}\n{\"type\":\"assis";
    let complete = cc_obs_ledger::transcript::complete_lines(bytes);
    assert_eq!(complete, b"{\"type\":\"user\"}\n");
}

#[test]
fn an_invalid_byte_does_not_change_how_many_raw_bytes_a_complete_line_covers() {
    let bytes = b"{\"type\":\"user\",\"x\":\"\xff\"}\n{\"type\":\"assis";
    let complete = cc_obs_ledger::transcript::complete_lines(bytes);
    assert_eq!(complete.len(), 24);
    assert_eq!(complete.last(), Some(&b'\n'));
}

fn two_prompt_transcript() -> String {
    let user = |text: &str| {
        format!(
            r#"{{"type":"user","sessionId":"s","promptId":"p","cwd":"/w/p","message":{{"role":"user","content":"{text}"}}}}"#
        )
    };
    let tool = |n: u32| {
        format!(
            r#"{{"type":"assistant","sessionId":"s","requestId":"r-{n}","cwd":"/w/p","isSidechain":false,"message":{{"id":"m-{n}","model":"m","content":[{{"type":"tool_use","id":"t-{n}","name":"Read","input":{{"n":{n}}}}}],"usage":{{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}}}}"#
        )
    };
    [user("one"), tool(1), tool(2), user("two"), tool(3)].join("\n") + "\n"
}

#[test]
fn parsing_in_two_parts_continues_turn_and_seq_like_parsing_once() {
    let text = two_prompt_transcript();
    let whole = parse(&text, &hasher());
    let split = text.match_indices('\n').nth(1).unwrap().0 + 1;
    let first = parse_from(&text[..split], &hasher(), Position::default());
    let second = parse_from(&text[split..], &hasher(), first.end);

    let mut calls = first.tool_calls.clone();
    calls.extend(second.tool_calls.clone());
    assert_eq!(calls, whole.tool_calls);
    assert_eq!(
        calls.iter().map(|c| (c.turn, c.seq)).collect::<Vec<_>>(),
        vec![(1, 0), (1, 1), (2, 2)]
    );
    assert_eq!(second.end, whole.end);
    assert_eq!(second.requests[0].turn, 1);
    assert_eq!(second.requests[0].request_id, "r-2");
}

#[test]
fn reading_only_the_newest_part_starts_on_a_line_boundary_and_reports_the_skip() {
    let data = b"aaaa\nbbbb\ncccc\ndddd\n".to_vec();
    let mut cursor = std::io::Cursor::new(data.clone());
    let tail = read_unread(&mut cursor, 0, 12).unwrap();
    assert_eq!(tail.bytes, b"cccc\ndddd\n");
    assert_eq!(tail.skipped, 10);

    let mut cursor = std::io::Cursor::new(data.clone());
    let tail = read_unread(&mut cursor, 0, 100).unwrap();
    assert_eq!(tail.bytes, data);
    assert_eq!(tail.skipped, 0);

    // The cut lands exactly on a line start: nothing extra is dropped.
    let mut cursor = std::io::Cursor::new(data);
    let tail = read_unread(&mut cursor, 0, 10).unwrap();
    assert_eq!(tail.bytes, b"cccc\ndddd\n");
    assert_eq!(tail.skipped, 10);
}
