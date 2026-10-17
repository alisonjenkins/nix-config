//! Reads a Claude Code session transcript (JSON lines) into per-request token
//! usage and per-tool-call sizes. Findings from the S3 spike
//! (specs/007-local-observability-stack/research.md): one API request is written
//! as several `assistant` lines that repeat the same `usage`, so a request is
//! counted once, by `requestId`.

use std::collections::{BTreeSet, HashMap, HashSet};
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use hmac::{Hmac, KeyInit, Mac};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use time::format_description::well_known::Rfc3339;
use time::OffsetDateTime;

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
    /// The line carried a `cache_creation_input_tokens` count (zero is a real count).
    pub cache_creation_reported: bool,
    /// Seconds since the previous request of the same agent kind (main or subagent)
    /// in this session; `None` for the first request or when a timestamp is missing.
    pub seconds_since_prev: Option<u64>,
    /// Set by the `subagent` hook; `None` for the main agent.
    pub agent_id: Option<String>,
}

/// One entry of the skill listing the session started with.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ListedSkill {
    pub name: String,
    /// Characters the entry adds to the listing, name and description included.
    pub chars: u64,
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
    /// Set by the `subagent` hook; `None` for the main agent.
    pub agent_id: Option<String>,
    /// Fixed-vocabulary label of a Bash command; never its text.
    pub command_shape: Option<String>,
}

impl Parsed {
    /// Tags every request and tool call with the sub-agent that made them.
    pub fn set_agent_id(&mut self, agent_id: &str) {
        for request in &mut self.requests {
            request.agent_id = Some(agent_id.to_owned());
        }
        for call in &mut self.tool_calls {
            call.agent_id = Some(agent_id.to_owned());
        }
    }
}

#[derive(Debug, Default)]
pub struct Parsed {
    pub requests: Vec<Request>,
    pub tool_calls: Vec<ToolCall>,
    /// Lines that were not JSON.
    pub skipped_lines: usize,
    /// Characters in the first user prompt, to subtract from the first request's context.
    pub first_prompt_chars: u64,
    /// The newest `skill_listing` attachment in this parse, if there was one.
    pub skill_listing: Option<Vec<ListedSkill>>,
    /// MCP servers named by `mcp_instructions_delta` attachments in this parse (added
    /// minus removed); `None` when the parse held no such attachment.
    pub mcp_servers: Option<BTreeSet<String>>,
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
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Position {
    pub turn: u64,
    pub seq: u64,
    /// Unix milliseconds of the newest main-agent request, for the next gap.
    pub last_main_ms: Option<u64>,
    /// Unix milliseconds of the newest subagent request.
    pub last_sub_ms: Option<u64>,
    /// Running request totals, so the counter can be sent cumulative.
    pub request_series: Vec<RequestSeries>,
}

/// Running request count of one (session, project, model, agent kind) series. The
/// sub-agent id is not part of it: a sub-agent cursor belongs to one agent file.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RequestSeries {
    pub session_id: String,
    pub project: String,
    pub model: String,
    pub sidechain: bool,
    pub total: u64,
    /// Unix nanoseconds of the first send; fixed so the counter never looks reset.
    pub start_ns: u64,
}

impl RequestSeries {
    pub fn matches(&self, request: &Request) -> bool {
        self.session_id == request.session_id
            && self.project == request.project
            && self.model == request.model
            && self.sidechain == request.sidechain
    }
}

fn now_ns() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |elapsed| {
            u64::try_from(elapsed.as_nanos()).unwrap_or(u64::MAX)
        })
}

fn count_requests(series: &mut Vec<RequestSeries>, requests: &[Request]) {
    for request in requests {
        if let Some(found) = series.iter_mut().find(|s| s.matches(request)) {
            found.total = found.total.saturating_add(1);
        } else {
            series.push(RequestSeries {
                session_id: request.session_id.clone(),
                project: request.project.clone(),
                model: request.model.clone(),
                sidechain: request.sidechain,
                total: 1,
                start_ns: now_ns(),
            });
        }
    }
}

/// Unix milliseconds of an RFC 3339 transcript timestamp.
fn timestamp_ms(value: &Value) -> Option<u64> {
    let text = value.get("timestamp")?.as_str()?;
    let parsed = OffsetDateTime::parse(text, &Rfc3339).ok()?;
    u64::try_from(parsed.unix_timestamp_nanos() / 1_000_000).ok()
}

fn read_attachment(value: &Value, parsed: &mut Parsed) {
    let Some(attachment) = value.get("attachment") else {
        return;
    };
    match attachment.get("type").and_then(Value::as_str) {
        Some("skill_listing") => {
            if let Some(content) = attachment.get("content").and_then(Value::as_str) {
                let listed = listed_skills(content);
                // Claude Code re-emits `skill_listing` with `isInitial: false` for skills
                // found later (nested `.claude/skills`); those add to the initial list.
                let is_delta = attachment.get("isInitial").and_then(Value::as_bool) == Some(false);
                match (&mut parsed.skill_listing, is_delta) {
                    (Some(existing), true) => {
                        existing.retain(|old| !listed.iter().any(|new| new.name == old.name));
                        existing.extend(listed);
                    }
                    (slot, _) => *slot = Some(listed),
                }
            }
        }
        Some("mcp_instructions_delta") => {
            let servers = parsed.mcp_servers.get_or_insert_with(BTreeSet::new);
            let names = |key: &str| {
                attachment
                    .get(key)
                    .and_then(Value::as_array)
                    .into_iter()
                    .flatten()
                    .filter_map(Value::as_str)
                    .map(str::to_owned)
                    .collect::<Vec<_>>()
            };
            servers.extend(names("addedNames"));
            for name in names("removedNames") {
                servers.remove(&name);
            }
        }
        _ => {}
    }
}

/// Entries of the form `- name: description`; a line that starts no entry belongs
/// to the entry before it.
fn listed_skills(content: &str) -> Vec<ListedSkill> {
    let mut skills: Vec<ListedSkill> = Vec::new();
    for line in content.lines() {
        let entry_name = line
            .strip_prefix("- ")
            .and_then(|rest| rest.split_once(": "))
            .map(|(name, _)| name.trim())
            .filter(|name| !name.is_empty());
        match (entry_name, skills.last_mut()) {
            (Some(name), _) => skills.push(ListedSkill {
                name: name.to_owned(),
                chars: line.chars().count() as u64,
            }),
            (None, Some(last)) => {
                // The newline that `lines()` removed counts as a character.
                last.chars = last
                    .chars
                    .saturating_add(1)
                    .saturating_add(line.chars().count() as u64);
            }
            (None, None) => {}
        }
    }
    skills
}

pub fn parse(text: &str, hasher: &ToolHasher) -> Parsed {
    parse_from(text, hasher, Position::default())
}

pub fn parse_from(text: &str, hasher: &ToolHasher, start: Position) -> Parsed {
    let mut parsed = Parsed::default();
    let mut seen_requests: HashSet<String> = HashSet::new();
    let mut tool_index: HashMap<String, usize> = HashMap::new();
    let mut turn: u64 = start.turn;
    let mut counters = Counters {
        seq: start.seq,
        last_main_ms: start.last_main_ms,
        last_sub_ms: start.last_sub_ms,
    };

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
                &mut counters,
                hasher,
            ),
            Some("attachment") => read_attachment(&value, &mut parsed),
            _ => {}
        }
    }
    let mut request_series = start.request_series;
    count_requests(&mut request_series, &parsed.requests);
    parsed.end = Position {
        turn,
        seq: counters.seq,
        last_main_ms: counters.last_main_ms,
        last_sub_ms: counters.last_sub_ms,
        request_series,
    };
    parsed
}

/// Counters that run on across lines, and across Stop hooks through `Position`.
struct Counters {
    seq: u64,
    last_main_ms: Option<u64>,
    last_sub_ms: Option<u64>,
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
    // Claude Code writes caveats, skill bodies and the /compact summary as user
    // records; none of them is something the person typed.
    let synthetic = ["isMeta", "isCompactSummary"]
        .iter()
        .any(|flag| value.get(flag).and_then(Value::as_bool) == Some(true));
    let items: Vec<&Value> = match content {
        Value::String(_) => {
            let text = content.as_str().unwrap_or_default();
            if !synthetic && !is_system_text(text) {
                start_turn(text.len(), parsed, turn);
            }
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
                let text = item.get("text").and_then(Value::as_str).unwrap_or_default();
                if !is_system_text(text) {
                    prompt_chars = prompt_chars.saturating_add(text.len());
                }
            }
            _ => {}
        }
    }
    if prompt_chars > 0 && !synthetic {
        start_turn(prompt_chars, parsed, turn);
    }
}

/// Text prefixes of user records that are system events, not prompts; a
/// `<task-notification>` is a background-task wake-up and does not count as a turn.
const SYSTEM_TEXT_PREFIXES: [&str; 8] = [
    "[Request interrupted",
    "<command-name>",
    "<command-message>",
    "<command-args>",
    "<local-command-stdout>",
    "<local-command-stderr>",
    "<local-command-caveat>",
    "<task-notification>",
];

fn is_system_text(text: &str) -> bool {
    let start = text.trim_start();
    SYSTEM_TEXT_PREFIXES
        .iter()
        .any(|prefix| start.starts_with(prefix))
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
    counters: &mut Counters,
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
        let cache_creation_reported = value
            .pointer("/message/usage/cache_creation_input_tokens")
            .is_some_and(Value::is_u64);
        let now_ms = timestamp_ms(value);
        let last_ms = if sidechain {
            &mut counters.last_sub_ms
        } else {
            &mut counters.last_main_ms
        };
        let seconds_since_prev = match (now_ms, *last_ms) {
            (Some(now), Some(prev)) => Some(now.saturating_sub(prev) / 1000),
            _ => None,
        };
        if now_ms.is_some() {
            *last_ms = now_ms;
        }
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
            cache_creation_reported,
            seconds_since_prev,
            agent_id: None,
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
            seq: counters.seq,
            input_bytes: bytes.len() as u64,
            input_hash: hasher.hash(bytes),
            input_prefix_hash: hasher.hash(prefix),
            result_bytes: None,
            prompt_id: None,
            agent_id: None,
            command_shape: crate::shape::tool_shape(
                name,
                item.pointer("/input/command").and_then(Value::as_str),
            ),
        });
        counters.seq = counters.seq.saturating_add(1);
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
