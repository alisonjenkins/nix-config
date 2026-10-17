use std::collections::BTreeMap;

use clap::ValueEnum;
use serde_json::{json, Map, Value};

use super::{
    parse_f64, tool, Ctx, CACHE_HIT, COST, FIXED, RECALL_HITS, RECALL_REQUESTS, RECALL_TOKENS,
    TOKENS,
};
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
    /// Sessions with fewer than --min-requests requests are left out.
    CacheHit,
    /// `session` only: compaction events per session, most first
    Compactions,
    /// `memory` only: recall matches used per request, lowest first
    HitRate,
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
        matches!(self, By::CacheHit | By::HitRate)
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
        Category::Mcp => (&["mcp_server_name"], vec!["mcp_server_name!=\"\""]),
        Category::Subagent => (&["agent_name", "model"], vec!["query_source=\"subagent\""]),
        Category::Tool | Category::Memory | Category::Fixed => return None,
    })
}

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
        .filter_map(|s| {
            let key = s.labels.get(label).filter(|k| !k.is_empty())?.clone();
            let model = labels
                .get(1)
                .and_then(|l| s.labels.get(*l))
                .filter(|m| !m.is_empty())
                .cloned();
            Some(RankRow {
                key,
                value: s.value,
                calls: None,
                model,
                detail: Map::new(),
            })
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
                ratio: cached / total,
                prompt_tokens: total,
            };
            (session, hit)
        })
        .collect())
}

/// Requests per session: one `cc_obs_ledger_*` series is written per request.
fn requests_by_session(ctx: &Ctx) -> Result<BTreeMap<String, f64>, Error> {
    let query = format!(
        "count by (session_id)(last_over_time({}[{}]))",
        ctx.selector(CACHE_HIT, &[]),
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
    object.insert("key".to_owned(), json!(row.key));
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
