use std::collections::BTreeMap;

use serde_json::{json, Map};

use super::{parse_f64, repeats, Ctx};
use crate::bounds::{figure, Report};
use crate::commands::top::RankRow;
use crate::error::Error;

/// Rough conversion for tool results that only report bytes.
pub const BYTES_PER_TOKEN: f64 = 4.0;

#[derive(Debug, Default, Clone)]
pub struct ToolStat {
    pub calls: u64,
    pub sized_calls: u64,
    pub total_bytes: f64,
    pub max_bytes: f64,
}

pub fn stats(ctx: &Ctx) -> Result<BTreeMap<String, ToolStat>, Error> {
    let mut stats: BTreeMap<String, ToolStat> = BTreeMap::new();
    for record in ctx.logs(&ctx.logql("claude-code", "tool_result"))? {
        let Some(name) = record.fields.get("tool_name") else {
            continue;
        };
        let stat = stats.entry(name.clone()).or_default();
        stat.calls = stat.calls.saturating_add(1);
        if let Some(bytes) = parse_f64(&record, "tool_result_size_bytes") {
            stat.sized_calls = stat.sized_calls.saturating_add(1);
            stat.total_bytes += bytes;
            stat.max_bytes = stat.max_bytes.max(bytes);
        }
    }
    Ok(stats)
}

pub fn ranked(ctx: &Ctx) -> Result<Vec<RankRow>, Error> {
    let mut rows: Vec<RankRow> = stats(ctx)?
        .into_iter()
        .filter(|(_, s)| s.sized_calls > 0)
        .map(|(key, s)| RankRow {
            key,
            value: s.total_bytes / BYTES_PER_TOKEN,
            calls: Some(s.calls),
            detail: Map::new(),
        })
        .collect();
    rows.sort_by(|a, b| b.value.total_cmp(&a.value).then_with(|| a.key.cmp(&b.key)));
    Ok(rows)
}

fn figure_row(key: &str, value: serde_json::Value) -> serde_json::Value {
    json!({"key": key, "value": value})
}

pub fn run(ctx: &Ctx, name: &str) -> Result<Report, Error> {
    let command = format!("tool {name}");
    let all = stats(ctx)?;
    let Some(stat) = all.get(name).filter(|s| s.sized_calls > 0) else {
        return Ok(Report::unavailable(
            &command,
            format!("no tool_result events for tool {name} in the window"),
        ));
    };
    let total_bytes: f64 = all.values().map(|s| s.total_bytes).sum();
    let sized = stat.sized_calls as f64;
    let repeat_rate = repeats::repeat_rate(ctx, name)?;
    let mut report = Report::new(&command).with("tool", json!(name));
    report.rows = vec![
        figure_row("calls", json!(stat.calls)),
        figure_row(
            "mean_result_bytes",
            figure(Some(stat.total_bytes / sized), ""),
        ),
        figure_row("max_result_bytes", figure(Some(stat.max_bytes), "")),
        figure_row(
            "share_of_tokens",
            figure(
                (total_bytes > 0.0).then(|| stat.total_bytes / total_bytes),
                "no result sizes recorded",
            ),
        ),
        figure_row(
            "repeat_rate",
            figure(
                repeat_rate,
                "no cc_obs_ledger.tool_call records for this tool in the window",
            ),
        ),
    ];
    Ok(report)
}
