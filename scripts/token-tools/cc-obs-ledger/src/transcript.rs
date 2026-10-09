//! Reads a Claude Code session transcript (JSON lines) into per-request token
//! usage and per-tool-call sizes. Findings from the S3 spike
//! (specs/007-local-observability-stack/research.md): one API request is written
//! as several `assistant` lines that repeat the same `usage`, so a request is
//! counted once, by `requestId`.

use std::collections::{HashMap, HashSet};
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

use hmac::{Hmac, Mac};
use serde_json::Value;
use sha2::{Digest, Sha256};

type HmacSha256 = Hmac<Sha256>;

/// Bytes of the canonical tool input that the "near-identical call" hash covers.
const PREFIX_BYTES: usize = 64;
/// Hex characters kept from a digest: enough to tell calls apart, short to store.
const HASH_HEX_CHARS: usize = 16;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Usage {
    pub input: u64,
    pub output: u64,
    pub cache_read: u64,
    pub cache_creation: u64,
}

impl Usage {
    /// Tokens sent to the model on this request.
    pub fn context_tokens(&self) -> u64 {
        self.input
            .saturating_add(self.cache_read)
            .saturating_add(self.cache_creation)
    }

    pub fn cache_hit_ratio(&self) -> Option<f64> {
        let total = self.context_tokens();
        if total == 0 {
            return None;
        }
        Some(self.cache_read as f64 / total as f64)
    }

    fn add(&mut self, other: &Usage) {
        self.input = self.input.saturating_add(other.input);
        self.output = self.output.saturating_add(other.output);
        self.cache_read = self.cache_read.saturating_add(other.cache_read);
        self.cache_creation = self.cache_creation.saturating_add(other.cache_creation);
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Request {
    pub request_id: String,
    pub session_id: String,
    pub project: String,
    pub model: String,
    pub sidechain: bool,
    /// 1-based user prompt this request belongs to; 0 before the first prompt.
    pub turn: u64,
    pub usage: Usage,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ToolCall {
    pub tool_use_id: String,
    pub name: String,
    pub request_id: String,
    pub session_id: String,
    pub sidechain: bool,
    pub turn: u64,
    /// Position of the call in the whole session, not just this parse.
    pub seq: u64,
    pub input_bytes: u64,
    pub input_hash: String,
    pub input_prefix_hash: String,
    pub result_bytes: Option<u64>,
    pub prompt_id: Option<String>,
}

#[derive(Debug, Default)]
pub struct Parsed {
    pub requests: Vec<Request>,
    pub tool_calls: Vec<ToolCall>,
    /// Lines that were not JSON.
    pub skipped_lines: usize,
    /// Characters in the first user prompt, to subtract from the first request's context.
    pub first_prompt_chars: u64,
    /// Turn and tool-call counters after the last line parsed.
    pub end: Position,
}

impl Parsed {
    pub fn total_usage(&self) -> Usage {
        let mut total = Usage::default();
        for request in &self.requests {
            total.add(&request.usage);
        }
        total
    }
}

/// Keyed one-way hash of tool inputs. The key stays on the machine, so a hash
/// cannot be reversed by guessing common inputs.
pub struct ToolHasher {
    key: Vec<u8>,
}

impl ToolHasher {
    pub fn new(key: Vec<u8>) -> Self {
        Self { key }
    }

    pub fn hash(&self, data: &[u8]) -> String {
        let digest = match HmacSha256::new_from_slice(&self.key) {
            Ok(mut mac) => {
                mac.update(data);
                mac.finalize().into_bytes().to_vec()
            }
            // HMAC accepts any key length, so this arm cannot run; hashing key and data
            // together keeps the function total without a panic path.
            Err(_) => Sha256::new()
                .chain_update(&self.key)
                .chain_update(data)
                .finalize()
                .to_vec(),
        };
        let hex: String = digest.iter().map(|byte| format!("{byte:02x}")).collect();
        hex.chars().take(HASH_HEX_CHARS).collect()
    }
}

/// The part of `bytes` that ends in a newline. A final line still being written
/// is left for the next read. Works on raw bytes so the length it returns is the
/// number of bytes to advance a file offset by, whatever the encoding.
pub fn complete_lines(bytes: &[u8]) -> &[u8] {
    match bytes.iter().rposition(|byte| *byte == b'\n') {
        Some(index) => bytes.get(..index.saturating_add(1)).unwrap_or_default(),
        None => &[],
    }
}

/// The unread part of a transcript, possibly cut to its newest lines.
#[derive(Debug)]
pub struct Unread {
    pub bytes: Vec<u8>,
    /// Bytes between the start offset and `bytes` that were not read.
    pub skipped: u64,
}

/// Reads from `start` to the end. If more than `limit` bytes are unread, only the
/// newest whole lines within `limit` are returned, so a huge backlog cannot make
/// the hook outlive its timeout.
pub fn read_unread<R: Read + Seek>(
    reader: &mut R,
    start: u64,
    limit: u64,
) -> std::io::Result<Unread> {
    let length = reader.seek(SeekFrom::End(0))?;
    let unread = length.saturating_sub(start);
    if unread <= limit {
        reader.seek(SeekFrom::Start(start))?;
        let mut bytes = Vec::new();
        reader.read_to_end(&mut bytes)?;
        return Ok(Unread { bytes, skipped: 0 });
    }
    // One byte before the cut: if it is a newline the cut is already on a line start.
    let from = length.saturating_sub(limit).saturating_sub(1);
    reader.seek(SeekFrom::Start(from))?;
    let mut bytes = Vec::new();
    reader.read_to_end(&mut bytes)?;
    let drop = bytes
        .iter()
        .position(|byte| *byte == b'\n')
        .map_or(bytes.len(), |index| index.saturating_add(1));
    bytes.drain(..drop);
    let skipped = length
        .saturating_sub(start)
        .saturating_sub(bytes.len() as u64);
    Ok(Unread { bytes, skipped })
}

/// Where a parse stopped, so the next one numbers turns and tool calls on from it.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Position {
    pub turn: u64,
    pub seq: u64,
}

pub fn parse(text: &str, hasher: &ToolHasher) -> Parsed {
    parse_from(text, hasher, Position::default())
}

pub fn parse_from(text: &str, hasher: &ToolHasher, start: Position) -> Parsed {
    let mut parsed = Parsed::default();
    let mut seen_requests: HashSet<String> = HashSet::new();
    let mut tool_index: HashMap<String, usize> = HashMap::new();
    let mut turn: u64 = start.turn;
    let mut seq: u64 = start.seq;

    for line in text.lines().filter(|line| !line.trim().is_empty()) {
        let Ok(value) = serde_json::from_str::<Value>(line) else {
            parsed.skipped_lines = parsed.skipped_lines.saturating_add(1);
            continue;
        };
        match value.get("type").and_then(Value::as_str) {
            Some("user") => read_user(&value, &mut parsed, &mut turn, &tool_index),
            Some("assistant") => read_assistant(
                &value,
                &mut parsed,
                turn,
                &mut seen_requests,
                &mut tool_index,
                &mut seq,
                hasher,
            ),
            _ => {}
        }
    }
    parsed.end = Position { turn, seq };
    parsed
}

fn read_user(
    value: &Value,
    parsed: &mut Parsed,
    turn: &mut u64,
    tool_index: &HashMap<String, usize>,
) {
    let Some(content) = value.pointer("/message/content") else {
        return;
    };
    let items: Vec<&Value> = match content {
        Value::String(_) => {
            start_turn(content.as_str().map_or(0, str::len), parsed, turn);
            return;
        }
        Value::Array(items) => items.iter().collect(),
        _ => return,
    };
    let prompt_id = value.get("promptId").and_then(Value::as_str);
    let mut prompt_chars = 0usize;
    for item in items {
        match item.get("type").and_then(Value::as_str) {
            Some("tool_result") => {
                let Some(id) = item.get("tool_use_id").and_then(Value::as_str) else {
                    continue;
                };
                let Some(call) = tool_index
                    .get(id)
                    .and_then(|index| parsed.tool_calls.get_mut(*index))
                else {
                    continue;
                };
                call.result_bytes = Some(result_size(item.get("content")));
                call.prompt_id = prompt_id.map(str::to_owned);
            }
            Some("text") => {
                let text_len = item.get("text").and_then(Value::as_str).map_or(0, str::len);
                prompt_chars = prompt_chars.saturating_add(text_len);
            }
            _ => {}
        }
    }
    if prompt_chars > 0 {
        start_turn(prompt_chars, parsed, turn);
    }
}

fn start_turn(chars: usize, parsed: &mut Parsed, turn: &mut u64) {
    if *turn == 0 {
        parsed.first_prompt_chars = chars as u64;
    }
    *turn = turn.saturating_add(1);
}

fn result_size(content: Option<&Value>) -> u64 {
    match content {
        Some(Value::String(text)) => text.len() as u64,
        Some(Value::Array(items)) => items
            .iter()
            .map(|item| match item.get("text").and_then(Value::as_str) {
                Some(text) => text.len() as u64,
                None => item.to_string().len() as u64,
            })
            .fold(0u64, u64::saturating_add),
        Some(other) => other.to_string().len() as u64,
        None => 0,
    }
}

fn read_assistant(
    value: &Value,
    parsed: &mut Parsed,
    turn: u64,
    seen_requests: &mut HashSet<String>,
    tool_index: &mut HashMap<String, usize>,
    seq: &mut u64,
    hasher: &ToolHasher,
) {
    let Some(request_id) = value.get("requestId").and_then(Value::as_str) else {
        return;
    };
    let session_id = value
        .get("sessionId")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_owned();
    let sidechain = value
        .get("isSidechain")
        .and_then(Value::as_bool)
        .unwrap_or(false);

    if seen_requests.insert(request_id.to_owned()) {
        let usage = value
            .pointer("/message/usage")
            .map(read_usage)
            .unwrap_or_default();
        parsed.requests.push(Request {
            request_id: request_id.to_owned(),
            session_id: session_id.clone(),
            project: value
                .get("cwd")
                .and_then(Value::as_str)
                .and_then(|cwd| Path::new(cwd).file_name())
                .map(|name| name.to_string_lossy().into_owned())
                .unwrap_or_default(),
            model: value
                .pointer("/message/model")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_owned(),
            sidechain,
            turn,
            usage,
        });
    }

    let Some(items) = value.pointer("/message/content").and_then(Value::as_array) else {
        return;
    };
    for item in items {
        if item.get("type").and_then(Value::as_str) != Some("tool_use") {
            continue;
        }
        let (Some(id), Some(name)) = (
            item.get("id").and_then(Value::as_str),
            item.get("name").and_then(Value::as_str),
        ) else {
            continue;
        };
        if tool_index.contains_key(id) {
            continue;
        }
        let canonical = item.get("input").map(Value::to_string).unwrap_or_default();
        let bytes = canonical.as_bytes();
        let prefix = bytes.get(..PREFIX_BYTES).unwrap_or(bytes);
        tool_index.insert(id.to_owned(), parsed.tool_calls.len());
        parsed.tool_calls.push(ToolCall {
            tool_use_id: id.to_owned(),
            name: name.to_owned(),
            request_id: request_id.to_owned(),
            session_id: session_id.clone(),
            sidechain,
            turn,
            seq: *seq,
            input_bytes: bytes.len() as u64,
            input_hash: hasher.hash(bytes),
            input_prefix_hash: hasher.hash(prefix),
            result_bytes: None,
            prompt_id: None,
        });
        *seq = seq.saturating_add(1);
    }
}

fn read_usage(usage: &Value) -> Usage {
    let field = |name: &str| usage.get(name).and_then(Value::as_u64).unwrap_or(0);
    Usage {
        input: field("input_tokens"),
        output: field("output_tokens"),
        cache_read: field("cache_read_input_tokens"),
        cache_creation: field("cache_creation_input_tokens"),
    }
}
