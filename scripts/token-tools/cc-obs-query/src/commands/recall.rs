use serde_json::{json, Value};

use super::{Ctx, RECALL_HITS, RECALL_REQUESTS, RECALL_TOKENS};
use crate::bounds::{figure, Report};
use crate::error::Error;

fn row(key: &str, value: Value) -> Value {
    json!({"key": key, "value": value})
}

pub fn run(ctx: &Ctx) -> Result<Report, Error> {
    let window = ctx.window.prom();
    let by_outcome = ctx.instant(&format!(
        "sum by (outcome)(increase({}[{window}]))",
        ctx.selector(RECALL_REQUESTS, &[])
    ))?;
    if by_outcome.is_empty() {
        return Ok(Report::unavailable(
            "recall",
            "no recall_requests_total samples in the window",
        ));
    }
    let count = |outcome: &str| -> f64 {
        by_outcome
            .iter()
            .filter(|s| s.labels.get("outcome").is_some_and(|o| o == outcome))
            .map(|s| s.value)
            .sum()
    };
    let requests: f64 = by_outcome.iter().map(|s| s.value).sum();
    let hits = ctx.increase_sum(RECALL_HITS)?;
    let injected = ctx.increase_sum(RECALL_TOKENS)?;
    let mut report = Report::new("recall");
    report.rows = vec![
        row("requests", figure(Some(requests), "")),
        row(
            "injected_tokens_per_prompt",
            figure(
                injected.filter(|_| requests > 0.0).map(|t| t / requests),
                "no recall_tokens_injected_total samples",
            ),
        ),
        row("matches_used", figure(hits, "no recall_hits_total samples")),
        row("empty_requests", figure(Some(count("empty")), "")),
        row("failures", figure(Some(count("error")), "")),
    ];
    Ok(report)
}
