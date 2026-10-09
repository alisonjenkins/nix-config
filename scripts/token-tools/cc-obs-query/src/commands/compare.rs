use std::collections::{BTreeMap, BTreeSet};

use serde_json::json;

use super::{query_report, question_cli, Ctx};
use crate::backend::Backend;
use crate::bounds::{figure, Report};
use crate::error::Error;
use crate::pack::Pack;
use crate::window::Window;

pub fn row_values(report: &Report) -> BTreeMap<String, f64> {
    report
        .rows
        .iter()
        .filter_map(|row| {
            Some((
                row.get("key")?.as_str()?.to_owned(),
                row.get("value")?.as_f64()?,
            ))
        })
        .collect()
}

fn figures(
    backend: &Backend,
    include_review: bool,
    window: Window,
    pack: &Pack,
    id: &str,
) -> Result<BTreeMap<String, f64>, Error> {
    let question = pack.question(id)?;
    let cli = question_cli(question)?;
    let ctx = Ctx::new(backend, window, include_review);
    Ok(row_values(&query_report(&ctx, &cli.command)?))
}

pub fn run(
    backend: &Backend,
    include_review: bool,
    pack: &Pack,
    id: &str,
    a: Window,
    b: Window,
) -> Result<Report, Error> {
    let first = figures(backend, include_review, a, pack, id)?;
    let second = figures(backend, include_review, b, pack, id)?;
    let keys: BTreeSet<&String> = first.keys().chain(second.keys()).collect();
    let mut rows: Vec<(f64, serde_json::Value)> = keys
        .into_iter()
        .map(|key| {
            let (x, y) = (first.get(key).copied(), second.get(key).copied());
            let delta = x.zip(y).map(|(x, y)| y - x);
            let ratio = x.zip(y).filter(|(x, _)| *x > 0.0).map(|(x, y)| y / x);
            (
                x.unwrap_or(0.0).max(y.unwrap_or(0.0)),
                json!({
                    "key": key,
                    "a": figure(x, "absent from range A"),
                    "b": figure(y, "absent from range B"),
                    "delta": figure(delta, "needs a value in both ranges"),
                    "ratio": figure(ratio, "needs a nonzero value in range A"),
                }),
            )
        })
        .collect();
    rows.sort_by(|l, r| r.0.total_cmp(&l.0));
    let mut report = Report::new("compare").with("question", json!(id));
    report.rows = rows.into_iter().map(|(_, row)| row).collect();
    if report.rows.is_empty() {
        return Ok(Report::unavailable(
            "compare",
            format!("question {id} returned no figures in either range"),
        ));
    }
    Ok(report)
}
