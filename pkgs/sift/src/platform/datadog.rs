use crate::auth::DatadogAuth;
use crate::event::Event;
use chrono::{DateTime, TimeZone, Utc};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::thread;
use std::time::Duration;
use thiserror::Error;

/// Datadog's v2 logs/spans search endpoints paginate via a `page.limit`
/// this crate has not independently confirmed a hard maximum for; 1000
/// matches the documented default/common ceiling for both endpoints and
/// keeps each page well under Datadog's response-size limits.
const PAGE_LIMIT: usize = 1000;

/// Default `--max-events` for a reduction mode (aggregate/topn/histogram/
/// diff): without a bound, a broad query would page against a live
/// Datadog org indefinitely. 5000 events is enough to make any of the
/// reduction modes meaningful while keeping one `sift` invocation to a
/// handful of paginated requests.
pub const DEFAULT_MAX_EVENTS: usize = 5000;

/// Total attempts (the original send plus retries) `send_with_retry` will
/// make before giving up: enough to ride out a short blip (a 429 near its
/// reset, a couple of 5xx flaps) without turning a large `--max-events`
/// fetch into an indefinite hang when the endpoint is genuinely down.
const RETRY_MAX_ATTEMPTS: u32 = 4;

/// Ceiling on any single retry wait, whether driven by Datadog's own
/// `X-RateLimit-Reset` or by exponential backoff: Datadog's documented
/// rate-limit windows are minute-scale, so a single wait longer than this
/// would stall a page fetch far past the point a fresh attempt is likely
/// to succeed.
const RETRY_MAX_WAIT: Duration = Duration::from_secs(60);

/// Datadog's v2 API error envelope on a non-2xx response (JSON:API
/// style: `{"errors":[{"title":...,"detail":...}]}`), or occasionally
/// present even on a 200 that still failed to produce a result. Both
/// logs and spans search share this shape.
#[derive(Debug, Deserialize)]
struct ApiErrorDetail {
    #[serde(default)]
    title: Option<String>,
    #[serde(default)]
    detail: Option<String>,
}

fn format_api_errors(errors: &[ApiErrorDetail]) -> String {
    errors
        .iter()
        .map(|e| {
            let title = e.title.as_deref().unwrap_or("error");
            match &e.detail {
                Some(detail) => format!("{title}: {detail}"),
                None => title.to_string(),
            }
        })
        .collect::<Vec<_>>()
        .join("; ")
}

#[derive(Debug, Error)]
pub enum DatadogError {
    #[error("sending Datadog logs search request: {0}")]
    LogsRequestFailed(reqwest::Error),
    #[error("reading Datadog logs search response body: {0}")]
    LogsResponseReadFailed(reqwest::Error),
    #[error("Datadog logs search returned status {status}: {body}")]
    LogsStatus { status: u16, body: String },
    #[error("Datadog logs search was rate limited; X-RateLimit-Reset: {reset:?}")]
    LogsRateLimited { reset: Option<String> },
    #[error("parsing Datadog logs search response: {0}")]
    LogsParse(serde_json::Error),
    #[error("Datadog logs search reported an API error: {0}")]
    LogsApiError(String),
    #[error("Datadog log entry had a missing or malformed timestamp: {0:?}")]
    LogsMalformedTimestamp(String),

    #[error("sending Datadog metrics query request: {0}")]
    MetricsRequestFailed(reqwest::Error),
    #[error("reading Datadog metrics query response body: {0}")]
    MetricsResponseReadFailed(reqwest::Error),
    #[error("Datadog metrics query returned status {status}: {body}")]
    MetricsStatus { status: u16, body: String },
    #[error("Datadog metrics query was rate limited; X-RateLimit-Reset: {reset:?}")]
    MetricsRateLimited { reset: Option<String> },
    #[error("parsing Datadog metrics query response: {0}")]
    MetricsParse(serde_json::Error),
    #[error("Datadog metrics query reported status {status:?}: {message}")]
    MetricsApiError { status: String, message: String },
    #[error("Datadog metric point had a malformed timestamp: {0:?}")]
    MetricsMalformedTimestamp(String),

    #[error("sending Datadog spans search request: {0}")]
    TracesRequestFailed(reqwest::Error),
    #[error("reading Datadog spans search response body: {0}")]
    TracesResponseReadFailed(reqwest::Error),
    #[error("Datadog spans search returned status {status}: {body}")]
    TracesStatus { status: u16, body: String },
    #[error("Datadog spans search was rate limited; X-RateLimit-Reset: {reset:?}")]
    TracesRateLimited { reset: Option<String> },
    #[error("parsing Datadog spans search response: {0}")]
    TracesParse(serde_json::Error),
    #[error("Datadog spans search reported an API error: {0}")]
    TracesApiError(String),
    #[error("Datadog span had a missing or malformed timestamp: {0:?}")]
    TracesMalformedTimestamp(String),
}

/// Builds the API base URL for a Datadog site, e.g. "datadoghq.com" ->
/// "https://api.datadoghq.com", "us3.datadoghq.com" ->
/// "https://api.us3.datadoghq.com". See
/// https://docs.datadoghq.com/getting_started/site/.
pub fn base_url(site: &str) -> String {
    format!("https://api.{site}")
}

/// A truncated non-2xx response body is more useful in an error message
/// than either the full body (which can be a multi-MB HTML error page
/// from an intermediate proxy) or nothing at all.
const ERROR_BODY_TRUNCATE_BYTES: usize = 2048;

fn truncate_body(body: &str) -> String {
    if body.len() <= ERROR_BODY_TRUNCATE_BYTES {
        return body.to_string();
    }
    let mut end = ERROR_BODY_TRUNCATE_BYTES;
    while end > 0 && !body.is_char_boundary(end) {
        end = end.saturating_sub(1);
    }
    // `end` is walked backward until `is_char_boundary` holds, so this
    // slice is always on a valid UTF-8 boundary.
    #[allow(clippy::indexing_slicing)]
    let mut truncated = body[..end].to_string();
    truncated.push_str("... [truncated]");
    truncated
}

enum HttpFailure {
    RateLimited(Option<String>),
    Status(u16, String),
}

/// What `send_with_retry` reports after retries are exhausted (or a
/// non-retryable failure hits immediately): `HttpFailure` plus the case
/// `check_response` never sees — a `reqwest` send error.
enum RetryFailure {
    RateLimited(Option<String>),
    Status(u16, String),
    Send(reqwest::Error),
}

/// Whether a non-2xx status is worth retrying: rate limiting and
/// server-side failures are typically transient, everything else (a
/// malformed query, bad auth, a missing resource) will fail identically
/// on the next attempt.
fn is_retryable_status(status: u16) -> bool {
    matches!(status, 429 | 500 | 502 | 503 | 504)
}

/// How long to wait before the next attempt. On a 429 with a parseable
/// `X-RateLimit-Reset` (Datadog sends this as seconds until the limit
/// resets), honor it; otherwise fall back to exponential backoff from 1s,
/// doubling per attempt. Either way the wait is capped at
/// `RETRY_MAX_WAIT`. `attempt` is the 1-based count of the attempt that
/// just failed.
fn backoff_delay(attempt: u32, reset_header: Option<&str>) -> Duration {
    if let Some(reset) = reset_header {
        if let Ok(secs) = reset.trim().parse::<u64>() {
            // A reset of 0 would retry instantly and almost certainly hit
            // the same limit again, so wait at least one second.
            return Duration::from_secs(secs.max(1)).min(RETRY_MAX_WAIT);
        }
    }
    let exponent = attempt.saturating_sub(1);
    let secs = 1u64.checked_shl(exponent).unwrap_or(u64::MAX);
    Duration::from_secs(secs).min(RETRY_MAX_WAIT)
}

/// Sends a request built fresh on each attempt (auth applied here, once
/// per attempt), retrying on a 429, a 5xx in `is_retryable_status`, or a
/// `reqwest` send error that is a timeout or connection failure. Any
/// other 4xx, or a non-retryable send error, returns immediately. Shared
/// by `fetch_logs`/`fetch_metrics`/`fetch_traces` so all three Datadog
/// endpoints retry the same way.
fn send_with_retry<F>(
    endpoint: &'static str,
    auth: &DatadogAuth,
    build_request: F,
) -> Result<reqwest::blocking::Response, RetryFailure>
where
    F: Fn() -> reqwest::blocking::RequestBuilder,
{
    let mut attempt: u32 = 1;
    loop {
        let request = auth.apply(build_request());
        match request.send() {
            Ok(response) => match check_response(response) {
                Ok(response) => return Ok(response),
                Err(HttpFailure::RateLimited(reset)) => {
                    if attempt >= RETRY_MAX_ATTEMPTS {
                        return Err(RetryFailure::RateLimited(reset));
                    }
                    let wait = backoff_delay(attempt, reset.as_deref());
                    tracing::warn!(
                        endpoint,
                        attempt,
                        status = 429,
                        wait_secs = wait.as_secs(),
                        "Datadog request rate limited; retrying"
                    );
                    thread::sleep(wait);
                    attempt = attempt.saturating_add(1);
                }
                Err(HttpFailure::Status(status, body)) => {
                    if !is_retryable_status(status) || attempt >= RETRY_MAX_ATTEMPTS {
                        return Err(RetryFailure::Status(status, body));
                    }
                    let wait = backoff_delay(attempt, None);
                    tracing::warn!(
                        endpoint,
                        attempt,
                        status,
                        wait_secs = wait.as_secs(),
                        "Datadog request failed with a retryable status; retrying"
                    );
                    thread::sleep(wait);
                    attempt = attempt.saturating_add(1);
                }
            },
            Err(send_err) => {
                let retryable = send_err.is_timeout() || send_err.is_connect();
                if !retryable || attempt >= RETRY_MAX_ATTEMPTS {
                    return Err(RetryFailure::Send(send_err));
                }
                let error_kind = if send_err.is_timeout() { "timeout" } else { "connect" };
                let wait = backoff_delay(attempt, None);
                tracing::warn!(
                    endpoint,
                    attempt,
                    error_kind,
                    wait_secs = wait.as_secs(),
                    "Datadog request send failed; retrying"
                );
                thread::sleep(wait);
                attempt = attempt.saturating_add(1);
            }
        }
    }
}

fn check_response(
    response: reqwest::blocking::Response,
) -> Result<reqwest::blocking::Response, HttpFailure> {
    let status = response.status();
    if status.is_success() {
        return Ok(response);
    }
    if status.as_u16() == 429 {
        let reset = response
            .headers()
            .get("x-ratelimit-reset")
            .and_then(|value| value.to_str().ok())
            .map(str::to_string);
        return Err(HttpFailure::RateLimited(reset));
    }
    let body = match response.text() {
        Ok(body) => truncate_body(&body),
        Err(read_err) => format!("<failed to read error response body: {read_err}>"),
    };
    Err(HttpFailure::Status(status.as_u16(), body))
}

/// Splits a Datadog tag ("key:value") into a label pair on its first
/// colon. A tag with no colon (a bare boolean-style tag, e.g.
/// "maintenance") becomes a label with an empty value rather than being
/// dropped — its presence is still meaningful for aggregate/topn
/// grouping.
fn tag_to_label(tag: &str) -> (String, String) {
    match tag.split_once(':') {
        Some((key, value)) => (key.to_string(), value.to_string()),
        None => (tag.to_string(), String::new()),
    }
}

/// Datadog log/span attributes can nest arbitrarily deep; a real payload
/// is at most a handful of levels (e.g. `http.response.headers.x-foo`), so
/// capping recursion here bounds `flatten_attributes_into`'s stack depth
/// against a pathological or malicious payload without truncating anything
/// realistic.
const MAX_ATTRIBUTE_FLATTEN_DEPTH: usize = 8;

/// Flattens a Datadog `attributes` JSON object into label key/value pairs
/// for grouping: a nested object contributes dot-joined keys
/// (`http.status_code`), numbers and booleans become their string form,
/// strings pass through as-is, nulls are skipped, and an array joins its
/// scalar elements with `,` (an array element that is itself an object is
/// skipped, since it has no single scalar representation).
fn flatten_attributes_into(
    prefix: &str,
    map: &serde_json::Map<String, serde_json::Value>,
    depth: usize,
    out: &mut BTreeMap<String, String>,
) {
    if depth > MAX_ATTRIBUTE_FLATTEN_DEPTH {
        return;
    }
    for (key, value) in map {
        let full_key = if prefix.is_empty() { key.clone() } else { format!("{prefix}.{key}") };
        match value {
            serde_json::Value::Null => {}
            serde_json::Value::String(s) => {
                out.insert(full_key, s.clone());
            }
            serde_json::Value::Bool(b) => {
                out.insert(full_key, b.to_string());
            }
            serde_json::Value::Number(n) => {
                out.insert(full_key, n.to_string());
            }
            serde_json::Value::Object(nested) => {
                flatten_attributes_into(&full_key, nested, depth.saturating_add(1), out);
            }
            serde_json::Value::Array(items) => {
                let joined = items
                    .iter()
                    .filter_map(|item| match item {
                        serde_json::Value::String(s) => Some(s.clone()),
                        serde_json::Value::Bool(b) => Some(b.to_string()),
                        serde_json::Value::Number(n) => Some(n.to_string()),
                        _ => None,
                    })
                    .collect::<Vec<_>>()
                    .join(",");
                out.insert(full_key, joined);
            }
        }
    }
}

fn string_attributes(attributes: &serde_json::Map<String, serde_json::Value>) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    flatten_attributes_into("", attributes, 0, &mut out);
    out
}

// ---------------------------------------------------------------------
// Logs: POST /api/v2/logs/events/search
// ---------------------------------------------------------------------

#[derive(Serialize)]
struct TimeFilter<'a> {
    query: &'a str,
    from: String,
    to: String,
}

#[derive(Serialize)]
struct PageRequest<'a> {
    limit: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    cursor: Option<&'a str>,
}

#[derive(Serialize)]
struct LogsSearchRequest<'a> {
    filter: TimeFilter<'a>,
    page: PageRequest<'a>,
    sort: &'static str,
}

#[derive(Debug, Deserialize, Default)]
struct LogsSearchResponse {
    #[serde(default)]
    data: Vec<LogEntry>,
    #[serde(default)]
    meta: Option<LogsMeta>,
    #[serde(default)]
    errors: Option<Vec<ApiErrorDetail>>,
}

#[derive(Debug, Deserialize)]
struct LogEntry {
    #[serde(default)]
    attributes: LogEntryAttributes,
}

#[derive(Debug, Deserialize, Default)]
struct LogEntryAttributes {
    #[serde(default)]
    timestamp: Option<String>,
    #[serde(default)]
    message: Option<String>,
    #[serde(default)]
    status: Option<String>,
    #[serde(default)]
    service: Option<String>,
    #[serde(default)]
    host: Option<String>,
    #[serde(default)]
    tags: Vec<String>,
    #[serde(default)]
    attributes: serde_json::Map<String, serde_json::Value>,
}

#[derive(Debug, Deserialize)]
struct LogsMeta {
    #[serde(default)]
    page: Option<LogsMetaPage>,
}

#[derive(Debug, Deserialize)]
struct LogsMetaPage {
    #[serde(default)]
    after: Option<String>,
}

/// Parses one page of a Datadog `/api/v2/logs/events/search` JSON
/// response body into `Event`s plus the pagination cursor for the next
/// page, if any. Pure function — no I/O — testable against a fixture
/// string.
fn parse_logs_response(body: &str) -> Result<(Vec<Event>, Option<String>), DatadogError> {
    let parsed: LogsSearchResponse = serde_json::from_str(body).map_err(DatadogError::LogsParse)?;

    if let Some(errors) = &parsed.errors {
        if !errors.is_empty() {
            return Err(DatadogError::LogsApiError(format_api_errors(errors)));
        }
    }

    let mut events = Vec::new();
    for entry in parsed.data {
        let attrs = entry.attributes;
        let timestamp_str = attrs
            .timestamp
            .clone()
            .ok_or_else(|| DatadogError::LogsMalformedTimestamp("<missing>".to_string()))?;
        let timestamp = DateTime::parse_from_rfc3339(&timestamp_str)
            .map(|dt| dt.with_timezone(&Utc))
            .map_err(|_| DatadogError::LogsMalformedTimestamp(timestamp_str))?;

        let mut labels = string_attributes(&attrs.attributes);
        if let Some(status) = attrs.status {
            labels.insert("status".to_string(), status);
        }
        if let Some(service) = attrs.service {
            labels.insert("service".to_string(), service);
        }
        if let Some(host) = attrs.host {
            labels.insert("host".to_string(), host);
        }
        for tag in &attrs.tags {
            let (key, value) = tag_to_label(tag);
            labels.insert(key, value);
        }

        events.push(Event {
            timestamp,
            labels,
            value: None,
            body: attrs.message,
        });
    }

    let cursor = parsed.meta.and_then(|meta| meta.page).and_then(|page| page.after);
    Ok((events, cursor))
}

/// Queries a Datadog site's `/api/v2/logs/events/search` endpoint,
/// following the `meta.page.after` cursor until either `limit` events
/// have been collected or the API reports no further page. Not
/// unit-tested directly — a thin `reqwest` wrapper around
/// `parse_logs_response`, which carries the actual logic.
pub fn fetch_logs(
    base_url: &str,
    query: &str,
    start: DateTime<Utc>,
    end: DateTime<Utc>,
    limit: usize,
    auth: &DatadogAuth,
) -> Result<Vec<Event>, DatadogError> {
    let client = reqwest::blocking::Client::new();
    let url = format!("{base_url}/api/v2/logs/events/search");
    let from = start.to_rfc3339();
    let to = end.to_rfc3339();

    let mut events = Vec::new();
    let mut cursor: Option<String> = None;
    loop {
        let remaining = limit.saturating_sub(events.len());
        if remaining == 0 {
            break;
        }
        let page_limit = remaining.min(PAGE_LIMIT);
        let request_body = LogsSearchRequest {
            filter: TimeFilter { query, from: from.clone(), to: to.clone() },
            page: PageRequest { limit: page_limit, cursor: cursor.as_deref() },
            // Newest first: when a capped fetch stops early, the dropped
            // tail is the oldest part of the window, not the newest.
            sort: "-timestamp",
        };

        let response = send_with_retry("logs.search", auth, || client.post(&url).json(&request_body))
            .map_err(|failure| match failure {
                RetryFailure::RateLimited(reset) => DatadogError::LogsRateLimited { reset },
                RetryFailure::Status(status, body) => DatadogError::LogsStatus { status, body },
                RetryFailure::Send(err) => DatadogError::LogsRequestFailed(err),
            })?;

        let body = response.text().map_err(DatadogError::LogsResponseReadFailed)?;
        let (mut page_events, next_cursor) = parse_logs_response(&body)?;
        let page_was_empty = page_events.is_empty();
        events.append(&mut page_events);

        match next_cursor {
            Some(next) if !page_was_empty => cursor = Some(next),
            _ => break,
        }
    }

    Ok(events)
}

// ---------------------------------------------------------------------
// Metrics: GET /api/v1/query
// ---------------------------------------------------------------------

#[derive(Debug, Deserialize, Default)]
struct MetricsQueryResponse {
    #[serde(default)]
    status: Option<String>,
    #[serde(default)]
    error: Option<String>,
    #[serde(default)]
    series: Vec<MetricsSeries>,
}

#[derive(Debug, Deserialize)]
struct MetricsSeries {
    #[serde(default)]
    metric: Option<String>,
    #[serde(default)]
    scope: Option<String>,
    #[serde(default)]
    tag_set: Vec<String>,
    #[serde(default)]
    pointlist: Vec<Vec<Option<f64>>>,
}

fn timestamp_from_unix_millis(ms: f64) -> Result<DateTime<Utc>, DatadogError> {
    if !ms.is_finite() {
        return Err(DatadogError::MetricsMalformedTimestamp(ms.to_string()));
    }
    if ms < i64::MIN as f64 || ms > i64::MAX as f64 {
        return Err(DatadogError::MetricsMalformedTimestamp(ms.to_string()));
    }
    let whole_ms = ms.floor() as i64;
    let seconds = whole_ms.div_euclid(1000);
    let millis_remainder = whole_ms.rem_euclid(1000);
    #[allow(clippy::arithmetic_side_effects)] // millis_remainder is in [0, 1000) from rem_euclid, so this stays within [0, 999_000_000].
    let nanos = u32::try_from(millis_remainder).unwrap_or(0).saturating_mul(1_000_000);
    Utc.timestamp_opt(seconds, nanos)
        .single()
        .ok_or_else(|| DatadogError::MetricsMalformedTimestamp(ms.to_string()))
}

/// Parses a Datadog `/api/v1/query` JSON response body into `Event`s.
/// Pure function — no I/O — testable against a fixture string.
fn parse_metrics_response(body: &str) -> Result<Vec<Event>, DatadogError> {
    let parsed: MetricsQueryResponse = serde_json::from_str(body).map_err(DatadogError::MetricsParse)?;

    let status = parsed.status.unwrap_or_default();
    if status != "ok" {
        return Err(DatadogError::MetricsApiError {
            status,
            message: parsed.error.unwrap_or_else(|| "no error message provided".to_string()),
        });
    }

    let mut events = Vec::new();
    for series in parsed.series {
        let mut labels: BTreeMap<String, String> = series
            .tag_set
            .iter()
            .map(|tag| tag_to_label(tag))
            .collect();
        if let Some(metric) = &series.metric {
            labels.insert("metric".to_string(), metric.clone());
        }
        if let Some(scope) = &series.scope {
            labels.insert("scope".to_string(), scope.clone());
        }

        for point in series.pointlist {
            let ts_ms = point
                .first()
                .copied()
                .flatten()
                .ok_or_else(|| DatadogError::MetricsMalformedTimestamp("<missing>".to_string()))?;
            // A null value means Datadog has no sample at that point in
            // the series (a gap, e.g. from a rollup) — skip it rather
            // than fabricating a 0.
            let Some(value) = point.get(1).copied().flatten() else {
                continue;
            };

            events.push(Event {
                timestamp: timestamp_from_unix_millis(ts_ms)?,
                labels: labels.clone(),
                value: Some(value),
                body: None,
            });
        }
    }

    Ok(events)
}

/// Queries a Datadog site's `/api/v1/query` timeseries endpoint. Not
/// unit-tested directly, same rationale as `fetch_logs`.
pub fn fetch_metrics(
    base_url: &str,
    query: &str,
    from_unix_secs: i64,
    to_unix_secs: i64,
    auth: &DatadogAuth,
) -> Result<Vec<Event>, DatadogError> {
    let client = reqwest::blocking::Client::new();
    let url = format!("{base_url}/api/v1/query");
    let response = send_with_retry("metrics.query", auth, || {
        client.get(&url).query(&[
            ("query", query.to_string()),
            ("from", from_unix_secs.to_string()),
            ("to", to_unix_secs.to_string()),
        ])
    })
    .map_err(|failure| match failure {
        RetryFailure::RateLimited(reset) => DatadogError::MetricsRateLimited { reset },
        RetryFailure::Status(status, body) => DatadogError::MetricsStatus { status, body },
        RetryFailure::Send(err) => DatadogError::MetricsRequestFailed(err),
    })?;

    let body = response.text().map_err(DatadogError::MetricsResponseReadFailed)?;
    parse_metrics_response(&body)
}

// ---------------------------------------------------------------------
// Traces (spans): POST /api/v2/spans/events/search
// ---------------------------------------------------------------------

#[derive(Serialize)]
struct SpansSearchRequest<'a> {
    data: SpansSearchRequestData<'a>,
}

#[derive(Serialize)]
struct SpansSearchRequestData<'a> {
    #[serde(rename = "type")]
    kind: &'static str,
    attributes: SpansSearchRequestAttributes<'a>,
}

#[derive(Serialize)]
struct SpansSearchRequestAttributes<'a> {
    filter: TimeFilter<'a>,
    page: PageRequest<'a>,
    sort: &'static str,
}

#[derive(Debug, Deserialize, Default)]
struct SpansSearchResponse {
    #[serde(default)]
    data: Vec<SpanEntry>,
    #[serde(default)]
    meta: Option<LogsMeta>,
    #[serde(default)]
    errors: Option<Vec<ApiErrorDetail>>,
}

#[derive(Debug, Deserialize)]
struct SpanEntry {
    #[serde(default)]
    attributes: SpanEntryAttributes,
}

#[derive(Debug, Deserialize, Default)]
struct SpanEntryAttributes {
    #[serde(default)]
    start_timestamp: Option<String>,
    #[serde(default)]
    end_timestamp: Option<String>,
    #[serde(default)]
    service: Option<String>,
    #[serde(default)]
    resource_name: Option<String>,
    #[serde(default)]
    env: Option<String>,
    #[serde(default)]
    host: Option<String>,
    #[serde(default)]
    tags: Vec<String>,
    #[serde(default)]
    attributes: serde_json::Map<String, serde_json::Value>,
    /// Datadog's `SpansAttributes` carries both `attributes` and `custom`
    /// (a separate "JSON object of custom spans data" map, per
    /// DataDog/datadog-api-client-go's `model_spans_attributes.go`) —
    /// distinct maps, not a duplicate of the same data.
    #[serde(default)]
    custom: serde_json::Map<String, serde_json::Value>,
}

/// Derives a span's duration in milliseconds: prefer `end_timestamp -
/// start_timestamp` (both are RFC3339 in the API response), falling back
/// to a custom `duration` field (nanoseconds, the APM convention) —
/// checked in `custom` first, then `attributes` — when the endpoints
/// aren't both present.
fn span_duration_ms(attrs: &SpanEntryAttributes, start: DateTime<Utc>) -> Option<f64> {
    if let Some(end_str) = &attrs.end_timestamp {
        if let Ok(end) = DateTime::parse_from_rfc3339(end_str) {
            let end = end.with_timezone(&Utc);
            let millis = end.signed_duration_since(start).num_milliseconds();
            return Some(millis as f64);
        }
    }
    attrs
        .custom
        .get("duration")
        .or_else(|| attrs.attributes.get("duration"))
        .and_then(serde_json::Value::as_f64)
        .map(|ns| ns / 1_000_000.0)
}

/// Parses one page of a Datadog `/api/v2/spans/events/search` JSON
/// response body into `Event`s plus the pagination cursor for the next
/// page, if any. Pure function — no I/O — testable against a fixture
/// string.
fn parse_traces_response(body: &str) -> Result<(Vec<Event>, Option<String>), DatadogError> {
    let parsed: SpansSearchResponse = serde_json::from_str(body).map_err(DatadogError::TracesParse)?;

    if let Some(errors) = &parsed.errors {
        if !errors.is_empty() {
            return Err(DatadogError::TracesApiError(format_api_errors(errors)));
        }
    }

    let mut events = Vec::new();
    for entry in parsed.data {
        let attrs = entry.attributes;
        let start_str = attrs
            .start_timestamp
            .clone()
            .ok_or_else(|| DatadogError::TracesMalformedTimestamp("<missing>".to_string()))?;
        let start = DateTime::parse_from_rfc3339(&start_str)
            .map(|dt| dt.with_timezone(&Utc))
            .map_err(|_| DatadogError::TracesMalformedTimestamp(start_str))?;

        let value = span_duration_ms(&attrs, start);

        let mut labels = string_attributes(&attrs.attributes);
        flatten_attributes_into("", &attrs.custom, 0, &mut labels);
        if let Some(service) = &attrs.service {
            labels.insert("service".to_string(), service.clone());
        }
        if let Some(resource_name) = &attrs.resource_name {
            labels.insert("resource_name".to_string(), resource_name.clone());
        }
        if let Some(env) = &attrs.env {
            labels.insert("env".to_string(), env.clone());
        }
        if let Some(host) = &attrs.host {
            labels.insert("host".to_string(), host.clone());
        }
        for tag in &attrs.tags {
            let (key, value) = tag_to_label(tag);
            labels.insert(key, value);
        }

        events.push(Event { timestamp: start, labels, value, body: None });
    }

    let cursor = parsed.meta.and_then(|meta| meta.page).and_then(|page| page.after);
    Ok((events, cursor))
}

/// Queries a Datadog site's `/api/v2/spans/events/search` endpoint,
/// following the `meta.page.after` cursor exactly like `fetch_logs`. Not
/// unit-tested directly — a thin `reqwest` wrapper around
/// `parse_traces_response`.
pub fn fetch_traces(
    base_url: &str,
    query: &str,
    start: DateTime<Utc>,
    end: DateTime<Utc>,
    limit: usize,
    auth: &DatadogAuth,
) -> Result<Vec<Event>, DatadogError> {
    let client = reqwest::blocking::Client::new();
    let url = format!("{base_url}/api/v2/spans/events/search");
    let from = start.to_rfc3339();
    let to = end.to_rfc3339();

    let mut events = Vec::new();
    let mut cursor: Option<String> = None;
    loop {
        let remaining = limit.saturating_sub(events.len());
        if remaining == 0 {
            break;
        }
        let page_limit = remaining.min(PAGE_LIMIT);
        let request_body = SpansSearchRequest {
            data: SpansSearchRequestData {
                kind: "search_request",
                attributes: SpansSearchRequestAttributes {
                    filter: TimeFilter { query, from: from.clone(), to: to.clone() },
                    page: PageRequest { limit: page_limit, cursor: cursor.as_deref() },
                    sort: "-timestamp",
                },
            },
        };

        let response = send_with_retry("traces.search", auth, || client.post(&url).json(&request_body))
            .map_err(|failure| match failure {
                RetryFailure::RateLimited(reset) => DatadogError::TracesRateLimited { reset },
                RetryFailure::Status(status, body) => DatadogError::TracesStatus { status, body },
                RetryFailure::Send(err) => DatadogError::TracesRequestFailed(err),
            })?;

        let body = response.text().map_err(DatadogError::TracesResponseReadFailed)?;
        let (mut page_events, next_cursor) = parse_traces_response(&body)?;
        let page_was_empty = page_events.is_empty();
        events.append(&mut page_events);

        match next_cursor {
            Some(next) if !page_was_empty => cursor = Some(next),
            _ => break,
        }
    }

    Ok(events)
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::unwrap_used,
        clippy::expect_used,
        clippy::indexing_slicing,
        clippy::panic
    )]
    use super::*;

    #[test]
    fn base_url_prefixes_the_site_with_api() {
        assert_eq!(base_url("datadoghq.com"), "https://api.datadoghq.com");
        assert_eq!(base_url("us3.datadoghq.com"), "https://api.us3.datadoghq.com");
    }

    // --- retry ---

    #[test]
    fn retryable_statuses_are_429_and_5xx() {
        for status in [429, 500, 502, 503, 504] {
            assert!(is_retryable_status(status), "{status} should be retryable");
        }
    }

    #[test]
    fn non_retryable_statuses_are_rejected() {
        for status in [400, 401, 403, 404, 422] {
            assert!(!is_retryable_status(status), "{status} should not be retryable");
        }
    }

    #[test]
    fn backoff_honors_a_parseable_reset_header() {
        assert_eq!(backoff_delay(1, Some("5")), Duration::from_secs(5));
    }

    #[test]
    fn backoff_waits_at_least_a_second_on_a_zero_reset_header() {
        assert_eq!(backoff_delay(1, Some("0")), Duration::from_secs(1));
    }

    #[test]
    fn backoff_caps_a_reset_header_above_the_max_wait() {
        assert_eq!(backoff_delay(1, Some("3600")), RETRY_MAX_WAIT);
    }

    #[test]
    fn backoff_falls_back_to_exponential_on_a_bad_reset_header() {
        assert_eq!(backoff_delay(2, Some("not-a-number")), Duration::from_secs(2));
        assert_eq!(backoff_delay(1, None), Duration::from_secs(1));
        assert_eq!(backoff_delay(3, None), Duration::from_secs(4));
    }

    #[test]
    fn backoff_exponential_is_capped_at_the_max_wait() {
        assert_eq!(backoff_delay(10, None), RETRY_MAX_WAIT);
    }

    // --- logs ---

    const LOGS_SAMPLE: &str = r#"{
        "data": [
            {
                "attributes": {
                    "timestamp": "2025-08-30T00:00:00.000Z",
                    "message": "connection timeout",
                    "status": "error",
                    "service": "checkout",
                    "host": "web-1",
                    "tags": ["env:prod", "maintenance"],
                    "attributes": {"http.method": "GET", "http.status_code": 500}
                }
            }
        ],
        "meta": {"page": {"after": "cursor123"}}
    }"#;

    #[test]
    fn parses_log_entries_into_events_with_labels_and_body() {
        let (events, cursor) = parse_logs_response(LOGS_SAMPLE).unwrap();

        assert_eq!(events.len(), 1);
        assert_eq!(events[0].body, Some("connection timeout".to_string()));
        assert_eq!(events[0].labels.get("status"), Some(&"error".to_string()));
        assert_eq!(events[0].labels.get("service"), Some(&"checkout".to_string()));
        assert_eq!(events[0].labels.get("host"), Some(&"web-1".to_string()));
        assert_eq!(events[0].labels.get("env"), Some(&"prod".to_string()));
        assert_eq!(events[0].labels.get("http.method"), Some(&"GET".to_string()));
        assert_eq!(events[0].labels.get("http.status_code"), Some(&"500".to_string()));
        assert_eq!(cursor, Some("cursor123".to_string()));
    }

    #[test]
    fn tag_without_a_colon_becomes_a_label_with_an_empty_value() {
        let (events, _) = parse_logs_response(LOGS_SAMPLE).unwrap();
        assert_eq!(events[0].labels.get("maintenance"), Some(&String::new()));
    }

    #[test]
    fn logs_response_with_no_data_parses_to_an_empty_event_list() {
        let (events, cursor) = parse_logs_response(r#"{"data":[],"meta":{"page":{}}}"#).unwrap();
        assert!(events.is_empty());
        assert_eq!(cursor, None);
    }

    #[test]
    fn logs_api_error_body_is_reported_as_an_error() {
        let body = r#"{"errors":[{"title":"Bad Request","detail":"query is invalid"}]}"#;
        let result = parse_logs_response(body);
        match result {
            Err(DatadogError::LogsApiError(message)) => {
                assert!(message.contains("query is invalid"));
            }
            other => panic!("expected LogsApiError, got {other:?}"),
        }
    }

    #[test]
    fn logs_entry_with_a_malformed_timestamp_is_rejected() {
        let body = r#"{"data":[{"attributes":{"timestamp":"not-a-timestamp","message":"x"}}]}"#;
        let result = parse_logs_response(body);
        assert!(matches!(result, Err(DatadogError::LogsMalformedTimestamp(_))));
    }

    #[test]
    fn rejects_malformed_logs_json() {
        assert!(parse_logs_response("not json").is_err());
    }

    #[test]
    fn nested_log_attribute_is_flattened_into_a_dotted_label() {
        let body = r#"{"data":[{"attributes":{"timestamp":"2025-08-30T00:00:00.000Z","attributes":{"http":{"status_code":500,"method":"GET"},"duration":1234}}}]}"#;
        let (events, _) = parse_logs_response(body).unwrap();
        assert_eq!(events[0].labels.get("http.status_code"), Some(&"500".to_string()));
        assert_eq!(events[0].labels.get("http.method"), Some(&"GET".to_string()));
        assert_eq!(events[0].labels.get("duration"), Some(&"1234".to_string()));
    }

    #[test]
    fn boolean_log_attribute_is_stringified() {
        let body = r#"{"data":[{"attributes":{"timestamp":"2025-08-30T00:00:00.000Z","attributes":{"retried":true}}}]}"#;
        let (events, _) = parse_logs_response(body).unwrap();
        assert_eq!(events[0].labels.get("retried"), Some(&"true".to_string()));
    }

    #[test]
    fn null_log_attribute_is_skipped() {
        let body = r#"{"data":[{"attributes":{"timestamp":"2025-08-30T00:00:00.000Z","attributes":{"optional_field":null}}}]}"#;
        let (events, _) = parse_logs_response(body).unwrap();
        assert_eq!(events[0].labels.get("optional_field"), None);
    }

    #[test]
    fn attribute_flattening_stops_at_the_depth_cap() {
        // Nest one level past MAX_ATTRIBUTE_FLATTEN_DEPTH; the deepest key
        // must not survive flattening.
        let mut value = serde_json::json!("too_deep");
        for _ in 0..=MAX_ATTRIBUTE_FLATTEN_DEPTH.saturating_add(1) {
            value = serde_json::json!({ "level": value });
        }
        let mut attributes = serde_json::Map::new();
        attributes.insert("root".to_string(), value);

        let mut out = BTreeMap::new();
        flatten_attributes_into("", &attributes, 0, &mut out);

        assert!(
            !out.values().any(|v| v == "too_deep"),
            "expected the deepest nested value to be dropped by the depth cap, got {out:?}"
        );
    }

    // --- metrics ---

    const METRICS_SAMPLE: &str = r#"{
        "status": "ok",
        "series": [
            {
                "metric": "system.load.1",
                "scope": "host:web-1",
                "tag_set": ["env:prod", "region:us-east-1"],
                "pointlist": [[1725000000000, 1.5], [1725000060000, null]]
            }
        ]
    }"#;

    #[test]
    fn parses_metrics_series_into_events_skipping_null_points() {
        let events = parse_metrics_response(METRICS_SAMPLE).unwrap();

        assert_eq!(events.len(), 1);
        assert_eq!(events[0].value, Some(1.5));
        assert_eq!(events[0].labels.get("metric"), Some(&"system.load.1".to_string()));
        assert_eq!(events[0].labels.get("scope"), Some(&"host:web-1".to_string()));
        assert_eq!(events[0].labels.get("env"), Some(&"prod".to_string()));
        assert_eq!(events[0].labels.get("region"), Some(&"us-east-1".to_string()));
        assert_eq!(events[0].timestamp.timestamp(), 1725000000);
    }

    #[test]
    fn metrics_response_with_no_series_parses_to_an_empty_event_list() {
        let events = parse_metrics_response(r#"{"status":"ok","series":[]}"#).unwrap();
        assert!(events.is_empty());
    }

    #[test]
    fn metrics_api_error_status_and_message_are_surfaced() {
        let body = r#"{"status":"error","error":"invalid query"}"#;
        let result = parse_metrics_response(body);
        match result {
            Err(DatadogError::MetricsApiError { status, message }) => {
                assert_eq!(status, "error");
                assert_eq!(message, "invalid query");
            }
            other => panic!("expected MetricsApiError, got {other:?}"),
        }
    }

    #[test]
    fn metrics_point_with_a_malformed_timestamp_is_rejected() {
        let body = r#"{"status":"ok","series":[{"pointlist":[[1e400,1.0]]}]}"#;
        let result = parse_metrics_response(body);
        assert!(matches!(result, Err(DatadogError::MetricsParse(_))));
    }

    #[test]
    fn rejects_malformed_metrics_json() {
        assert!(parse_metrics_response("not json").is_err());
    }

    // --- traces ---

    const TRACES_SAMPLE: &str = r#"{
        "data": [
            {
                "attributes": {
                    "start_timestamp": "2025-08-30T00:00:00.000Z",
                    "end_timestamp": "2025-08-30T00:00:00.250Z",
                    "service": "checkout",
                    "resource_name": "POST /cart",
                    "env": "prod",
                    "host": "web-1",
                    "tags": ["error:true", "high_cardinality"],
                    "attributes": {"http.status_code": "500"}
                }
            }
        ],
        "meta": {"page": {"after": "cursor456"}}
    }"#;

    #[test]
    fn parses_span_entries_into_events_with_labels_and_duration_value() {
        let (events, cursor) = parse_traces_response(TRACES_SAMPLE).unwrap();

        assert_eq!(events.len(), 1);
        assert_eq!(events[0].value, Some(250.0));
        assert_eq!(events[0].labels.get("service"), Some(&"checkout".to_string()));
        assert_eq!(events[0].labels.get("resource_name"), Some(&"POST /cart".to_string()));
        assert_eq!(events[0].labels.get("env"), Some(&"prod".to_string()));
        assert_eq!(events[0].labels.get("host"), Some(&"web-1".to_string()));
        assert_eq!(events[0].labels.get("error"), Some(&"true".to_string()));
        assert_eq!(events[0].labels.get("high_cardinality"), Some(&String::new()));
        assert_eq!(events[0].labels.get("http.status_code"), Some(&"500".to_string()));
        assert_eq!(cursor, Some("cursor456".to_string()));
    }

    #[test]
    fn span_duration_falls_back_to_a_custom_duration_attribute_in_nanoseconds() {
        let body = r#"{"data":[{"attributes":{"start_timestamp":"2025-08-30T00:00:00.000Z","attributes":{"duration":250000000}}}]}"#;
        let (events, _) = parse_traces_response(body).unwrap();
        assert_eq!(events[0].value, Some(250.0));
    }

    #[test]
    fn span_custom_attributes_are_flattened_into_labels() {
        let body = r#"{"data":[{"attributes":{"start_timestamp":"2025-08-30T00:00:00.000Z","end_timestamp":"2025-08-30T00:00:00.250Z","custom":{"http":{"status_code":500}}}}]}"#;
        let (events, _) = parse_traces_response(body).unwrap();
        assert_eq!(events[0].labels.get("http.status_code"), Some(&"500".to_string()));
    }

    #[test]
    fn span_duration_falls_back_to_custom_duration_before_attributes_duration() {
        let body = r#"{"data":[{"attributes":{"start_timestamp":"2025-08-30T00:00:00.000Z","custom":{"duration":250000000},"attributes":{"duration":999000000}}}]}"#;
        let (events, _) = parse_traces_response(body).unwrap();
        assert_eq!(events[0].value, Some(250.0));
    }

    #[test]
    fn traces_response_with_no_data_parses_to_an_empty_event_list() {
        let (events, cursor) = parse_traces_response(r#"{"data":[],"meta":{"page":{}}}"#).unwrap();
        assert!(events.is_empty());
        assert_eq!(cursor, None);
    }

    #[test]
    fn traces_api_error_body_is_reported_as_an_error() {
        let body = r#"{"errors":[{"title":"Bad Request","detail":"query is invalid"}]}"#;
        let result = parse_traces_response(body);
        assert!(matches!(result, Err(DatadogError::TracesApiError(_))));
    }

    #[test]
    fn traces_entry_with_a_malformed_timestamp_is_rejected() {
        let body = r#"{"data":[{"attributes":{"start_timestamp":"not-a-timestamp"}}]}"#;
        let result = parse_traces_response(body);
        assert!(matches!(result, Err(DatadogError::TracesMalformedTimestamp(_))));
    }

    #[test]
    fn rejects_malformed_traces_json() {
        assert!(parse_traces_response("not json").is_err());
    }
}
