//! The review digest: a mechanical run of the question pack (`baseline`) and the
//! validator for a digest a model gathered (`validate`).
use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

use clap::ValueEnum;
use serde_json::{json, Map, Value};

use super::top::{rank, By, Category, Ranked};
use super::{health, own_cost_of, query_report, question_cli, Ctx, COST, TOKENS};
use crate::backend::Backend;
use crate::bounds::{figure, num};
use crate::error::Error;
use crate::pack::{load_decisions, regrown, Decision, Pack, Question};
use crate::window::{iso, parse_iso, Window};

const SCHEMA: u64 = 1;
const WEEK_SECS: f64 = 604_800.0;
const EFFECTIVE_BELOW: f64 = 0.8;
const MAX_STRING_CHARS: usize = 200;
const MAX_GAP_CHARS: usize = 200;
const MAX_TITLE_CHARS: usize = 120;
const MAX_IDENTIFIER_CHARS: usize = 80;
/// MCP tool names run past 80 characters and a repeats sequence joins several.
const MAX_ROW_KEY_CHARS: usize = 256;
const TOP_KEYS: [&str; 10] = [
    "schema",
    "stage1",
    "host",
    "period",
    "pack",
    "stack",
    "totals",
    "questions",
    "prior_decisions",
    "own_cost",
];
const QUESTION_KEYS: [&str; 6] = [
    "id",
    "title",
    "rows",
    "truncated",
    "unavailable",
    "suppressed",
];
const ROW_KEYS: [&str; 8] = [
    "key",
    "value",
    "share",
    "calls",
    "evidence",
    "regrowth_of",
    "pattern",
    "sessions",
];
const DECISION_KEYS: [&str; 5] = ["id", "status", "before", "after", "verdict"];

pub struct Opts {
    pub pack: PathBuf,
    pub decisions: Option<PathBuf>,
    pub window: Window,
    pub include_review: bool,
    pub max_bytes: usize,
}

pub struct Validated {
    pub digest: Value,
    pub evidence_checked: usize,
}

fn normalise(value: f64, unit: &str, window: Window) -> f64 {
    if unit.ends_with("/week") && window.secs > 0 {
        value * WEEK_SECS / window.secs as f64
    } else {
        value
    }
}

fn verdict(before: f64, after: Option<f64>) -> &'static str {
    match after {
        Some(a) if a <= before * EFFECTIVE_BELOW => "effective",
        Some(a) if a >= before => "ineffective",
        _ => "inconclusive",
    }
}

struct Answer {
    entry: Value,
    gaps: Vec<String>,
    current: BTreeMap<String, f64>,
}

fn answer(
    ctx: &Ctx,
    pack: &Pack,
    question: &Question,
    decisions: &[Decision],
) -> Result<Answer, Error> {
    let cli = question_cli(question)?;
    let report = query_report(ctx, &cli.command)?;
    let mut gaps: Vec<String> = report
        .fields
        .get("gaps")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .map(|g| format!("{}: {g}", question.id))
        .collect();
    let mut entry = Map::new();
    entry.insert("id".to_owned(), json!(question.id));
    entry.insert("title".to_owned(), json!(question.title));
    if let Some(why) = report.fields.get("unavailable").and_then(Value::as_str) {
        entry.insert("rows".to_owned(), json!([]));
        entry.insert("truncated".to_owned(), json!(false));
        entry.insert("unavailable".to_owned(), json!(why));
        gaps.push(format!("{}: {why}", question.id));
        return Ok(Answer {
            entry: Value::Object(entry),
            gaps,
            current: BTreeMap::new(),
        });
    }
    let current = super::compare::row_values(&report);
    let dismissed: Vec<&Decision> = decisions
        .iter()
        .filter(|d| d.decision == "dismiss")
        .filter(|d| d.metric.as_ref().is_some_and(|m| m.question == question.id))
        .collect();
    let mut suppressed = 0u64;
    let mut kept: Vec<Value> = Vec::new();
    for mut row in report.rows {
        let share = row.get("share").and_then(Value::as_f64);
        let calls = row.get("calls").and_then(Value::as_u64);
        let below_share =
            matches!((share, question.threshold.min_share), (Some(s), Some(m)) if s < m);
        let below_calls =
            matches!((calls, question.threshold.min_calls), (Some(c), Some(m)) if c < m);
        if below_share || below_calls {
            continue;
        }
        let key = row
            .get("key")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_owned();
        let value = row.get("value").and_then(Value::as_f64);
        let mut resurfaced = None;
        let mut hide = false;
        for decision in &dismissed {
            let Some(metric) = decision.metric.as_ref().filter(|m| m.key == key) else {
                continue;
            };
            let now = value.map(|v| normalise(v, &metric.unit, ctx.window));
            if now.is_some_and(|n| regrown(n, metric.baseline, pack.regrowth_factor)) {
                resurfaced = Some(decision.id.clone());
            } else {
                hide = true;
            }
        }
        if hide && resurfaced.is_none() {
            suppressed = suppressed.saturating_add(1);
            continue;
        }
        if let Some(object) = row.as_object_mut() {
            object.remove("detail");
            if let Some(id) = resurfaced {
                object.insert("regrowth_of".to_owned(), json!(id));
            }
        }
        kept.push(row);
    }
    let truncated = kept.len() > cli.limit;
    kept.truncate(cli.limit);
    entry.insert("rows".to_owned(), Value::Array(kept));
    entry.insert("truncated".to_owned(), json!(truncated));
    if suppressed > 0 {
        entry.insert("suppressed".to_owned(), json!(suppressed));
    }
    Ok(Answer {
        entry: Value::Object(entry),
        gaps,
        current,
    })
}

fn total(gaps: &mut Vec<String>, name: &str, result: Result<Option<f64>, Error>) -> Value {
    let why = match result {
        Ok(Some(v)) => return num(v),
        Ok(None) => "no samples in the window".to_owned(),
        Err(e) => e.to_string(),
    };
    gaps.push(format!("{name}: {why}"));
    figure(None, &why)
}

fn prior_decisions(
    decisions: &[Decision],
    current: &BTreeMap<(String, String), f64>,
    window: Window,
) -> Vec<Value> {
    decisions
        .iter()
        .filter(|d| d.acted_on.is_some())
        .filter_map(|d| {
            let metric = d.metric.as_ref()?;
            let now = current
                .get(&(metric.question.clone(), metric.key.clone()))
                .map(|v| normalise(*v, &metric.unit, window));
            Some(json!({
                "id": d.id,
                "status": "acted",
                "before": num(metric.baseline),
                "after": figure(now, "metric absent from this period"),
                "verdict": d.outcome.clone().unwrap_or_else(|| verdict(metric.baseline, now).to_owned()),
            }))
        })
        .collect()
}

fn fit(digest: &mut Value, max_bytes: usize) -> Result<(), Error> {
    loop {
        let size = serde_json::to_string(digest)
            .map_err(|source| Error::Render { source })?
            .len();
        if size <= max_bytes {
            return Ok(());
        }
        let biggest = digest
            .get_mut("questions")
            .and_then(Value::as_array_mut)
            .and_then(|qs| {
                qs.iter_mut()
                    .max_by_key(|q| q.get("rows").and_then(Value::as_array).map_or(0, Vec::len))
            });
        let popped = biggest.and_then(|q| {
            let rows = q.get_mut("rows").and_then(Value::as_array_mut)?;
            rows.pop()?;
            q.as_object_mut()?
                .insert("truncated".to_owned(), json!(true));
            Some(())
        });
        if popped.is_none() {
            return Err(Error::DigestInvalid {
                problems: vec![format!(
                    "the digest cannot be reduced under {max_bytes} bytes"
                )],
            });
        }
    }
}

pub fn baseline(backend: &Backend, opts: &Opts) -> Result<Value, Error> {
    let pack = Pack::load(&opts.pack)?;
    let decisions_dir = opts.decisions.clone().unwrap_or_else(|| {
        opts.pack
            .parent()
            .map_or_else(|| PathBuf::from("decisions"), |p| p.join("decisions"))
    });
    let decisions = load_decisions(&decisions_dir)?;
    let ctx = Ctx::new(backend, opts.window, opts.include_review);
    let mut gaps: Vec<String> = Vec::new();
    let sessions = ctx.scalar(&format!(
        "count(sum by (session_id)(increase({}[{}])) > 0)",
        ctx.selector(TOKENS, &[]),
        ctx.window.prom()
    ));
    let totals = json!({
        "tokens": total(&mut gaps, "totals.tokens", ctx.increase_sum(TOKENS)),
        "est_cost_usd": total(&mut gaps, "totals.est_cost_usd", ctx.increase_sum(COST)),
        "sessions": total(&mut gaps, "totals.sessions", sessions),
    });
    let state = health::state(&ctx);
    if !state.stores_ok() {
        gaps.push("a store is not ready; see `cc-obs-query health`".to_owned());
    }
    let mut questions = Vec::new();
    let mut current: BTreeMap<(String, String), f64> = BTreeMap::new();
    for question in &pack.questions {
        match answer(&ctx, &pack, question, &decisions) {
            Ok(done) => {
                gaps.extend(done.gaps);
                current.extend(
                    done.current
                        .into_iter()
                        .map(|(key, value)| ((question.id.clone(), key), value)),
                );
                questions.push(done.entry);
            }
            Err(e) => {
                gaps.push(format!("{}: {e}", question.id));
                questions.push(json!({
                    "id": question.id,
                    "title": question.title,
                    "rows": [],
                    "truncated": false,
                    "unavailable": e.to_string(),
                }));
            }
        }
    }
    let mut digest = json!({
        "schema": SCHEMA,
        "stage1": "baseline",
        "host": backend.endpoints.host,
        "period": {
            "start": iso(opts.window.start_unix()),
            "end": iso(opts.window.end_unix()),
        },
        "pack": {"version": pack.version, "sha": pack.sha},
        "stack": {
            "stores_ok": state.stores_ok(),
            "guard": state.guard.unwrap_or("unknown"),
            "gaps": gaps,
        },
        "totals": totals,
        "questions": questions,
        "prior_decisions": prior_decisions(&decisions, &current, opts.window),
        "own_cost": own_cost_of(backend, opts.window),
    });
    fit(&mut digest, opts.max_bytes)?;
    Ok(digest)
}

fn require<'a>(digest: &'a Value, path: &str, problems: &mut Vec<String>) -> Option<&'a Value> {
    let found = path
        .split('.')
        .try_fold(digest, |value, key| value.get(key));
    if found.is_none() {
        problems.push(format!("missing {path}"));
    }
    found
}

fn check_schema(digest: &Value, problems: &mut Vec<String>) {
    if digest.get("schema").and_then(Value::as_u64) != Some(SCHEMA) {
        problems.push(format!("schema must be {SCHEMA}"));
    }
    if !matches!(
        digest.get("stage1").and_then(Value::as_str),
        Some("model" | "baseline")
    ) {
        problems.push("stage1 must be \"model\" or \"baseline\"".to_owned());
    }
    for path in ["host", "pack.sha", "stack.guard"] {
        if require(digest, path, problems).is_some_and(|v| !v.is_string()) {
            problems.push(format!("{path} must be a string"));
        }
    }
    for path in ["period.start", "period.end"] {
        let ok = require(digest, path, problems)
            .and_then(Value::as_str)
            .and_then(parse_iso)
            .is_some();
        if !ok {
            problems.push(format!("{path} must be an ISO 8601 UTC timestamp"));
        }
    }
    if require(digest, "stack.stores_ok", problems).is_some_and(|v| !v.is_boolean()) {
        problems.push("stack.stores_ok must be a boolean".to_owned());
    }
    for path in ["stack.gaps", "questions", "prior_decisions"] {
        if require(digest, path, problems).is_some_and(|v| !v.is_array()) {
            problems.push(format!("{path} must be an array"));
        }
    }
    for path in ["totals", "own_cost", "pack"] {
        if require(digest, path, problems).is_some_and(|v| !v.is_object()) {
            problems.push(format!("{path} must be an object"));
        }
    }
    let questions = digest
        .get("questions")
        .and_then(Value::as_array)
        .map(Vec::as_slice)
        .unwrap_or_default();
    for (index, question) in questions.iter().enumerate() {
        for field in ["id", "title"] {
            if !question.get(field).is_some_and(Value::is_string) {
                problems.push(format!("questions[{index}].{field} must be a string"));
            }
        }
        if !question.get("truncated").is_some_and(Value::is_boolean) {
            problems.push(format!("questions[{index}].truncated must be a boolean"));
        }
        let rows = question.get("rows").and_then(Value::as_array);
        let Some(rows) = rows else {
            problems.push(format!("questions[{index}].rows must be an array"));
            continue;
        };
        for (r, row) in rows.iter().enumerate() {
            if !row.get("key").is_some_and(Value::is_string) || row.get("value").is_none() {
                problems.push(format!(
                    "questions[{index}].rows[{r}] needs a string key and a value"
                ));
            }
        }
    }
}

fn is_identifier(text: &str, max_chars: usize) -> bool {
    (1..=max_chars).contains(&text.chars().count())
        && text
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || "_.:/@+>-".contains(c))
}

fn check_text(path: &str, value: Option<&Value>, max_chars: usize, problems: &mut Vec<String>) {
    let Some(text) = value.and_then(Value::as_str) else {
        return;
    };
    if text.chars().count() > max_chars || text.chars().any(char::is_control) {
        problems.push(format!(
            "{path}: free text must be at most {max_chars} characters on one line"
        ));
    }
}

fn check_identifier(path: &str, value: Option<&Value>, problems: &mut Vec<String>) {
    if value
        .and_then(Value::as_str)
        .is_some_and(|text| !is_identifier(text, MAX_IDENTIFIER_CHARS))
    {
        problems.push(format!(
            "{path}: must be an identifier of at most {MAX_IDENTIFIER_CHARS} characters from [A-Za-z0-9_.:/@+>-], not prose"
        ));
    }
}

/// The keys of `value`, each checked against the allowlist. Keys are compared
/// exactly, so `Prompt` and `PROMPT` are unknown like `prompt`.
fn only_keys<'a>(
    value: Option<&'a Value>,
    path: &str,
    allowed: &[&str],
    problems: &mut Vec<String>,
) -> Option<&'a Map<String, Value>> {
    let map = value?.as_object()?;
    for key in map.keys().filter(|k| !allowed.contains(&k.as_str())) {
        problems.push(format!(
            "{path}.{key}: field {key:?} is not in the digest schema (allowed: {})",
            allowed.join(", ")
        ));
    }
    Some(map)
}

/// A figure: a number, or `{"value": null, "unavailable": why}`.
fn check_figure(path: &str, value: Option<&Value>, problems: &mut Vec<String>) {
    let Some(value) = value else { return };
    match value {
        Value::Null | Value::Number(_) => {}
        Value::Object(_) => {
            let map = only_keys(Some(value), path, &["value", "unavailable"], problems);
            if !map
                .and_then(|m| m.get("value"))
                .is_some_and(|v| v.is_null() || v.is_number())
            {
                problems.push(format!("{path}.value: must be a number or null"));
            }
            let why = map.and_then(|m| m.get("unavailable"));
            if why.is_some_and(|w| !w.is_string()) {
                problems.push(format!("{path}.unavailable: must be a string"));
            }
            check_text(
                &format!("{path}.unavailable"),
                why,
                MAX_STRING_CHARS,
                problems,
            );
        }
        _ => problems.push(format!(
            "{path}: must be a number, null or {{value, unavailable}}, not text"
        )),
    }
}

fn check_unsigned(path: &str, value: Option<&Value>, problems: &mut Vec<String>) {
    if value.is_some_and(|v| v.as_u64().is_none()) {
        problems.push(format!("{path}: must be an unsigned integer"));
    }
}

/// The digest is an allowlist: unknown fields are rejected, and every string that
/// is not a number-like figure is an identifier or a short single-line note.
fn check_content(digest: &Value, problems: &mut Vec<String>) {
    let top = only_keys(Some(digest), "$", &TOP_KEYS, problems);
    let get = |name: &str| top.and_then(|t| t.get(name));
    check_identifier("host", get("host"), problems);
    for (name, allowed) in [
        ("period", &["start", "end"][..]),
        ("pack", &["version", "sha"][..]),
        ("stack", &["stores_ok", "guard", "gaps"][..]),
        ("totals", &["tokens", "est_cost_usd", "sessions"][..]),
        ("own_cost", &["tokens", "est_cost_usd"][..]),
    ] {
        let Some(section) = only_keys(get(name), name, allowed, problems) else {
            continue;
        };
        if name == "totals" || name == "own_cost" {
            for (key, figure) in section {
                check_figure(&format!("{name}.{key}"), Some(figure), problems);
            }
        }
    }
    if digest
        .pointer("/pack/version")
        .is_some_and(|v| !v.is_number())
    {
        problems.push("pack.version: must be a number".to_owned());
    }
    check_identifier("pack.sha", digest.pointer("/pack/sha"), problems);
    check_identifier("stack.guard", digest.pointer("/stack/guard"), problems);
    let gaps = digest.pointer("/stack/gaps").and_then(Value::as_array);
    for (index, gap) in gaps.into_iter().flatten().enumerate() {
        check_text(
            &format!("stack.gaps[{index}]"),
            Some(gap),
            MAX_GAP_CHARS,
            problems,
        );
    }
    let questions = get("questions").and_then(Value::as_array);
    for (index, question) in questions.into_iter().flatten().enumerate() {
        let path = format!("questions[{index}]");
        let Some(map) = only_keys(Some(question), &path, &QUESTION_KEYS, problems) else {
            continue;
        };
        check_identifier(&format!("{path}.id"), map.get("id"), problems);
        check_text(
            &format!("{path}.title"),
            map.get("title"),
            MAX_TITLE_CHARS,
            problems,
        );
        check_text(
            &format!("{path}.unavailable"),
            map.get("unavailable"),
            MAX_STRING_CHARS,
            problems,
        );
        let rows = map.get("rows").and_then(Value::as_array);
        for (r, row) in rows.into_iter().flatten().enumerate() {
            let row_path = format!("{path}.rows[{r}]");
            let Some(row_map) = only_keys(Some(row), &row_path, &ROW_KEYS, problems) else {
                continue;
            };
            check_row_key(&row_path, row_map, problems);
            for field in ["pattern", "regrowth_of"] {
                check_identifier(&format!("{row_path}.{field}"), row_map.get(field), problems);
            }
            for field in ["value", "share", "calls"] {
                check_figure(&format!("{row_path}.{field}"), row_map.get(field), problems);
            }
            check_unsigned(
                &format!("{row_path}.sessions"),
                row_map.get("sessions"),
                problems,
            );
        }
        check_unsigned(
            &format!("{path}.suppressed"),
            map.get("suppressed"),
            problems,
        );
    }
    let prior = get("prior_decisions").and_then(Value::as_array);
    for (index, decision) in prior.into_iter().flatten().enumerate() {
        let path = format!("prior_decisions[{index}]");
        let Some(map) = only_keys(Some(decision), &path, &DECISION_KEYS, problems) else {
            continue;
        };
        for field in ["id", "status", "verdict"] {
            check_identifier(&format!("{path}.{field}"), map.get(field), problems);
        }
        for field in ["before", "after"] {
            check_figure(&format!("{path}.{field}"), map.get(field), problems);
        }
    }
    check_strings(digest, "$", MAX_STRING_CHARS, problems);
}

/// A row key is an identifier, or the very name its evidence reference cites (the
/// evidence check then proves that name exists in the stores).
fn check_row_key(path: &str, row: &Map<String, Value>, problems: &mut Vec<String>) {
    let Some(key) = row.get("key").and_then(Value::as_str) else {
        return;
    };
    let cited = row
        .get("evidence")
        .and_then(Value::as_str)
        .and_then(|e| e.split_once(':'))
        .map(|(_, name)| name);
    if !is_identifier(key, MAX_ROW_KEY_CHARS) && cited != Some(key) {
        problems.push(format!(
            "{path}.key: must be an identifier of at most {MAX_ROW_KEY_CHARS} characters from [A-Za-z0-9_.:/@+>-] or the name its evidence cites, not prose"
        ));
    }
}

fn check_strings(value: &Value, path: &str, max_chars: usize, problems: &mut Vec<String>) {
    match value {
        Value::Object(map) => {
            for (key, child) in map {
                let limit = if key == "key" {
                    MAX_ROW_KEY_CHARS
                } else {
                    MAX_STRING_CHARS
                };
                check_strings(child, &format!("{path}.{key}"), limit, problems);
            }
        }
        Value::Array(items) => {
            for (index, child) in items.iter().enumerate() {
                check_strings(child, &format!("{path}[{index}]"), max_chars, problems);
            }
        }
        Value::String(text) if text.chars().count() > max_chars || text.contains('\n') => {
            problems.push(format!("{path}: content-like string (long or multi-line)"));
        }
        _ => {}
    }
}

fn evidence_refs(digest: &Value) -> Vec<String> {
    digest
        .get("questions")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|q| q.get("rows").and_then(Value::as_array))
        .flatten()
        .filter_map(|row| row.get("evidence").and_then(Value::as_str))
        .map(str::to_owned)
        .collect()
}

fn check_evidence(
    backend: &Backend,
    digest: &Value,
    opts: &Opts,
    problems: &mut Vec<String>,
) -> usize {
    let refs = evidence_refs(digest);
    let period = digest.get("period");
    let at = |field: &str| {
        period
            .and_then(|p| p.get(field))
            .and_then(Value::as_str)
            .and_then(parse_iso)
    };
    let window = match (at("start"), at("end")) {
        (Some(start), Some(end)) if end > start => Window {
            secs: end.saturating_sub(start).unsigned_abs(),
            end: Some(end),
        },
        _ => opts.window,
    };
    let ctx = Ctx::new(backend, window, opts.include_review);
    let mut known: BTreeMap<String, Result<BTreeSet<String>, String>> = BTreeMap::new();
    for reference in &refs {
        let Some((kind, value)) = reference.split_once(':') else {
            problems.push(format!("evidence {reference:?} is not <kind>:<value>"));
            continue;
        };
        let Ok(category) = Category::from_str(kind, true) else {
            problems.push(format!("evidence {reference:?} has an unknown kind"));
            continue;
        };
        let keys = known.entry(kind.to_owned()).or_insert_with(|| {
            match rank(&ctx, category, By::Tokens) {
                Ok(Ranked::Rows(rows)) => Ok(rows.into_iter().map(|r| r.key).collect()),
                Ok(Ranked::Unavailable(_)) => Ok(BTreeSet::new()),
                Err(e) => Err(e.to_string()),
            }
        });
        match keys {
            Ok(set) if set.contains(value) => {}
            Ok(_) => problems.push(format!(
                "evidence {reference:?} does not exist in the stores for the period"
            )),
            Err(why) => problems.push(format!(
                "evidence {reference:?} could not be checked: {why}"
            )),
        }
    }
    refs.len()
}

pub fn validate(backend: &Backend, file: &Path, opts: &Opts) -> Result<Validated, Error> {
    let text = std::fs::read_to_string(file).map_err(|source| Error::DigestRead {
        path: file.to_owned(),
        source,
    })?;
    let digest: Value = serde_json::from_str(&text).map_err(|source| Error::DigestParse {
        path: file.to_owned(),
        source,
    })?;
    let mut problems = Vec::new();
    if text.len() > opts.max_bytes {
        problems.push(format!(
            "the digest is {} bytes, over the {} byte limit",
            text.len(),
            opts.max_bytes
        ));
    }
    check_schema(&digest, &mut problems);
    check_content(&digest, &mut problems);
    let evidence_checked = check_evidence(backend, &digest, opts, &mut problems);
    if !problems.is_empty() {
        return Err(Error::DigestInvalid { problems });
    }
    Ok(Validated {
        digest,
        evidence_checked,
    })
}
