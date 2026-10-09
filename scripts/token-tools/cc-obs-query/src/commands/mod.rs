//! The query commands. Each takes a `Ctx` (backend, window, review exclusion) and
//! returns a `Report`; none of them reads prompt or file content.
use std::cell::RefCell;

use serde_json::{json, Value};

use crate::backend::{Backend, LogFetch, LogRecord, Sample};
use crate::bounds::{figure, Report};
use clap::Parser;

use crate::cli::{Cli, Command};
use crate::error::Error;
use crate::pack::Question;
use crate::window::Window;

pub mod compare;
pub mod digest;
pub mod health;
pub mod recall;
pub mod repeats;
pub mod session;
pub mod tool;
pub mod top;
pub mod unused;

pub const TOKENS: &str = "claude_code_token_usage_tokens_total";
pub const COST: &str = "claude_code_cost_usage_USD_total";
pub const CONTEXT: &str = "cc_obs_ledger_context_tokens";
pub const CACHE_HIT: &str = "cc_obs_ledger_cache_hit_ratio";
pub const FIXED: &str = "cc_obs_ledger_fixed_context_tokens";
pub const RECALL_REQUESTS: &str = "recall_requests_total";
pub const RECALL_HITS: &str = "recall_hits_total";
pub const RECALL_TOKENS: &str = "recall_tokens_injected_total";

const EXCLUDE: &str = "review_run!=\"1\"";
/// Cache reads and writes are not new tokens; summing them with input and output
/// mixes units, so token figures leave them out.
pub const NO_CACHE_TOKENS: &str = "type!~\"cacheRead|cacheCreation\"";
/// Loki's default per-query entry limit.
const LOG_PAGE_SIZE: usize = 5000;
/// Hard stops so a busy window cannot exhaust memory or the caller's patience.
const MAX_LOG_RECORDS: usize = 50_000;
const MAX_LOG_PAGES: usize = 20;

/// Escapes a value for use inside a double-quoted PromQL/LogQL/TraceQL string.
pub fn escape_label(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for c in value.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\n' => out.push_str("\\n"),
            other => out.push(other),
        }
    }
    out
}

/// A label value taken from the command line: control characters are refused,
/// the rest is escaped.
pub fn label_value(flag: &'static str, value: &str) -> Result<String, Error> {
    if value.is_empty() || value.chars().any(char::is_control) {
        return Err(Error::BadArgument {
            flag,
            value: value.escape_debug().to_string(),
            reason: "it is empty or contains control characters".to_owned(),
        });
    }
    Ok(escape_label(value))
}

pub struct Ctx<'a> {
    pub backend: &'a Backend,
    pub window: Window,
    pub include_review: bool,
    /// Notes about figures that cover less than the window asked for.
    gaps: RefCell<Vec<String>>,
}

impl<'a> Ctx<'a> {
    pub fn new(backend: &'a Backend, window: Window, include_review: bool) -> Self {
        Self {
            backend,
            window,
            include_review,
            gaps: RefCell::new(Vec::new()),
        }
    }

    fn note_gap(&self, note: String) {
        let mut gaps = self.gaps.borrow_mut();
        if !gaps.contains(&note) {
            gaps.push(note);
        }
    }

    fn take_gaps(&self) -> Vec<String> {
        std::mem::take(&mut *self.gaps.borrow_mut())
    }

    /// `metric{review_run!="1",extra...}`; the review filter is left out under
    /// `--include-review`. Token counts also drop the cache types.
    pub fn selector(&self, metric: &str, extra: &[&str]) -> String {
        let mut matchers: Vec<&str> = Vec::new();
        if !self.include_review {
            matchers.push(EXCLUDE);
        }
        if metric == TOKENS {
            matchers.push(NO_CACHE_TOKENS);
        }
        matchers.extend_from_slice(extra);
        if matchers.is_empty() {
            metric.to_owned()
        } else {
            format!("{metric}{{{}}}", matchers.join(","))
        }
    }

    pub fn instant(&self, query: &str) -> Result<Vec<Sample>, Error> {
        self.backend.prom_instant(query, self.window.end)
    }

    pub fn scalar(&self, query: &str) -> Result<Option<f64>, Error> {
        Ok(self.instant(query)?.first().map(|s| s.value))
    }

    pub fn increase_sum(&self, metric: &str) -> Result<Option<f64>, Error> {
        self.scalar(&format!(
            "sum(increase({}[{}]))",
            self.selector(metric, &[]),
            self.window.prom()
        ))
    }

    /// LogQL for one event name, with the review exclusion.
    pub fn logql(&self, service: &str, event: &str) -> String {
        let filter = if self.include_review {
            String::new()
        } else {
            format!(" | {EXCLUDE}")
        };
        format!(
            "{{service_name=\"{}\"}} | event_name=\"{}\"{filter}",
            escape_label(service),
            escape_label(event)
        )
    }

    /// Every record of the window, paged; a cap stopping the fetch early is
    /// recorded as a gap that the report carries.
    pub fn logs(&self, logql: &str) -> Result<Vec<LogRecord>, Error> {
        let end = self.window.end_unix().saturating_mul(1_000_000_000);
        let start = self.window.start_unix().saturating_mul(1_000_000_000);
        let fetched = self.backend.loki_paged(
            logql,
            start,
            end,
            LogFetch {
                page_size: LOG_PAGE_SIZE,
                max_records: MAX_LOG_RECORDS,
                max_pages: MAX_LOG_PAGES,
            },
        )?;
        if fetched.truncated {
            self.note_gap(format!(
                "loki: stopped at {MAX_LOG_RECORDS} records or {MAX_LOG_PAGES} pages; figures cover only the oldest part of the window"
            ));
        }
        for gap in fetched.gaps {
            self.note_gap(gap);
        }
        Ok(fetched.records)
    }

    /// What the unattended review's own runs spent in the window, or `None` when
    /// they are included in the figures anyway.
    pub fn own_cost(&self) -> Option<Value> {
        if self.include_review {
            return None;
        }
        Some(own_cost_of(self.backend, self.window))
    }
}

pub fn own_cost_of(backend: &Backend, window: Window) -> Value {
    let spent = |metric: &str| -> Result<Option<f64>, Error> {
        let cache_filter = if metric == TOKENS {
            format!(",{NO_CACHE_TOKENS}")
        } else {
            String::new()
        };
        let query = format!(
            "sum(increase({metric}{{review_run=\"1\"{cache_filter}}}[{}]))",
            window.prom()
        );
        Ok(backend
            .prom_instant(&query, window.end)?
            .first()
            .map(|s| s.value))
    };
    let figure_of = |metric: &str| match spent(metric) {
        Ok(value) => figure(value, "no review-run samples in the window"),
        Err(e) => figure(None, &e.to_string()),
    };
    json!({"tokens": figure_of(TOKENS), "est_cost_usd": figure_of(COST)})
}

pub fn with_own_cost(ctx: &Ctx, mut report: Report) -> Report {
    if let Some(own) = ctx.own_cost() {
        report.fields.insert("own_cost".to_owned(), own);
    }
    report
}

pub fn parse_f64(record: &LogRecord, field: &str) -> Option<f64> {
    record.fields.get(field).and_then(|v| v.parse().ok())
}

/// Flags a pack command would silently lose: the window and the review filter
/// come from the digest or compare call, and the digest sets its own bounds.
const PACK_FORBIDDEN_FLAGS: [&str; 6] = [
    "--since",
    "--until",
    "--include-review",
    "--max-bytes",
    "--offset",
    "--format",
];

pub fn question_cli(question: &Question) -> Result<Cli, Error> {
    let query_error = |reason: String| Error::QueryCommand {
        id: question.id.clone(),
        command: question.query.command.clone(),
        reason,
    };
    for token in question.query.command.split_whitespace() {
        let flag = token.split('=').next().unwrap_or(token);
        if PACK_FORBIDDEN_FLAGS.contains(&flag) {
            return Err(query_error(format!(
                "{flag} is not supported in a pack command; the digest and compare set the window and bounds"
            )));
        }
    }
    Cli::try_parse_from(question.query.command.split_whitespace()).map_err(|e| {
        Error::QueryCommand {
            id: question.id.clone(),
            command: question.query.command.clone(),
            reason: e.to_string(),
        }
    })
}

pub fn run_query(ctx: &Ctx, command: &Command) -> Result<Report, Error> {
    let report = query_report(ctx, command)?;
    if matches!(command, Command::Health) {
        return Ok(report);
    }
    Ok(with_own_cost(ctx, report))
}

/// The figures alone, without the review's own-cost field.
pub fn query_report(ctx: &Ctx, command: &Command) -> Result<Report, Error> {
    let mut report = match command {
        Command::Top { category, by, .. } => top::run(ctx, *category, *by)?,
        Command::Tool { name, .. } => tool::run(ctx, name)?,
        Command::Session { id, detail, .. } => session::run(ctx, id, *detail)?,
        Command::Recall { .. } => recall::run(ctx)?,
        Command::Repeats { min_count, .. } => repeats::run(ctx, *min_count)?,
        Command::Health => health::run(ctx)?,
        other => {
            return Err(Error::Usage {
                message: format!("{} is not a query command", other.name()),
                input: other.name().to_owned(),
            })
        }
    };
    let gaps = ctx.take_gaps();
    if !gaps.is_empty() {
        report.fields.insert("gaps".to_owned(), json!(gaps));
    }
    Ok(report)
}
