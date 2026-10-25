use std::collections::{BTreeMap, BTreeSet};

use clap::ValueEnum;
use serde_json::{json, Map, Value};

use super::{
    parse_f64, tool, Ctx, CACHE_HIT, CONTEXT, COST, FIXED, RECALL_HITS, RECALL_REQUESTS,
    RECALL_TOKENS, TOKENS,
};
use crate::backend::Sample;
use crate::bounds::{figure, num, Report};
use crate::error::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum Category {
    Tool,
    Skill,
    Mcp,
    Subagent,
    Memory,
    Fixed,
    Model,
    Project,
    Session,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum By {
    /// Estimated cost in USD
    Cost,
    /// New input and output tokens; cache reads and cache writes are not counted
    Tokens,
    /// `session` only: prompt-cache hit ratio, lowest first. Weighted by tokens:
    /// cacheRead / (cacheRead + cacheCreation + input) summed over the window.
    /// Sessions with fewer than --min-requests API requests are left out,
    /// counted from the ledger's request counter.
    CacheHit,
    /// `session` only: compaction events per session, most first
    Compactions,
    /// `memory` only: recall matches used per request, lowest first
    HitRate,
    /// `session` only: API requests per session and agent kind, most first
    Requests,
    /// `session` only: largest per-turn context minus the first turn's, per
    /// session and agent kind, most first
    ContextGrowth,
    /// `fixed` only: share of the average request's context that is fixed context,
    /// as `total` and per component
    Share,
    /// `mcp` only: servers connected at session start that no tool call used
    Idle,
    /// `skill` only: installed skills with no activation in the window, by the
    /// tokens their listing costs
    Unactivated,
    /// `memory` only: recall tokens injected per recall request, most first
    TokensPerRequest,
}

impl Category {
    pub fn name(self) -> String {
        self.to_possible_value()
            .map(|v| v.get_name().to_owned())
            .unwrap_or_default()
    }
}

impl By {
    fn name(self) -> String {
        self.to_possible_value()
            .map(|v| v.get_name().to_owned())
            .unwrap_or_default()
    }

    /// Ranks a ratio, where a share of the total means nothing.
    fn is_ratio(self) -> bool {
        matches!(
            self,
            By::CacheHit
                | By::HitRate
                | By::ContextGrowth
                | By::Share
                | By::Idle
                | By::TokensPerRequest
        )
    }
}

#[derive(Debug, Clone)]
pub struct RankRow {
    pub key: String,
    pub value: f64,
    pub calls: Option<u64>,
    /// Set when the row is one model's share of its key (`top subagent`).
    pub model: Option<String>,
    pub detail: Map<String, Value>,
}

impl RankRow {
    /// What the row is called in an evidence reference: `key`, or `key@model`.
    pub fn evidence_name(&self) -> String {
        match &self.model {
            Some(model) => format!("{}@{model}", self.key),
            None => self.key.clone(),
        }
    }
}

pub enum Ranked {
    Rows(Vec<RankRow>),
    Unavailable(String),
}

/// Prometheus labels and extra matchers that carry each category's attribution.
/// The first label is the row's key; a second one is the model it ran on.
fn label_spec(category: Category) -> Option<(&'static [&'static str], Vec<&'static str>)> {
    Some(match category {
        Category::Model => (&["model"], vec![]),
        Category::Project => (&["repository"], vec![]),
        Category::Session => (&["session_id"], vec![]),
        Category::Skill => (&["skill_name"], vec!["skill_name!=\"\""]),
        Category::Subagent => (&["agent_name", "model"], vec!["query_source=\"subagent\""]),
        Category::Tool | Category::Mcp | Category::Memory | Category::Fixed => return None,
    })
}

/// Key of a series whose attribution label is empty or missing, so its value
/// stays in the ranking and the shares instead of vanishing.
const UNATTRIBUTED: &str = "(unattributed)";

fn rows_from(
    ctx: &Ctx,
    aggregate: &str,
    metric: &str,
    labels: &[&str],
    extra: &[&str],
    window_fn: &str,
) -> Result<Vec<RankRow>, Error> {
    let Some(&label) = labels.first() else {
        return Ok(Vec::new());
    };
    let query = format!(
        "{aggregate} by ({})({window_fn}({}[{}]))",
        labels.join(", "),
        ctx.selector(metric, extra),
        ctx.window.prom()
    );
    let mut rows: Vec<RankRow> = ctx
        .instant(&query)?
        .into_iter()
        .map(|s| {
            let key = s
                .labels
                .get(label)
                .filter(|k| !k.is_empty())
                .cloned()
                .unwrap_or_else(|| UNATTRIBUTED.to_owned());
            let model = labels
                .get(1)
                .and_then(|l| s.labels.get(*l))
                .filter(|m| !m.is_empty())
                .cloned();
            RankRow {
                key,
                value: s.value,
                calls: None,
                model,
                detail: Map::new(),
            }
        })
        .collect();
    rows.sort_by(|a, b| {
        b.value
            .total_cmp(&a.value)
            .then_with(|| a.key.cmp(&b.key))
            .then_with(|| a.model.cmp(&b.model))
    });
    Ok(rows)
}

fn wrong_category(by: By, only: &str) -> Ranked {
    Ranked::Unavailable(format!("--by {} applies to `top {only}` only", by.name()))
}

fn ascending(rows: &mut [RankRow]) {
    rows.sort_by(|a, b| a.value.total_cmp(&b.value).then_with(|| a.key.cmp(&b.key)));
}

fn ranked_or_none(ctx_name: &str, rows: Vec<RankRow>) -> Ranked {
    if rows.is_empty() {
        Ranked::Unavailable(format!("no samples for {ctx_name} in the window"))
    } else {
        Ranked::Rows(rows)
    }
}

/// Sessions with fewer requests than this are left out of the cache-hit
/// ranking: the first request of a session is a cold start, so a session of one
/// to four requests always ranks low without anything being wrong.
pub const DEFAULT_MIN_REQUESTS: u64 = 5;

/// A session's prompt-cache hit ratio over the window, weighted by tokens.
struct CacheHit {
    ratio: f64,
    prompt_tokens: f64,
}

/// `sum by (session_id)(increase(tokens{type...}[window]))`, cache types included.
fn prompt_tokens_by_session(ctx: &Ctx, type_matcher: &str) -> Result<BTreeMap<String, f64>, Error> {
    let query = format!(
        "sum by (session_id)(increase({}[{}]))",
        ctx.selector_all_types(TOKENS, &[type_matcher]),
        ctx.window.prom()
    );
    Ok(ctx
        .instant(&query)?
        .into_iter()
        .filter_map(|s| {
            Some((
                s.labels
                    .get("session_id")
                    .filter(|k| !k.is_empty())?
                    .clone(),
                s.value,
            ))
        })
        .collect())
}

/// cacheRead over cacheRead + cacheCreation + input, summed across the window,
/// so a one-request cold start weighs what it spent rather than as much as a
/// long session. Sessions without token samples are absent.
fn cache_hit_by_session(ctx: &Ctx) -> Result<BTreeMap<String, CacheHit>, Error> {
    let read = prompt_tokens_by_session(ctx, "type=\"cacheRead\"")?;
    let prompt = prompt_tokens_by_session(ctx, "type=~\"cacheRead|cacheCreation|input\"")?;
    Ok(prompt
        .into_iter()
        .filter(|(_, total)| *total > 0.0)
        .map(|(session, total)| {
            let cached = read.get(&session).copied().unwrap_or(0.0);
            let hit = CacheHit {
                // increase() extrapolates the two series separately, so the quotient can pass 1
                ratio: (cached / total).min(1.0),
                prompt_tokens: total,
            };
            (session, hit)
        })
        .collect())
}

/// The ledger's per-request counter: one increment per distinct API request.
const LEDGER_REQUESTS: &str = "cc_obs_ledger_requests_total";

/// API requests per session and agent kind over the window, from the ledger's
/// request counter. A ledger that predates the counter has no such series; then
/// this falls back to counting cache-hit gauge series, which carry turn, model,
/// agent and project but no request id, so a tool loop within one turn counts
/// once and requests are undercounted.
fn requests_by_session_agent(ctx: &Ctx) -> Result<Vec<(String, String, f64)>, Error> {
    let by_counter = counted_requests(ctx)?;
    if !by_counter.is_empty() {
        return Ok(by_counter);
    }
    ctx.note_gap(format!(
        "{LEDGER_REQUESTS} has no samples in the window (ledger not yet updated?); requests are counted from {CACHE_HIT} series, which undercounts tool loops"
    ));
    let query = format!(
        "count by (session_id, agent)(last_over_time({}[{}]))",
        ctx.selector(CACHE_HIT, &[]),
        ctx.window.prom()
    );
    session_agent_values(ctx, &query)
}

fn counted_requests(ctx: &Ctx) -> Result<Vec<(String, String, f64)>, Error> {
    let counted = format!(
        "round(sum by (session_id, agent)(increase({}[{}])))",
        ctx.selector(LEDGER_REQUESTS, &[]),
        ctx.window.prom()
    );
    session_agent_values(ctx, &counted)
}

/// API requests per session, the agent kinds summed.
fn requests_by_session(ctx: &Ctx) -> Result<BTreeMap<String, f64>, Error> {
    let mut totals: BTreeMap<String, f64> = BTreeMap::new();
    for (session, _, value) in requests_by_session_agent(ctx)? {
        *totals.entry(session).or_insert(0.0) += value;
    }
    Ok(totals)
}

fn session_agent_values(ctx: &Ctx, query: &str) -> Result<Vec<(String, String, f64)>, Error> {
    Ok(ctx
        .instant(query)?
        .into_iter()
        .filter(|s| !label_of(s, "session_id").is_empty())
        .map(|s| (label_of(&s, "session_id"), label_of(&s, "agent"), s.value))
        .collect())
}

fn rank_cache_hit(ctx: &Ctx, min_requests: u64) -> Result<Ranked, Error> {
    let requests = requests_by_session(ctx)?;
    let hits = cache_hit_by_session(ctx)?;
    let mut untokened = 0_u64;
    let mut rows: Vec<RankRow> = Vec::new();
    for (session, count) in requests {
        if count < min_requests as f64 {
            continue;
        }
        let Some(hit) = hits.get(&session) else {
            untokened = untokened.saturating_add(1);
            continue;
        };
        let mut detail = Map::new();
        detail.insert("requests".to_owned(), num(count));
        detail.insert("prompt_tokens".to_owned(), num(hit.prompt_tokens));
        rows.push(RankRow {
            key: session,
            value: hit.ratio,
            calls: None,
            model: None,
            detail,
        });
    }
    if untokened > 0 {
        ctx.note_gap(format!(
            "{untokened} session(s) have ledger requests but no token counts in the window and are not ranked"
        ));
    }
    ascending(&mut rows);
    Ok(ranked_or_none(
        &format!("session cache hit ratio with at least {min_requests} requests"),
        rows,
    ))
}

fn rank_compactions(ctx: &Ctx) -> Result<Ranked, Error> {
    #[derive(Default)]
    struct Sums {
        count: u64,
        pre: f64,
        post: f64,
        sized: u64,
    }
    let mut sums: BTreeMap<String, Sums> = BTreeMap::new();
    for record in ctx.logs(&ctx.logql("claude-code", "compaction"))? {
        let Some(session) = record.fields.get("session_id").filter(|s| !s.is_empty()) else {
            continue;
        };
        let entry = sums.entry(session.clone()).or_default();
        entry.count = entry.count.saturating_add(1);
        if let (Some(pre), Some(post)) = (
            parse_f64(&record, "pre_tokens"),
            parse_f64(&record, "post_tokens"),
        ) {
            entry.pre += pre;
            entry.post += post;
            entry.sized = entry.sized.saturating_add(1);
        }
    }
    let mut rows: Vec<RankRow> = sums
        .into_iter()
        .map(|(key, s)| {
            let mut detail = Map::new();
            if s.sized > 0 {
                let n = s.sized as f64;
                detail.insert("mean_pre_tokens".to_owned(), num(s.pre / n));
                detail.insert("mean_post_tokens".to_owned(), num(s.post / n));
            }
            RankRow {
                key,
                value: s.count as f64,
                calls: None,
                model: None,
                detail,
            }
        })
        .collect();
    rows.sort_by(|a, b| b.value.total_cmp(&a.value).then_with(|| a.key.cmp(&b.key)));
    Ok(ranked_or_none("compaction events", rows))
}

/// The row key of one agent kind in a session: the session id for the main
/// agent, `<id>/subagent` for the sub-agents, so the two never merge.
fn agent_key(session: &str, agent: &str) -> String {
    if agent == "subagent" {
        format!("{session}/subagent")
    } else {
        session.to_owned()
    }
}

fn label_of(s: &Sample, name: &str) -> String {
    s.labels.get(name).cloned().unwrap_or_default()
}

fn rank_requests(ctx: &Ctx) -> Result<Ranked, Error> {
    // a ranking by request count must not fall back to the series count, which undercounts tool loops
    let counted = counted_requests(ctx)?;
    if counted.is_empty() {
        return Ok(Ranked::Unavailable(format!(
            "{LEDGER_REQUESTS} has no samples in the window (ledger not yet updated?)"
        )));
    }
    let mut by_key: BTreeMap<String, f64> = BTreeMap::new();
    for (session, agent, value) in counted {
        *by_key.entry(agent_key(&session, &agent)).or_insert(0.0) += value;
    }
    let mut rows: Vec<RankRow> = by_key
        .into_iter()
        .map(|(key, value)| RankRow {
            key,
            value,
            calls: None,
            model: None,
            detail: Map::new(),
        })
        .collect();
    rows.sort_by(|a, b| b.value.total_cmp(&a.value).then_with(|| a.key.cmp(&b.key)));
    Ok(ranked_or_none("API requests", rows))
}

/// Per session and agent kind: the largest per-turn context less the first
/// turn's. A turn holds several series when it ran on more than one model; the
/// largest one stands for the turn. Series without a numeric turn are noted.
fn rank_context_growth(ctx: &Ctx) -> Result<Ranked, Error> {
    let query = format!(
        "last_over_time({}[{}])",
        ctx.selector(CONTEXT, &[]),
        ctx.window.prom()
    );
    let mut turns: BTreeMap<(String, String), BTreeMap<u64, f64>> = BTreeMap::new();
    let mut dropped = 0_u64;
    for s in ctx.instant(&query)? {
        let session = label_of(&s, "session_id");
        if session.is_empty() {
            continue;
        }
        let Some(turn) = s.labels.get("turn").and_then(|t| t.parse::<u64>().ok()) else {
            dropped = dropped.saturating_add(1);
            continue;
        };
        let slot = turns
            .entry((session, label_of(&s, "agent")))
            .or_default()
            .entry(turn)
            .or_insert(s.value);
        *slot = slot.max(s.value);
    }
    if dropped > 0 {
        ctx.note_gap(format!(
            "{CONTEXT}: {dropped} series without a numeric turn label were left out"
        ));
    }
    let mut rows: Vec<RankRow> = turns
        .into_iter()
        .filter_map(|((session, agent), by_turn)| {
            let first = *by_turn.values().next()?;
            let peak = by_turn.values().copied().fold(f64::MIN, f64::max);
            let mut detail = Map::new();
            detail.insert("turns".to_owned(), json!(by_turn.len()));
            detail.insert("first_context_tokens".to_owned(), num(first));
            detail.insert("max_context_tokens".to_owned(), num(peak));
            Some(RankRow {
                key: agent_key(&session, &agent),
                value: (peak - first).max(0.0),
                calls: None,
                model: None,
                detail,
            })
        })
        .collect();
    rows.sort_by(|a, b| b.value.total_cmp(&a.value).then_with(|| a.key.cmp(&b.key)));
    Ok(ranked_or_none("per-turn context growth", rows))
}

/// Fixed context re-read on every request, over the average request's context:
/// `avg(fixed{component})` over `avg(context_tokens)`. The `total` row is the
/// overall share; the component rows are shares of the same denominator, so
/// they add up to it and `total` is not counted among them.
fn rank_fixed_share(ctx: &Ctx) -> Result<Ranked, Error> {
    let context = ctx.scalar(&format!(
        "avg(avg_over_time({}[{}]))",
        ctx.selector(CONTEXT, &[]),
        ctx.window.prom()
    ))?;
    let Some(context) = context.filter(|c| *c > 0.0) else {
        return Ok(Ranked::Unavailable(format!(
            "no {CONTEXT} samples in the window, so there is no request size to divide by"
        )));
    };
    let mut rows = rows_from(ctx, "avg", FIXED, &["component"], &[], "avg_over_time")?;
    for row in &mut rows {
        let fixed = row.value;
        row.value = fixed / context;
        row.detail.insert("fixed_tokens".to_owned(), num(fixed));
        row.detail
            .insert("mean_request_context_tokens".to_owned(), num(context));
    }
    Ok(ranked_or_none("fixed context", rows))
}

/// Gauge set to 1 per MCP server connected at session start.
const MCP_CONNECTED: &str = "cc_obs_ledger_mcp_server_connected";

/// The server in an `mcp__<server>__<tool>` tool name.
fn mcp_server(tool: &str) -> Option<&str> {
    tool.strip_prefix("mcp__")?
        .split("__")
        .next()
        .filter(|server| !server.is_empty())
}

/// The form a server name takes inside a tool name: Claude Code replaces every
/// character outside `[A-Za-z0-9_-]` with `_` (`plugin:a:b` -> `plugin_a_b`).
fn normalise_server(name: &str) -> String {
    name.chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '_' || c == '-' {
                c
            } else {
                '_'
            }
        })
        .collect()
}

/// Result tokens and calls per MCP server, read from the ledger's `tool_call`
/// records: the claude-code `tool_result` stream names every MCP call `mcp_tool`.
fn mcp_ranked(ctx: &Ctx) -> Result<Vec<RankRow>, Error> {
    let mut servers: BTreeMap<String, (f64, u64)> = BTreeMap::new();
    for record in ctx.logs(&ctx.logql("cc-obs-ledger", "cc_obs_ledger.tool_call"))? {
        let Some(server) = record.fields.get("tool_name").and_then(|n| mcp_server(n)) else {
            continue;
        };
        let entry = servers.entry(server.to_owned()).or_default();
        entry.0 += parse_f64(&record, "result_bytes").unwrap_or(0.0) / tool::BYTES_PER_TOKEN;
        entry.1 = entry.1.saturating_add(1);
    }
    let mut rows: Vec<RankRow> = servers
        .into_iter()
        .map(|(key, (tokens, calls))| RankRow {
            key,
            value: tokens,
            calls: Some(calls),
            model: None,
            detail: Map::new(),
        })
        .collect();
    rows.sort_by(|a, b| b.value.total_cmp(&a.value).then_with(|| a.key.cmp(&b.key)));
    Ok(rows)
}

/// Connected servers (gauge at 1) minus servers with any tool call in the window.
fn rank_idle_mcp(ctx: &Ctx) -> Result<Ranked, Error> {
    let query = format!(
        "max by (mcp_server_name)(last_over_time({}[{}]))",
        ctx.selector(MCP_CONNECTED, &[]),
        ctx.window.prom()
    );
    let connected: Vec<String> = ctx
        .instant(&query)?
        .into_iter()
        .filter(|s| s.value >= 1.0)
        .map(|s| label_of(&s, "mcp_server_name"))
        .filter(|name| !name.is_empty())
        .collect();
    if connected.is_empty() {
        return Ok(Ranked::Unavailable(format!(
            "no {MCP_CONNECTED} samples in the window (the ledger does not emit the connected-server gauge yet, or no MCP server was connected)"
        )));
    }
    let called: BTreeSet<String> = mcp_ranked(ctx)?.into_iter().map(|r| r.key).collect();
    let mut rows: Vec<RankRow> = connected
        .into_iter()
        .filter(|name| !called.contains(&normalise_server(name)))
        .map(|key| RankRow {
            key,
            value: 1.0,
            calls: Some(0),
            model: None,
            detail: Map::new(),
        })
        .collect();
    rows.sort_by(|a, b| a.key.cmp(&b.key));
    Ok(Ranked::Rows(rows))
}

/// Gauge of the tokens a skill's listing costs, one per installed skill at session start.
const SKILL_LISTED: &str = "cc_obs_ledger_skill_listed_tokens";

/// The skill name after the last `:`; activations carry only this part of a
/// plugin-prefixed listing name such as `anthropic-skills:chrome-browser`.
fn bare_skill(name: &str) -> &str {
    name.rsplit(':').next().unwrap_or(name)
}

/// A worktree-prefixed listing (`.claude/worktrees/<wt>:<skill>`) whose bare
/// name is also listed: the same skill seen from a worktree checkout.
fn is_listed_twin(name: &str, listed: &BTreeSet<String>) -> bool {
    name.contains(".claude/worktrees/") && listed.contains(bare_skill(name))
}

/// Installed skills (listed gauge) minus skills with token usage attributed to
/// them, which is how `top skill` sees an activation.
fn rank_unactivated_skills(ctx: &Ctx) -> Result<Ranked, Error> {
    let listed = rows_from(
        ctx,
        "max",
        SKILL_LISTED,
        &["skill_name"],
        &[],
        "last_over_time",
    )?;
    if listed.is_empty() {
        return Ok(Ranked::Unavailable(format!(
            "no {SKILL_LISTED} samples in the window (the ledger does not emit the per-skill listing gauge yet)"
        )));
    }
    let activated: BTreeSet<String> = rows_from(
        ctx,
        "sum",
        TOKENS,
        &["skill_name"],
        &["skill_name!=\"\""],
        "increase",
    )?
    .into_iter()
    .filter(|r| r.value > 0.0)
    .map(|r| bare_skill(&r.key).to_owned())
    .collect();
    let listed_names: BTreeSet<String> = listed.iter().map(|r| r.key.clone()).collect();
    let rows = listed
        .into_iter()
        .filter(|r| !activated.contains(bare_skill(&r.key)))
        .filter(|r| !is_listed_twin(&r.key, &listed_names))
        .collect();
    Ok(Ranked::Rows(rows))
}

/// Recall tokens injected over recall requests, per service. A service with no
/// requests in the window has no per-request figure and is left out.
fn rank_tokens_per_request(ctx: &Ctx) -> Result<Ranked, Error> {
    let requests = rows_from(ctx, "sum", RECALL_REQUESTS, &["service"], &[], "increase")?;
    let injected: BTreeMap<String, f64> =
        rows_from(ctx, "sum", RECALL_TOKENS, &["service"], &[], "increase")?
            .into_iter()
            .map(|r| (r.key, r.value))
            .collect();
    let mut rows: Vec<RankRow> = requests
        .into_iter()
        .filter(|r| r.value > 0.0)
        .map(|r| {
            let tokens = injected.get(&r.key).copied().unwrap_or(0.0);
            let mut detail = Map::new();
            detail.insert("requests".to_owned(), num(r.value));
            detail.insert("injected_tokens".to_owned(), num(tokens));
            RankRow {
                value: tokens / r.value,
                key: r.key,
                calls: None,
                model: None,
                detail,
            }
        })
        .collect();
    rows.sort_by(|a, b| b.value.total_cmp(&a.value).then_with(|| a.key.cmp(&b.key)));
    Ok(ranked_or_none("recall tokens per request", rows))
}

fn rank_hit_rate(ctx: &Ctx) -> Result<Ranked, Error> {
    let requests = rows_from(ctx, "sum", RECALL_REQUESTS, &["service"], &[], "increase")?;
    let hits: BTreeMap<String, f64> =
        rows_from(ctx, "sum", RECALL_HITS, &["service"], &[], "increase")?
            .into_iter()
            .map(|r| (r.key, r.value))
            .collect();
    let mut rows: Vec<RankRow> = requests
        .into_iter()
        .filter(|r| r.value > 0.0)
        .map(|r| {
            // a counter with no series yet means no hits, not missing data
            let used = hits.get(&r.key).copied().unwrap_or(0.0);
            let mut detail = Map::new();
            detail.insert("requests".to_owned(), num(r.value));
            detail.insert("hits".to_owned(), num(used));
            RankRow {
                value: used / r.value,
                key: r.key,
                calls: None,
                model: None,
                detail,
            }
        })
        .collect();
    ascending(&mut rows);
    Ok(ranked_or_none("recall hit rate", rows))
}

pub fn rank(ctx: &Ctx, category: Category, by: By, min_requests: u64) -> Result<Ranked, Error> {
    match (by, category) {
        (By::CacheHit, Category::Session) => return rank_cache_hit(ctx, min_requests),
        (By::CacheHit, _) => return Ok(wrong_category(by, "session")),
        (By::Compactions, Category::Session) => return rank_compactions(ctx),
        (By::Compactions, _) => return Ok(wrong_category(by, "session")),
        (By::HitRate, Category::Memory) => return rank_hit_rate(ctx),
        (By::HitRate, _) => return Ok(wrong_category(by, "memory")),
        (By::Requests, Category::Session) => return rank_requests(ctx),
        (By::Requests, _) => return Ok(wrong_category(by, "session")),
        (By::ContextGrowth, Category::Session) => return rank_context_growth(ctx),
        (By::ContextGrowth, _) => return Ok(wrong_category(by, "session")),
        (By::TokensPerRequest, Category::Memory) => return rank_tokens_per_request(ctx),
        (By::TokensPerRequest, _) => return Ok(wrong_category(by, "memory")),
        (By::Unactivated, Category::Skill) => return rank_unactivated_skills(ctx),
        (By::Unactivated, _) => return Ok(wrong_category(by, "skill")),
        (By::Idle, Category::Mcp) => return rank_idle_mcp(ctx),
        (By::Idle, _) => return Ok(wrong_category(by, "mcp")),
        (By::Share, Category::Fixed) => return rank_fixed_share(ctx),
        (By::Share, _) => return Ok(wrong_category(by, "fixed")),
        _ => {}
    }
    let name = category.name();
    let none = || Ranked::Unavailable(format!("no samples for {name} in the window"));
    let rows = match category {
        Category::Tool => {
            if by == By::Cost {
                return Ok(Ranked::Unavailable(
                    "cost is not attributed per tool; rank by tokens".to_owned(),
                ));
            }
            tool::ranked(ctx)?
        }
        Category::Mcp => {
            if by == By::Cost {
                return Ok(Ranked::Unavailable(
                    "cost is not attributed per MCP server; rank by tokens".to_owned(),
                ));
            }
            mcp_ranked(ctx)?
        }
        Category::Fixed => {
            if by == By::Cost {
                return Ok(Ranked::Unavailable(
                    "cost is not attributed to fixed context; rank by tokens".to_owned(),
                ));
            }
            let mut rows = rows_from(ctx, "avg", FIXED, &["component"], &[], "avg_over_time")?;
            // `total` is the sum of the other components, not a component
            rows.retain(|r| r.key != "total");
            rows
        }
        Category::Memory => {
            if by == By::Cost {
                return Ok(Ranked::Unavailable(
                    "cost is not attributed to injected memory; rank by tokens".to_owned(),
                ));
            }
            rows_from(ctx, "sum", RECALL_TOKENS, &["service"], &[], "increase")?
        }
        other => {
            let Some((labels, extra)) = label_spec(other) else {
                return Ok(none());
            };
            let metric = if by == By::Cost { COST } else { TOKENS };
            let mut rows = rows_from(ctx, "sum", metric, labels, &extra, "increase")?;
            if other == Category::Session {
                add_cache_hit(ctx, &mut rows);
            }
            rows
        }
    };
    Ok(if rows.is_empty() {
        none()
    } else {
        Ranked::Rows(rows)
    })
}

fn add_cache_hit(ctx: &Ctx, rows: &mut [RankRow]) {
    let ratios: Result<BTreeMap<String, f64>, Error> = cache_hit_by_session(ctx)
        .map(|hits| hits.into_iter().map(|(k, hit)| (k, hit.ratio)).collect());
    for row in rows {
        let value = match &ratios {
            Ok(map) => figure(
                map.get(&row.key).copied(),
                "no cache hit ratio recorded for this session",
            ),
            Err(e) => figure(None, &e.to_string()),
        };
        row.detail.insert("cache_hit_ratio".to_owned(), value);
    }
}

/// `total` is the sum the row's share is taken of; `None` for a ratio, which has no share.
pub fn row_json(category: Category, row: &RankRow, total: Option<f64>) -> Value {
    let mut object = Map::new();
    object.insert("key".to_owned(), json!(row.evidence_name()));
    object.insert("value".to_owned(), num(row.value));
    if let Some(total) = total {
        let share = if total > 0.0 { row.value / total } else { 0.0 };
        object.insert("share".to_owned(), num(share));
    }
    if let Some(calls) = row.calls {
        object.insert("calls".to_owned(), json!(calls));
    }
    object.insert(
        "evidence".to_owned(),
        json!(format!("{}:{}", category.name(), row.evidence_name())),
    );
    let mut detail = row.detail.clone();
    if let Some(model) = &row.model {
        detail.insert("model".to_owned(), json!(model));
    }
    if !detail.is_empty() {
        object.insert("detail".to_owned(), Value::Object(detail));
    }
    Value::Object(object)
}

pub fn run(ctx: &Ctx, category: Category, by: By, min_requests: u64) -> Result<Report, Error> {
    let command = format!("top {}", category.name());
    Ok(match rank(ctx, category, by, min_requests)? {
        Ranked::Unavailable(why) => Report::unavailable(&command, why),
        Ranked::Rows(rows) => {
            let total = (!by.is_ratio()).then(|| rows.iter().map(|r| r.value).sum::<f64>());
            let mut report = Report::new(&command)
                .with("category", json!(category.name()))
                .with("by", json!(by.name()));
            report.rows = rows.iter().map(|r| row_json(category, r, total)).collect();
            report
        }
    })
}
