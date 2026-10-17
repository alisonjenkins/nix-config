//! Repeat detection from `cc_obs_ledger.tool_call` records. Only keyed hashes and
//! sizes are read; tool input content is never available here.
use std::collections::{BTreeMap, BTreeSet};

use serde_json::{json, Map};

use super::{parse_f64, Ctx};
use crate::bounds::{num, Report};
use crate::error::Error;

/// A result at least this big counts as "large" for the large-then-narrow pattern.
pub(super) const LARGE_RESULT_BYTES: u64 = 20_000;
const SEQUENCE_LEN: usize = 3;
/// Rows from every pattern are ranked together by `value`, so it has one unit:
/// tool calls that would not have been made without the pattern. `calls` is the size
/// of the evidence: calls in the group (identical, near_identical), 2 for a
/// large_then_narrow pair, or non-overlapping occurrences of a sequence.
const VALUE_MEANS: &str = "calls saved: identical = repeat calls beyond the first (calls separated by an edit by the same agent do not repeat each other: Edit, Write, NotebookEdit and MultiEdit end a run), near_identical = distinct inputs beyond the first, large_then_narrow = 1 per pair, sequence = occurrences x (length - 1) if one tool replaced the triple";
/// Identical and near-identical calls are a within-session, within-agent notion (each
/// agent has its own context), so their threshold applies per (session, agent); a
/// sequence is "frequent" across the window, so its threshold applies to occurrences
/// summed over all sessions.
const MIN_COUNT_MEANS: &str = "--min-count (floor 2): identical and near_identical = calls per session and agent (a subagent repeating a main-agent call is not a repeat); sequence = occurrences across all sessions";
const NO_RECORDS: &str = "no cc_obs_ledger.tool_call records in the window";

#[derive(Debug, Clone)]
pub struct Call {
    pub session: String,
    pub tool: String,
    pub agent: String,
    /// Sub-agent id; empty for the main loop and for records from an older ledger.
    pub agent_id: String,
    pub input_hash: String,
    pub prefix_hash: String,
    /// Short fixed-vocabulary label of a Bash call; empty on records from an older ledger.
    pub command_shape: String,
    pub result_bytes: Option<u64>,
    pub turn: u64,
    pub seq: u64,
}

pub(super) fn load(ctx: &Ctx) -> Result<Vec<Call>, Error> {
    let records = ctx.logs(&ctx.logql("cc-obs-ledger", "cc_obs_ledger.tool_call"))?;
    let received = records.len();
    let mut calls: Vec<Call> = records
        .into_iter()
        .filter_map(|r| {
            let field = |name: &str| r.fields.get(name).cloned();
            let whole = |name: &str| parse_f64(&r, name).map(|v| v as u64);
            Some(Call {
                session: field("session_id")?,
                tool: field("tool_name")?,
                // The ledger writes `agent`; `agent_type` is the name older data used.
                agent: field("agent")
                    .or_else(|| field("agent_type"))
                    .unwrap_or_default(),
                agent_id: field("agent_id").unwrap_or_default(),
                input_hash: field("input_hash")?,
                prefix_hash: field("input_prefix_hash").unwrap_or_default(),
                command_shape: field("command_shape").unwrap_or_default(),
                result_bytes: whole("result_bytes"),
                turn: whole("turn").unwrap_or(0),
                seq: whole("seq").unwrap_or(0),
            })
        })
        .collect();
    let skipped = received.saturating_sub(calls.len());
    if skipped > 0 {
        ctx.note_gap(format!(
            "repeats: {skipped} of {received} tool_call records lacked session_id, tool_name or input_hash and were skipped"
        ));
    }
    // Ingest may deliver a record twice; the first (session, agent, agent_id, seq) wins.
    // Each sub-agent has its own cursor, so its seq restarts at 0.
    let mut seen: BTreeSet<(String, String, String, u64)> = BTreeSet::new();
    let before = calls.len();
    calls.retain(|c| {
        seen.insert((
            c.session.clone(),
            c.agent.clone(),
            c.agent_id.clone(),
            c.seq,
        ))
    });
    let duplicates = before.saturating_sub(calls.len());
    if duplicates > 0 {
        ctx.note_gap(format!(
            "repeats: {duplicates} duplicate tool_call records (same session, agent, agent_id, seq) ignored"
        ));
    }
    calls.sort_by(|a, b| (&a.session, a.turn, a.seq).cmp(&(&b.session, b.turn, b.seq)));
    Ok(calls)
}

/// One stream per (session, agent, agent_id); `agent_id` is empty for the main loop and
/// for sub-agent records from an older ledger, which therefore stay one stream.
fn by_agent(calls: &[Call]) -> BTreeMap<(&str, &str, &str), Vec<&Call>> {
    let mut map: BTreeMap<(&str, &str, &str), Vec<&Call>> = BTreeMap::new();
    for call in calls {
        map.entry((
            call.session.as_str(),
            call.agent.as_str(),
            call.agent_id.as_str(),
        ))
        .or_default()
        .push(call);
    }
    map
}

/// Fraction of a tool's calls that repeat an earlier identical call of the same
/// session; `None` when the ledger has no record of the tool.
pub fn repeat_rate(ctx: &Ctx, tool: &str) -> Result<Option<f64>, Error> {
    let calls: Vec<Call> = load(ctx)?.into_iter().filter(|c| c.tool == tool).collect();
    if calls.is_empty() {
        return Ok(None);
    }
    let distinct: BTreeSet<(&str, &str, &str, &str)> = calls
        .iter()
        .map(|c| {
            (
                c.session.as_str(),
                c.agent.as_str(),
                c.agent_id.as_str(),
                c.input_hash.as_str(),
            )
        })
        .collect();
    Ok(Some(
        (calls.len().saturating_sub(distinct.len())) as f64 / calls.len() as f64,
    ))
}

#[derive(Default)]
struct Finding {
    value: u64,
    calls: u64,
    sessions: BTreeSet<String>,
    wasted_bytes: u64,
}

impl Finding {
    fn add(&mut self, session: &str, count: u64, wasted: u64, calls: u64) {
        self.calls = self.calls.saturating_add(calls);
        self.value = self.value.saturating_add(count);
        self.sessions.insert(session.to_owned());
        self.wasted_bytes = self.wasted_bytes.saturating_add(wasted);
    }
}

type Findings = BTreeMap<(&'static str, String), Finding>;

/// Tools that change the state a repeated call would observe.
const EDIT_TOOLS: [&str; 4] = ["Edit", "Write", "NotebookEdit", "MultiEdit"];

/// Identical calls by one agent, split into runs at every edit by that agent: a call
/// repeated across an edit may legitimately see new state (a test run after a fix), so
/// only calls with no edit between them form a group. `calls` is one agent's stream.
fn identical(calls: &[&Call], min_count: u64, out: &mut Findings) {
    type Group<'a> = BTreeMap<(&'a str, &'a str), Vec<&'a Call>>;
    let mut runs: Vec<Group> = vec![Group::new()];
    for call in calls {
        if EDIT_TOOLS.contains(&call.tool.as_str()) {
            runs.push(Group::new());
            continue;
        }
        if let Some(run) = runs.last_mut() {
            run.entry((call.tool.as_str(), call.input_hash.as_str()))
                .or_default()
                .push(call);
        }
    }
    for ((tool, _), group) in runs.into_iter().flatten() {
        let size = group.len() as u64;
        if size < min_count.max(2) {
            continue;
        }
        let wasted: u64 = group.iter().skip(1).filter_map(|c| c.result_bytes).sum();
        if let Some(first) = group.first() {
            out.entry(("identical", tool.to_owned())).or_default().add(
                &first.session,
                size.saturating_sub(1),
                wasted,
                size,
            );
        }
    }
}

/// Same tool and same leading-argument hash (the ledger contract), with at least two
/// distinct full inputs. Calls that also form an identical group stay in `calls`; the
/// contract does not exclude them, and `value` counts only the distinct extra inputs
/// so nothing is counted twice against `identical`.
fn near_identical(calls: &[&Call], min_count: u64, out: &mut Findings) {
    let mut groups: BTreeMap<(&str, &str), Vec<&Call>> = BTreeMap::new();
    for call in calls.iter().filter(|c| !c.prefix_hash.is_empty()) {
        groups
            .entry((call.tool.as_str(), call.prefix_hash.as_str()))
            .or_default()
            .push(call);
    }
    for ((tool, _), group) in groups {
        let hashes: BTreeSet<&str> = group.iter().map(|c| c.input_hash.as_str()).collect();
        if (group.len() as u64) < min_count.max(2) || hashes.len() < 2 {
            continue;
        }
        if let Some(first) = group.first() {
            out.entry(("near_identical", tool.to_owned()))
                .or_default()
                .add(
                    &first.session,
                    hashes.len().saturating_sub(1) as u64,
                    0,
                    group.len() as u64,
                );
        }
    }
}

/// A large result immediately followed, by the same agent, by a different call to the
/// same tool that returned less: the first call asked for more than it needed. A
/// later call to the same tool with other work in between is not a narrowing.
fn large_then_narrow(calls: &[&Call], out: &mut Findings) {
    for (call, next) in calls.iter().zip(calls.iter().skip(1)) {
        let Some(large) = call.result_bytes.filter(|b| *b >= LARGE_RESULT_BYTES) else {
            continue;
        };
        if next.tool == call.tool {
            let narrower = next.result_bytes.is_some_and(|b| b < large);
            if narrower && next.input_hash != call.input_hash {
                out.entry(("large_then_narrow", call.tool.clone()))
                    .or_default()
                    .add(&call.session, 1, large, 2);
            }
        }
    }
}

/// Non-overlapping windows of `len` labels, found greedily left to right: each is the
/// window's start and its labels joined by `sep`. A run of five identical labels holds
/// one window of three, not three. Only windows of the same labels are kept apart.
pub(super) fn greedy_windows(labels: &[&str], len: usize, sep: &str) -> Vec<(usize, String)> {
    let mut free_from: BTreeMap<String, usize> = BTreeMap::new();
    let mut found = Vec::new();
    for (start, window) in labels.windows(len).enumerate() {
        let key = window.join(sep);
        if free_from.get(&key).is_some_and(|free| start < *free) {
            continue;
        }
        free_from.insert(key.clone(), start.saturating_add(len));
        found.push((start, key));
    }
    found
}

/// Non-overlapping occurrences of each tool triple within one agent's calls.
fn sequences(calls: &[&Call], counts: &mut BTreeMap<String, (u64, BTreeSet<String>)>) {
    let names: Vec<&str> = calls.iter().map(|c| c.tool.as_str()).collect();
    for (_, key) in greedy_windows(&names, SEQUENCE_LEN, ">") {
        let entry = counts.entry(key).or_default();
        entry.0 = entry.0.saturating_add(1);
        if let Some(call) = calls.first() {
            entry.1.insert(call.session.clone());
        }
    }
}

pub fn run(ctx: &Ctx, min_count: u64, tool: Option<&str>) -> Result<Report, Error> {
    let mut calls = load(ctx)?;
    if calls.is_empty() {
        return Ok(Report::unavailable("repeats", NO_RECORDS));
    }
    if let Some(tool) = tool {
        calls.retain(|c| c.tool == tool);
        if calls.is_empty() {
            return Ok(Report::unavailable(
                "repeats",
                format!("no cc_obs_ledger.tool_call records for tool {tool} in the window"),
            ));
        }
    }
    let mut findings = Findings::new();
    let mut seqs = BTreeMap::new();
    // A subagent's calls are interleaved with the main agent's by (turn, seq) and its
    // seq may restart, and each agent has its own context, so every pattern is read per
    // (session, agent), never across them.
    for stream in by_agent(&calls).values() {
        identical(stream, min_count, &mut findings);
        near_identical(stream, min_count, &mut findings);
        large_then_narrow(stream, &mut findings);
        sequences(stream, &mut seqs);
    }
    let mut rows: Vec<(u64, String, serde_json::Value)> = Vec::new();
    for ((pattern, tool), finding) in findings {
        let key = format!("{pattern}:{tool}");
        let mut detail = Map::new();
        detail.insert(
            "wasted_result_bytes".to_owned(),
            json!(finding.wasted_bytes),
        );
        rows.push((
            finding.value,
            key.clone(),
            json!({
                "key": key,
                "pattern": pattern,
                "value": finding.value,
                "calls": finding.calls,
                "sessions": finding.sessions.len(),
                "evidence": format!("tool:{tool}"),
                "detail": detail,
            }),
        ));
    }
    for (sequence, (count, sessions)) in seqs {
        if count < min_count.max(2) {
            continue;
        }
        let key = format!("sequence:{sequence}");
        rows.push((
            count,
            key.clone(),
            json!({
                "key": key,
                "pattern": "sequence",
                "value": count.saturating_mul(SEQUENCE_LEN.saturating_sub(1) as u64),
                "calls": count,
                "detail": { "occurrences": count, "calls_covered": count.saturating_mul(SEQUENCE_LEN as u64) },
                "sessions": sessions.len(),
            }),
        ));
    }
    rows.sort_by(|a, b| b.0.cmp(&a.0).then_with(|| a.1.cmp(&b.1)));
    let total = calls.len() as f64;
    let mut report = Report::new("repeats")
        .with("calls_analysed", num(total))
        .with("value_means", json!(VALUE_MEANS))
        .with("min_count_means", json!(MIN_COUNT_MEANS));
    report.rows = rows.into_iter().map(|(_, _, row)| row).collect();
    Ok(report)
}
