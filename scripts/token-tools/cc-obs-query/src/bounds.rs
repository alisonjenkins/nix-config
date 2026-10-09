//! Bounded output: every command returns a `Report`, and `render` applies the row
//! limit, the byte cap and the output format so no command can flood the caller.
use clap::ValueEnum;
use serde_json::{json, Map, Value};

use crate::error::Error;

pub const DEFAULT_LIMIT: usize = 10;
pub const DEFAULT_MAX_BYTES: usize = 8192;
pub const DIGEST_MAX_BYTES: usize = 32_768;

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum Format {
    Concise,
    Detailed,
    Table,
}

#[derive(Debug, Clone, Copy)]
pub struct Bounds {
    pub format: Format,
    pub limit: usize,
    pub max_bytes: usize,
    pub offset: usize,
}

impl Default for Bounds {
    fn default() -> Self {
        Self {
            format: Format::Concise,
            limit: DEFAULT_LIMIT,
            max_bytes: DEFAULT_MAX_BYTES,
            offset: 0,
        }
    }
}

/// What a command produced: top-level fields plus ranked rows. A row's optional
/// `detail` object is shown only with `--format detailed`.
#[derive(Debug, Clone, Default)]
pub struct Report {
    pub command: String,
    pub fields: Map<String, Value>,
    pub rows: Vec<Value>,
    /// The command ran but its check failed (exit code 1, output still printed).
    pub failed: bool,
}

impl Report {
    pub fn new(command: &str) -> Self {
        Self {
            command: command.to_owned(),
            ..Self::default()
        }
    }

    pub fn unavailable(command: &str, why: impl Into<String>) -> Self {
        let mut report = Self::new(command);
        report.fields.insert("value".to_owned(), Value::Null);
        report
            .fields
            .insert("unavailable".to_owned(), Value::String(why.into()));
        report
    }

    pub fn with(mut self, key: &str, value: Value) -> Self {
        self.fields.insert(key.to_owned(), value);
        self
    }
}

/// A figure, or `{"value": null, "unavailable": why}`; never a zero standing in
/// for missing data.
pub fn figure(value: Option<f64>, why: &str) -> Value {
    match value {
        Some(v) => num(v),
        None => json!({"value": null, "unavailable": why}),
    }
}

/// Whole numbers stay integers; everything else keeps four decimals.
pub fn num(value: f64) -> Value {
    if value.fract() == 0.0 && value.abs() < 1e15 {
        json!(value as i64)
    } else {
        json!((value * 10_000.0).round() / 10_000.0)
    }
}

fn shape_row(row: &Value, format: Format) -> Value {
    let Some(object) = row.as_object() else {
        return row.clone();
    };
    let mut shaped = object.clone();
    let detail = shaped.remove("detail");
    if format == Format::Detailed {
        if let Some(Value::Object(extra)) = detail {
            shaped.extend(extra);
        }
    }
    Value::Object(shaped)
}

fn cell(value: &Value) -> String {
    match value {
        Value::String(s) => s.clone(),
        Value::Null => "-".to_owned(),
        other => other.to_string(),
    }
}

fn table(report: &Report, rows: &[Value], truncated: Option<&str>) -> String {
    let mut columns: Vec<String> = Vec::new();
    for row in rows {
        if let Some(object) = row.as_object() {
            for key in object.keys() {
                if !columns.contains(key) {
                    columns.push(key.clone());
                }
            }
        }
    }
    let mut out = String::new();
    for (key, value) in &report.fields {
        out.push_str(&format!("{key}: {}\n", cell(value)));
    }
    out.push_str(&columns.join("\t"));
    out.push('\n');
    for row in rows {
        let line: Vec<String> = columns
            .iter()
            .map(|c| row.get(c).map(cell).unwrap_or_else(|| "-".to_owned()))
            .collect();
        out.push_str(&line.join("\t"));
        out.push('\n');
    }
    if let Some(next) = truncated {
        out.push_str(&format!("truncated: true next: {next}\n"));
    }
    out
}

fn encode(
    report: &Report,
    format: Format,
    rows: &[Value],
    next: Option<&str>,
) -> Result<String, Error> {
    if format == Format::Table {
        return Ok(table(report, rows, next));
    }
    let mut envelope = Map::new();
    envelope.insert("command".to_owned(), json!(report.command));
    envelope.extend(report.fields.clone());
    envelope.insert("rows".to_owned(), Value::Array(rows.to_vec()));
    if let Some(next) = next {
        envelope.insert("truncated".to_owned(), json!(true));
        envelope.insert("next".to_owned(), json!(next));
    }
    serde_json::to_string(&envelope).map_err(|source| Error::Render { source })
}

pub fn render(report: &Report, bounds: &Bounds) -> Result<String, Error> {
    if bounds.limit == 0 {
        return Err(Error::Usage {
            message: "--limit 0 shows no rows and gives `next` nothing to advance; use 1 or more"
                .to_owned(),
            input: "--limit 0".to_owned(),
        });
    }
    let shaped: Vec<Value> = report
        .rows
        .iter()
        .skip(bounds.offset)
        .map(|r| shape_row(r, bounds.format))
        .collect();
    let by_limit = shaped.len().min(bounds.limit);
    let next_for = |kept: usize| format!("--offset {}", bounds.offset.saturating_add(kept));
    let mut keep = by_limit;
    // The rendered size only grows with the row count, so bisect for the largest fit.
    let fits = |n: usize| -> Result<bool, Error> {
        let rows = shaped.get(..n).unwrap_or(&shaped);
        let next = (n < shaped.len()).then(|| next_for(n));
        Ok(encode(report, bounds.format, rows, next.as_deref())?.len() <= bounds.max_bytes)
    };
    // At least one row must fit, or `next` would equal the current offset.
    let floor = shaped.len().min(1);
    let floor_rows = shaped.get(..floor).unwrap_or(&shaped);
    let floor_next = (floor < shaped.len()).then(|| next_for(floor));
    let need = encode(report, bounds.format, floor_rows, floor_next.as_deref())?.len();
    if need > bounds.max_bytes {
        return Err(Error::Usage {
            message: format!(
                "--max-bytes {} is too small; need at least {need}",
                bounds.max_bytes
            ),
            input: format!("--max-bytes {}", bounds.max_bytes),
        });
    }
    if !fits(keep)? {
        let (mut low, mut high) = (floor, keep);
        while low < high {
            let mid = low.saturating_add(high).saturating_add(1) / 2;
            if fits(mid)? {
                low = mid;
            } else {
                high = mid.saturating_sub(1);
            }
        }
        keep = low;
    }
    let rows = shaped.get(..keep).unwrap_or(&shaped);
    let next = (keep < shaped.len()).then(|| next_for(keep));
    encode(report, bounds.format, rows, next.as_deref())
}

#[cfg(test)]
#[allow(
    clippy::unwrap_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]
mod tests {
    use super::*;

    fn report(n: usize) -> Report {
        let mut r = Report::new("x");
        r.rows = (0..n)
            .map(|i| json!({"key": format!("k{i}"), "detail": {"d": i}}))
            .collect();
        r
    }

    #[test]
    fn figures_never_turn_missing_into_zero() {
        assert_eq!(
            figure(None, "why"),
            json!({"value": null, "unavailable": "why"})
        );
        assert_eq!(figure(Some(0.0), "why"), json!(0));
        assert_eq!(num(0.123_456), json!(0.1235));
    }

    #[test]
    fn limit_truncates_with_next() {
        let out: Value = serde_json::from_str(
            &render(
                &report(5),
                &Bounds {
                    limit: 2,
                    ..Bounds::default()
                },
            )
            .unwrap(),
        )
        .unwrap();
        assert_eq!(out["rows"].as_array().unwrap().len(), 2);
        assert_eq!(out["next"], json!("--offset 2"));
    }

    #[test]
    fn detail_only_in_detailed_format() {
        let concise = render(&report(1), &Bounds::default()).unwrap();
        assert!(!concise.contains("\"d\""));
        let detailed = render(
            &report(1),
            &Bounds {
                format: Format::Detailed,
                ..Bounds::default()
            },
        )
        .unwrap();
        assert!(detailed.contains("\"d\":0"));
    }

    #[test]
    fn byte_cap_holds_even_with_one_row_too_big() {
        let out = render(
            &report(50),
            &Bounds {
                limit: 50,
                max_bytes: 150,
                ..Bounds::default()
            },
        )
        .unwrap();
        assert!(out.len() <= 150, "{out}");
    }
}
