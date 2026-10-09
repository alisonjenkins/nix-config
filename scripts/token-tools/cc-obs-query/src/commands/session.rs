use std::collections::BTreeMap;

use serde_json::{json, Value};

use super::{label_value, Ctx, CACHE_HIT, CONTEXT, FIXED};
use crate::bounds::{figure, num, Report};
use crate::error::Error;

fn session_matcher(id: &str) -> Result<String, Error> {
    Ok(format!("session_id=\"{}\"", label_value("session id", id)?))
}

fn per_turn(ctx: &Ctx, metric: &str, id: &str) -> Result<BTreeMap<u64, f64>, Error> {
    let matcher = session_matcher(id)?;
    let query = format!(
        "last_over_time({}[{}])",
        ctx.selector(metric, &[&matcher]),
        ctx.window.prom()
    );
    Ok(ctx
        .instant(&query)?
        .into_iter()
        .filter_map(|s| Some((s.labels.get("turn")?.parse().ok()?, s.value)))
        .collect())
}

fn fixed_tokens(ctx: &Ctx, id: &str) -> Result<Option<f64>, Error> {
    let matcher = session_matcher(id)?;
    let query = format!(
        "max by (component)(last_over_time({}[{}]))",
        ctx.selector(FIXED, &[&matcher]),
        ctx.window.prom()
    );
    let samples = ctx.instant(&query)?;
    Ok((!samples.is_empty()).then(|| samples.iter().map(|s| s.value).sum()))
}

pub fn run(ctx: &Ctx, id: &str, detail: bool) -> Result<Report, Error> {
    let command = format!("session {id}");
    let context = per_turn(ctx, CONTEXT, id)?;
    if context.is_empty() {
        return Ok(Report::unavailable(
            &command,
            format!("no cc_obs_ledger samples for session {id} in the window"),
        ));
    }
    let cache = per_turn(ctx, CACHE_HIT, id)?;
    let fixed = fixed_tokens(ctx, id)?;
    let max_context = context.values().copied().fold(f64::MIN, f64::max);
    let mean_cache = (!cache.is_empty()).then(|| cache.values().sum::<f64>() / cache.len() as f64);
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
        .with(
            "new_tokens",
            figure(
                fixed.map(|f| (max_context - f).max(0.0)),
                "needs the fixed-context census",
            ),
        );
    if detail {
        report.rows = context
            .iter()
            .map(|(turn, tokens)| -> Value {
                json!({
                    "key": format!("turn {turn}"),
                    "turn": turn,
                    "context_tokens": num(*tokens),
                    "cache_hit_ratio": figure(cache.get(turn).copied(), "no ratio for this turn"),
                })
            })
            .collect();
    }
    Ok(report)
}
