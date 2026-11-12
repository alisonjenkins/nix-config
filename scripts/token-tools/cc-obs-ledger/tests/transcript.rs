#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]

use cc_obs_ledger::image::{image_dimensions, image_tokens, FALLBACK_IMAGE_TOKENS};
use cc_obs_ledger::otlp::{turn_payloads, Resource};
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
fn tool_input_hash_is_the_first_sixteen_hex_digits_of_hmac_sha256() {
    // RFC 4231 test case 2: key "Jefe", data "what do ya want for nothing?".
    let known = ToolHasher::new(b"Jefe".to_vec()).hash(b"what do ya want for nothing?");
    assert_eq!(known, "5bdcc146bf60754e");
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

fn encode_base64(bytes: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let b0 = chunk[0];
        let b1 = *chunk.get(1).unwrap_or(&0);
        let b2 = *chunk.get(2).unwrap_or(&0);
        out.push(TABLE[(b0 >> 2) as usize] as char);
        out.push(TABLE[(((b0 & 0x03) << 4) | (b1 >> 4)) as usize] as char);
        if chunk.len() > 1 {
            out.push(TABLE[(((b1 & 0x0f) << 2) | (b2 >> 6)) as usize] as char);
        } else {
            out.push('=');
        }
        if chunk.len() > 2 {
            out.push(TABLE[(b2 & 0x3f) as usize] as char);
        } else {
            out.push('=');
        }
    }
    out
}

fn tiny_png(width: u32, height: u32) -> Vec<u8> {
    let mut bytes = vec![
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
        0x00, 0x00, 0x00, 0x0D, // IHDR length (13)
        b'I', b'H', b'D', b'R',
    ];
    bytes.extend_from_slice(&width.to_be_bytes());
    bytes.extend_from_slice(&height.to_be_bytes());
    bytes.extend_from_slice(&[8, 2, 0, 0, 0, 0, 0, 0, 0]);
    bytes
}

fn tiny_jpeg(width: u16, height: u16) -> Vec<u8> {
    let mut bytes = vec![
        0xFF, 0xD8, // SOI
        0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00, // APP0 segment (length 4)
        0xFF, 0xC4, 0x00, 0x04, 0x00, 0x00, // DHT (0xC4, must be skipped)
        0xFF, 0xC0, 0x00, 0x0B, 0x08, // SOF0 header + precision
    ];
    bytes.extend_from_slice(&height.to_be_bytes());
    bytes.extend_from_slice(&width.to_be_bytes());
    bytes.extend_from_slice(&[0x01, 0x01, 0x11, 0x00, 0xFF, 0xD9]);
    bytes
}

#[test]
fn image_tokens_scales_down_within_limits_and_rounds_up() {
    assert_eq!(image_tokens(1000, 1000), 1334);
    assert_eq!(image_tokens(3000, 2000), 1534);
    assert_eq!(image_tokens(10, 10), 1);
    assert_eq!(image_tokens(0, 100), 0);
}

#[test]
fn image_dimensions_reads_png_jpeg_gif_and_webp_headers() {
    let png_b64 = encode_base64(&tiny_png(1280, 720));
    assert_eq!(image_dimensions(&png_b64), Some((1280, 720)));

    let jpeg_b64 = encode_base64(&tiny_jpeg(640, 480));
    assert_eq!(image_dimensions(&jpeg_b64), Some((640, 480)));

    let mut gif = b"GIF89a".to_vec();
    gif.extend_from_slice(&320u16.to_le_bytes());
    gif.extend_from_slice(&240u16.to_le_bytes());
    assert_eq!(image_dimensions(&encode_base64(&gif)), Some((320, 240)));

    let mut webp = Vec::new();
    webp.extend_from_slice(b"RIFF");
    webp.extend_from_slice(&22u32.to_le_bytes());
    webp.extend_from_slice(b"WEBPVP8X");
    webp.extend_from_slice(&10u32.to_le_bytes());
    webp.extend_from_slice(&0u32.to_le_bytes());
    // 24-bit LE width-1 (799 -> 800) and height-1 (599 -> 600)
    webp.extend_from_slice(&[0x1F, 0x03, 0x00, 0x57, 0x02, 0x00]);
    assert_eq!(image_dimensions(&encode_base64(&webp)), Some((800, 600)));
}

#[test]
fn image_dimensions_returns_none_on_truncated_or_garbage_input() {
    assert_eq!(image_dimensions(""), None);
    assert_eq!(image_dimensions("abc"), None);
    assert_eq!(image_dimensions("not!base64!!"), None);
    assert_eq!(image_dimensions(&encode_base64(b"plain text file")), None);
    assert_eq!(
        image_dimensions(&encode_base64(&tiny_png(100, 100)[..18])),
        None
    );
    assert_eq!(
        image_dimensions(&encode_base64(&tiny_jpeg(100, 100)[..16])),
        None
    );
    // Zero-length JPEG segment must not loop.
    assert_eq!(
        image_dimensions(&encode_base64(&[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x00])),
        None
    );
}

#[test]
fn tool_result_with_text_and_image_records_image_count_bytes_and_tokens() {
    let png_b64 = encode_base64(&tiny_png(1000, 1000));
    let image_item = serde_json::json!({
        "type": "image",
        "source": {
            "type": "base64",
            "media_type": "image/png",
            "data": png_b64,
        }
    });
    let expected_image_bytes = image_item.to_string().len() as u64;
    let assistant = serde_json::json!({
        "type": "assistant",
        "sessionId": "s",
        "requestId": "r-1",
        "cwd": "/w/p",
        "isSidechain": false,
        "message": {
            "id": "m-1",
            "model": "m",
            "content": [{"type": "tool_use", "id": "t-1", "name": "Read", "input": {"file_path": "/w/p/img.png"}}],
            "usage": {"input_tokens": 1, "output_tokens": 1, "cache_read_input_tokens": 0, "cache_creation_input_tokens": 0}
        }
    });
    let user = serde_json::json!({
        "type": "user",
        "sessionId": "s",
        "promptId": "p-1",
        "cwd": "/w/p",
        "message": {
            "role": "user",
            "content": [{
                "type": "tool_result",
                "tool_use_id": "t-1",
                "content": [
                    {"type": "text", "text": "caption"},
                    image_item,
                ]
            }]
        }
    });
    let text = format!("{assistant}\n{user}\n");
    let parsed = parse(&text, &hasher());
    assert_eq!(parsed.tool_calls.len(), 1);
    let call = &parsed.tool_calls[0];
    assert_eq!(call.result_image_count, 1);
    assert_eq!(call.result_image_bytes, expected_image_bytes);
    assert_eq!(call.result_image_tokens, 1334);
    assert_eq!(
        call.result_bytes,
        Some("caption".len() as u64 + expected_image_bytes)
    );

    let payloads = turn_payloads(&Resource::new("h", &[]), &parsed);
    let logs = payloads
        .iter()
        .find_map(|p| p.body.pointer("/resourceLogs/0/scopeLogs/0/logRecords/0"))
        .unwrap();
    let attrs = logs["attributes"].as_array().unwrap();
    let int_attr = |key: &str| {
        attrs
            .iter()
            .find(|a| a["key"] == key)
            .and_then(|a| a["value"]["intValue"].as_str())
    };
    assert_eq!(int_attr("result_image_count"), Some("1"));
    assert_eq!(
        int_attr("result_image_bytes"),
        Some(expected_image_bytes.to_string()).as_deref()
    );
    assert_eq!(int_attr("result_image_tokens"), Some("1334"));

    // Non-image tool calls omit the image attributes.
    let fixture_parsed = parse(FIXTURE, &hasher());
    let fixture_payloads = turn_payloads(&Resource::new("h", &[]), &fixture_parsed);
    let fixture_logs = fixture_payloads
        .iter()
        .find_map(|p| p.body.pointer("/resourceLogs/0/scopeLogs/0/logRecords/0"))
        .unwrap();
    let fixture_attrs = fixture_logs["attributes"].as_array().unwrap();
    assert!(fixture_attrs
        .iter()
        .all(|a| a["key"] != "result_image_count"));

    // Unknown image dimensions fall back to FALLBACK_IMAGE_TOKENS.
    let bad_user = serde_json::json!({
        "type": "user",
        "sessionId": "s",
        "message": {
            "role": "user",
            "content": [{
                "type": "tool_result",
                "tool_use_id": "t-1",
                "content": [{"type": "image", "source": {"type": "base64", "data": "AAAA"}}]
            }]
        }
    });
    let bad_parsed = parse(&format!("{assistant}\n{bad_user}\n"), &hasher());
    assert_eq!(
        bad_parsed.tool_calls[0].result_image_tokens,
        FALLBACK_IMAGE_TOKENS
    );
}
