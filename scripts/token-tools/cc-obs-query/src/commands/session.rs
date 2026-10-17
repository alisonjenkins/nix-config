use std::collections::BTreeMap;

use serde_json::{json, Value};

use super::{label_value, Ctx, CACHE_HIT, CONTEXT, FIXED};
use crate::backend::Sample;
use crate::bounds::{figure, num, Report};
use crate::error::Error;

fn session_matcher(id: &str) -> Result<String, Error> {
    Ok(format!("session_id=\"{}\"", label_value("session id", id)?))
}

/// One ledger series: a user-prompt turn of one agent kind on one model. A turn
/// holds the main agent's requests and any subagents', so the turn alone is not
/// a series identity.
#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
struct SeriesKey {
    turn: u64,
    agent: String,
    model: String,
}

fn per_series(ctx: &Ctx, metric: &str, id: &str) -> Result<BTreeMap<SeriesKey, f64>, Error> {
    let matcher = session_matcher(id)?;
    let query = format!(
        "last_over_time({}[{}])",
        ctx.selector(metric, &[&matcher]),
        ctx.window.prom()
    );
    let label = |s: &Sample, name: &str| s.labels.get(name).cloned().unwrap_or_default();
    Ok(ctx
        .instant(&query)?
        .into_iter()
        .filter_map(|s| {
            let key = SeriesKey {
                turn: s.labels.get("turn")?.parse().ok()?,
                agent: label(&s, "agent"),
                model: label(&s, "model"),
            };
            Some((key, s.value))
        })
        .collect())
}

/// Per turn, the series with the largest context, with the cache ratio of that
/// same series so a turn's figures never mix two agents.
fn peak_per_turn(
    context: &BTreeMap<SeriesKey, f64>,
    cache: &BTreeMap<SeriesKey, f64>,
) -> BTreeMap<u64, (f64, Option<f64>)> {
    let mut peaks: BTreeMap<u64, (f64, Option<f64>)> = BTreeMap::new();
    for (key, tokens) in context {
        let ratio = cache.get(key).copied();
        match peaks.get(&key.turn) {
            Some((best, _)) if best >= tokens => {}
            _ => {
                peaks.insert(key.turn, (*tokens, ratio));
            }
        }
    }
    peaks
}

/// The component series are a split of the total, so summing them would count
/// the fixed context twice; only the total is read.
fn fixed_tokens(ctx: &Ctx, id: &str) -> Result<Option<f64>, Error> {
    let matcher = session_matcher(id)?;
    let total = "component=\"total\"";
    let query = format!(
        "max(last_over_time({}[{}]))",
        ctx.selector(FIXED, &[&matcher, total]),
        ctx.window.prom()
    );
    ctx.scalar(&query)
}

pub fn run(ctx: &Ctx, id: &str, detail: bool) -> Result<Report, Error> {
    let command = format!("session {id}");
    let series = per_series(ctx, CONTEXT, id)?;
    if series.is_empty() {
        return Ok(Report::unavailable(
            &command,
            format!("no cc_obs_ledger samples for session {id} in the window"),
        ));
    }
    let cache = per_series(ctx, CACHE_HIT, id)?;
    let fixed = fixed_tokens(ctx, id)?;
    let context = peak_per_turn(&series, &cache);
    let max_context = context
        .values()
        .map(|(tokens, _)| *tokens)
        .fold(f64::MIN, f64::max);
    let ratios: Vec<f64> = context.values().filter_map(|(_, ratio)| *ratio).collect();
    let mean_cache = (!ratios.is_empty()).then(|| ratios.iter().sum::<f64>() / ratios.len() as f64);
    let new_tokens = match fixed {
        None => figure(None, "needs the fixed-context census"),
        Some(f) if f > max_context => figure(
            None,
            "the fixed-context census exceeds the peak context, so the two do not describe the same requests",
        ),
        Some(f) => num(max_context - f),
    };
    let mut report = Report::new(&command)
        .with("session", json!(id))
        .with("turns", json!(context.len()))
        .with("max_context_tokens", num(max_context))
        .with(
            "mean_cache_hit_ratio",
            figure(mean_cache, "no cache hit ratio recorded for this session"),
        )
        .with(
            "fixed_context_tokens",
            figure(fixed, "no fixed-context census for this session"),
        )
        .with("new_tokens", new_tokens);
    if detail {
        report.rows = context
            .iter()
            .map(|(turn, (tokens, ratio))| -> Value {
                json!({
                    "key": format!("turn {turn}"),
                    "turn": turn,
                    "context_tokens": num(*tokens),
                    "cache_hit_ratio": figure(*ratio, "no ratio for this turn"),
                })
            })
            .collect();
    }
    Ok(report)
}
