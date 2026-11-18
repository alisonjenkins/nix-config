use std::collections::{BTreeMap, BTreeSet};

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
    pub image_bytes: f64,
    pub image_tokens: f64,
    pub image_calls: u64,
}

impl ToolStat {
    pub fn estimated_tokens(&self) -> f64 {
        (self.total_bytes - self.image_bytes).max(0.0) / BYTES_PER_TOKEN + self.image_tokens
    }
}

pub fn stats(ctx: &Ctx) -> Result<BTreeMap<String, ToolStat>, Error> {
    let mut stats: BTreeMap<String, ToolStat> = BTreeMap::new();
    for record in ctx.logs(&ctx.logql_client_variant("claude-code", "tool_result"))? {
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
    if let Ok(records) = ctx.logs(&ctx.logql("cc-obs-ledger", "cc_obs_ledger.tool_call")) {
        // Ingest may deliver a record twice; count each call once, keyed as in
        // `repeats::load`, so a duplicate never subtracts its image bytes twice.
        let mut seen: BTreeSet<(String, String, String, String)> = BTreeSet::new();
        for record in records {
            let Some(name) = record.fields.get("tool_name") else {
                continue;
            };
            let field = |key: &str| record.fields.get(key).cloned().unwrap_or_default();
            let agent = record
                .fields
                .get("agent")
                .or_else(|| record.fields.get("agent_type"))
                .cloned()
                .unwrap_or_default();
            if !seen.insert((field("session_id"), agent, field("agent_id"), field("seq"))) {
                continue;
            }
            let img_bytes = parse_f64(&record, "result_image_bytes").unwrap_or(0.0);
            let img_tokens = parse_f64(&record, "result_image_tokens").unwrap_or(0.0);
            let img_count = parse_f64(&record, "result_image_count").unwrap_or(0.0);
            if img_count > 0.0 || img_bytes > 0.0 || img_tokens > 0.0 {
                let stat = stats.entry(name.clone()).or_default();
                stat.image_calls = stat.image_calls.saturating_add(1);
                stat.image_bytes += img_bytes;
                stat.image_tokens += img_tokens;
            }
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
            value: s.estimated_tokens(),
            calls: Some(s.calls),
            model: None,
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
    let total_tokens: f64 = all
        .values()
        .filter(|s| s.sized_calls > 0)
        .map(ToolStat::estimated_tokens)
        .sum();
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
                (total_tokens > 0.0).then(|| stat.estimated_tokens() / total_tokens),
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
    if stat.image_calls > 0 {
        report
            .rows
            .push(figure_row("image_calls", json!(stat.image_calls)));
        report.rows.push(figure_row(
            "image_tokens",
            figure(Some(stat.image_tokens), ""),
        ));
    }
    Ok(report)
}
