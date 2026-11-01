//! Candidates for scripts or tools that would replace repetitive AI work, ranked by
//! the estimated spend a script would remove. Reads `cc_obs_ledger.tool_call` records
//! through the same loader as `repeats`; only labels, hashes and sizes are available.
use std::collections::{BTreeMap, BTreeSet};

use serde_json::json;

use super::repeats::{greedy_windows, load, Call, LARGE_RESULT_BYTES};
use super::Ctx;
use crate::bounds::{num, Report};
use crate::error::Error;

/// Tokens of the call itself (the tool_use block); the records carry no input size.
const CALL_TOKENS: u64 = 100;
/// Result bytes per token, the same rough ratio the other commands use.
const BYTES_PER_TOKEN: u64 = 4;
/// Sonnet 5.5 input price, USD per million tokens (delegation skill, tiers.md).
const INPUT_USD_PER_MTOK: f64 = 2.0;
/// Sonnet 5.5 cache-read price: 10% of input (assumed; tiers.md lists no cache rate).
const CACHE_READ_USD_PER_MTOK: f64 = 0.20;
/// Assumed fraction of the spend a script removes, per candidate kind.
const SAVEABLE_SHAPE: f64 = 0.8;
const SAVEABLE_SEQUENCE: f64 = 0.6;
const SAVEABLE_LARGE: f64 = 0.5;
const SEQUENCE_LENS: [usize; 3] = [2, 3, 4];
const MAX_KEY_CHARS: usize = 256;
const NO_RECORDS: &str = "no cc_obs_ledger.tool_call records in the window";

const SCORE_MEANS: &str = "value = est_usd x saveable_share (USD); est_usd = direct_tokens x $2/M + carried_token_turns x $0.20/M (Sonnet 5.5 input and cache-read); direct_tokens = sum over the candidate's calls of (result_bytes/4 + 100 call tokens); carried_token_turns = sum over calls of result tokens x calls remaining in that agent's run; saveable_share is an assumption: 0.8 repeated identical shape, 0.6 sequence, 0.5 large result then narrower query";
const CALLS_MEANS: &str = "calls = occurrences: Bash calls with the shape, non-overlapping windows of a sequence, or large-then-narrow pairs; main/sub = occurrences by the main loop and by sub-agents";
const MIN_COUNT_MEANS: &str = "--min-count (floor 2): occurrences across all sessions needed for a `script` (shape or sequence) or `tool` (large result) action; candidates seen at least twice below it are listed as `dismiss`";

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum Kind {
    Shape,
    Sequence,
    LargeThenNarrow,
}

impl Kind {
    fn name(self) -> &'static str {
        match self {
            Kind::Shape => "shape",
            Kind::Sequence => "sequence",
            Kind::LargeThenNarrow => "large_then_narrow",
        }
    }

    fn saveable_share(self) -> f64 {
        match self {
            Kind::Shape => SAVEABLE_SHAPE,
            Kind::Sequence => SAVEABLE_SEQUENCE,
            Kind::LargeThenNarrow => SAVEABLE_LARGE,
        }
    }
}

struct Candidate {
    kind: Kind,
    parts: Vec<String>,
    occurrences: u64,
    sessions: BTreeSet<String>,
    main: u64,
    sub: u64,
    direct_tokens: u64,
    carried_token_turns: u64,
}

type Candidates = BTreeMap<(Kind, String), Candidate>;

fn is_sub(call: &Call) -> bool {
    call.agent == "subagent" || !call.agent_id.is_empty()
}

/// A Bash call is identified by its shape, or by its leading-argument hash on records
/// from a ledger that predates `command_shape`; any other call by its tool name.
fn label(call: &Call) -> String {
    if call.tool != "Bash" {
        call.tool.clone()
    } else if !call.command_shape.is_empty() {
        call.command_shape.clone()
    } else if !call.prefix_hash.is_empty() {
        format!("Bash@{}", call.prefix_hash)
    } else {
        "Bash".to_owned()
    }
}

/// An identifier-safe form of a label: digest row keys allow only `[A-Za-z0-9_.:/@+>-]`.
fn slug(label: &str) -> String {
    label
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || "_.:/@+>-".contains(c) {
                c
            } else {
                '_'
            }
        })
        .collect()
}

fn round6(value: f64) -> f64 {
    (value * 1e6).round() / 1e6
}

/// Records one occurrence covering `stream[start..start + len]`.
fn occurrence(
    found: &mut Candidates,
    kind: Kind,
    parts: Vec<String>,
    stream: &[&Call],
    start: usize,
    len: usize,
) {
    let Some(window) = stream.get(start..start.saturating_add(len)) else {
        return;
    };
    let Some(first) = window.first() else { return };
    let entry = found
        .entry((kind, parts.join(" > ")))
        .or_insert_with(|| Candidate {
            kind,
            parts,
            occurrences: 0,
            sessions: BTreeSet::new(),
            main: 0,
            sub: 0,
            direct_tokens: 0,
            carried_token_turns: 0,
        });
    entry.occurrences = entry.occurrences.saturating_add(1);
    entry.sessions.insert(first.session.clone());
    if is_sub(first) {
        entry.sub = entry.sub.saturating_add(1);
    } else {
        entry.main = entry.main.saturating_add(1);
    }
    for (offset, call) in window.iter().enumerate() {
        let tokens = call.result_bytes.unwrap_or(0) / BYTES_PER_TOKEN;
        let remaining = stream
            .len()
            .saturating_sub(start.saturating_add(offset).saturating_add(1));
        entry.direct_tokens = entry
            .direct_tokens
            .saturating_add(tokens.saturating_add(CALL_TOKENS));
        entry.carried_token_turns = entry
            .carried_token_turns
            .saturating_add(tokens.saturating_mul(remaining as u64));
    }
}

fn shapes(stream: &[&Call], found: &mut Candidates) {
    for (index, call) in stream.iter().enumerate() {
        if call.tool == "Bash" {
            occurrence(found, Kind::Shape, vec![label(call)], stream, index, 1);
        }
    }
}

/// Windows of consecutive Bash calls by one agent: a window holding another tool is
/// not something one script replaces.
fn sequences(stream: &[&Call], found: &mut Candidates) {
    let labels: Vec<String> = stream.iter().map(|c| label(c)).collect();
    let names: Vec<&str> = labels.iter().map(String::as_str).collect();
    for len in SEQUENCE_LENS {
        for (start, key) in greedy_windows(&names, len, " > ") {
            let Some(window) = stream.get(start..start.saturating_add(len)) else {
                continue;
            };
            if window.iter().any(|c| c.tool != "Bash") {
                continue;
            }
            let parts = key.split(" > ").map(str::to_owned).collect();
            occurrence(found, Kind::Sequence, parts, stream, start, len);
        }
    }
}

/// A large result immediately followed by a narrower different call to the same tool.
fn large_then_narrow(stream: &[&Call], found: &mut Candidates) {
    for (index, (call, next)) in stream.iter().zip(stream.iter().skip(1)).enumerate() {
        let Some(large) = call.result_bytes.filter(|b| *b >= LARGE_RESULT_BYTES) else {
            continue;
        };
        let narrower = next.result_bytes.is_some_and(|b| b < large);
        if next.tool == call.tool && narrower && next.input_hash != call.input_hash {
            occurrence(
                found,
                Kind::LargeThenNarrow,
                vec![label(call)],
                stream,
                index,
                2,
            );
        }
    }
}

/// Drops a sequence whose every occurrence sits inside one longer, listed sequence.
fn drop_contained(found: &mut Candidates) {
    let longer: Vec<(Vec<String>, u64)> = found
        .values()
        .filter(|c| c.kind == Kind::Sequence && c.occurrences >= 2)
        .map(|c| (c.parts.clone(), c.occurrences))
        .collect();
    found.retain(|_, cand| {
        if cand.kind != Kind::Sequence {
            return true;
        }
        !longer.iter().any(|(parts, occurrences)| {
            parts.len() > cand.parts.len()
                && *occurrences == cand.occurrences
                && parts.windows(cand.parts.len()).any(|w| w == cand.parts)
        })
    });
}

fn action(cand: &Candidate, min_count: u64) -> &'static str {
    let enough = cand.occurrences >= min_count;
    match cand.kind {
        Kind::LargeThenNarrow if enough => "tool",
        Kind::Shape | Kind::Sequence if enough && !cand.parts.iter().any(|p| p == "other") => {
            "script"
        }
        _ => "dismiss",
    }
}

pub fn run(ctx: &Ctx, min_count: u64) -> Result<Report, Error> {
    ctx.note_missing_subagent_transcripts()?;
    let calls = load(ctx)?;
    if calls.is_empty() {
        return Ok(Report::unavailable("automate", NO_RECORDS));
    }
    let bash = calls.iter().filter(|c| c.tool == "Bash").count();
    let unlabelled = calls
        .iter()
        .filter(|c| c.tool == "Bash" && c.command_shape.is_empty())
        .count();
    if unlabelled > 0 {
        ctx.note_gap(format!(
            "automate: {unlabelled} of {bash} Bash calls have no command_shape (records from before the ledger emitted it); they are grouped by tool_name + input_prefix_hash, so command identity needs the new ledger"
        ));
    }
    // A sub-agent has its own run and context, so streams are per (session, agent, agent id).
    let mut streams: BTreeMap<(&str, &str, &str), Vec<&Call>> = BTreeMap::new();
    for call in &calls {
        streams
            .entry((
                call.session.as_str(),
                call.agent.as_str(),
                call.agent_id.as_str(),
            ))
            .or_default()
            .push(call);
    }
    let mut found = Candidates::new();
    for stream in streams.values() {
        shapes(stream, &mut found);
        sequences(stream, &mut found);
        large_then_narrow(stream, &mut found);
    }
    drop_contained(&mut found);
    let floor = min_count.max(2);
    let mut ranked: Vec<(f64, String, serde_json::Value)> = Vec::new();
    for cand in found.values().filter(|c| c.occurrences >= 2) {
        let est_usd = cand.direct_tokens as f64 * INPUT_USD_PER_MTOK / 1e6
            + cand.carried_token_turns as f64 * CACHE_READ_USD_PER_MTOK / 1e6;
        let share = cand.kind.saveable_share();
        let score = round6(est_usd * share);
        let key = {
            let slugs: Vec<String> = cand.parts.iter().map(|p| slug(p)).collect();
            let joined = format!("{}:{}", cand.kind.name(), slugs.join(">"));
            joined.chars().take(MAX_KEY_CHARS).collect::<String>()
        };
        ranked.push((
            score,
            key.clone(),
            json!({
                "key": key,
                "pattern": cand.kind.name(),
                "value": score,
                "calls": cand.occurrences,
                "sessions": cand.sessions.len(),
                "main": cand.main,
                "sub": cand.sub,
                "est_usd": round6(est_usd),
                "action": action(cand, floor),
                "label": cand.parts.join(" > "),
                "detail": {
                    "saveable_share": share,
                    "direct_tokens": cand.direct_tokens,
                    "carried_token_turns": cand.carried_token_turns,
                },
            }),
        ));
    }
    ranked.sort_by(|a, b| b.0.total_cmp(&a.0).then_with(|| a.1.cmp(&b.1)));
    let mut report = Report::new("automate")
        .with("calls_analysed", num(calls.len() as f64))
        .with("score_means", json!(SCORE_MEANS))
        .with("calls_means", json!(CALLS_MEANS))
        .with("min_count_means", json!(MIN_COUNT_MEANS));
    report.rows = ranked.into_iter().map(|(_, _, row)| row).collect();
    Ok(report)
}
