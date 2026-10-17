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

/// One range's figures. `truncated` is set when the backend stopped fetching
/// early, so a key missing from `values` may still exist in that range.
struct Side {
    values: BTreeMap<String, f64>,
    truncated: bool,
}

/// The note `Ctx::logs` records when a fetch hits its record or page cap.
const FETCH_CAP_NOTE: &str = "loki: stopped at";

impl Side {
    /// `Some(value)` for a present key, `Some(0.0)` for a key absent from a
    /// complete range, `None` for a key that may sit beyond the fetch cap.
    fn get(&self, key: &str) -> Option<f64> {
        match self.values.get(key) {
            Some(v) => Some(*v),
            None if self.truncated => None,
            None => Some(0.0),
        }
    }

    fn why_missing(&self, range: &str) -> String {
        format!("outside top {} in range {range}", self.values.len())
    }
}

fn figures(
    backend: &Backend,
    include_review: bool,
    window: Window,
    pack: &Pack,
    id: &str,
) -> Result<Side, Error> {
    let question = pack.question(id)?;
    let cli = question_cli(question)?;
    let ctx = Ctx::new(backend, window, include_review);
    let report = query_report(&ctx, &cli.command)?;
    let truncated = report
        .fields
        .get("gaps")
        .and_then(|g| g.as_array())
        .is_some_and(|gaps| {
            gaps.iter()
                .any(|g| g.as_str().is_some_and(|s| s.starts_with(FETCH_CAP_NOTE)))
        });
    Ok(Side {
        values: row_values(&report),
        truncated,
    })
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
    let keys: BTreeSet<&String> = first.values.keys().chain(second.values.keys()).collect();
    let mut rows: Vec<(f64, serde_json::Value)> = keys
        .into_iter()
        .map(|key| {
            let (x, y) = (first.get(key), second.get(key));
            let missing = match (x, y) {
                (None, _) => first.why_missing("A"),
                _ => second.why_missing("B"),
            };
            let delta = x.zip(y).map(|(x, y)| y - x);
            let ratio = x.zip(y).filter(|(x, _)| *x > 0.0).map(|(x, y)| y / x);
            let ratio_why = if delta.is_none() {
                missing.as_str()
            } else {
                "range A is zero"
            };
            (
                x.unwrap_or(0.0).max(y.unwrap_or(0.0)),
                json!({
                    "key": key,
                    "a": figure(x, &first.why_missing("A")),
                    "b": figure(y, &second.why_missing("B")),
                    "delta": figure(delta, &missing),
                    "ratio": figure(ratio, ratio_why),
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
