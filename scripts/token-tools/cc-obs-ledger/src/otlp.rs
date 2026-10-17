//! OTLP/HTTP JSON payloads. Only counts, sizes, names, ids and keyed hashes go in;
//! never transcript text or tool input.

use std::collections::BTreeMap;
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::census::Census;
use crate::transcript::{Parsed, Request, ToolCall};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Signal {
    Metrics,
    Logs,
}

#[derive(Debug, Clone)]
pub struct Payload {
    pub signal: Signal,
    pub body: Value,
}

/// Resource attributes added to everything: the service, the host, and whatever
/// `OTEL_RESOURCE_ATTRIBUTES` holds (the unattended review sets `review.run=1`).
#[derive(Debug, Clone)]
pub struct Resource {
    pub attrs: Vec<(String, String)>,
}

impl Resource {
    pub fn new(host: &str, extra: &[(String, String)]) -> Self {
        let mut attrs = vec![
            ("service.name".to_owned(), "cc-obs-ledger".to_owned()),
            ("host".to_owned(), host.to_owned()),
        ];
        attrs.extend(extra.iter().cloned());
        Self { attrs }
    }

    /// `key=value` pairs separated by commas; a pair without `=` or with an empty key is ignored.
    pub fn from_env_string(host: &str, pairs: &str) -> Self {
        let extra: Vec<(String, String)> = pairs
            .split(',')
            .filter_map(|pair| pair.split_once('='))
            .map(|(key, value)| (key.trim().to_owned(), value.trim().to_owned()))
            .filter(|(key, _)| !key.is_empty())
            .collect();
        Self::new(host, &extra)
    }

    fn json(&self) -> Value {
        json!({ "attributes": attributes(self.attrs.iter().map(|(k, v)| (k.as_str(), v.clone()))) })
    }
}

fn attributes<'a>(pairs: impl Iterator<Item = (&'a str, String)>) -> Vec<Value> {
    pairs
        .map(|(key, value)| json!({ "key": key, "value": { "stringValue": value } }))
        .collect()
}

fn int_attribute(key: &str, value: u64) -> Value {
    json!({ "key": key, "value": { "intValue": value.to_string() } })
}

fn now_nanos() -> String {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |elapsed| elapsed.as_nanos())
        .to_string()
}

/// OTLP `AGGREGATION_TEMPORALITY_DELTA`: each Stop hook sends only what is new.
const AGGREGATION_DELTA: u8 = 1;

enum Number {
    Int(u64),
    Ratio(f64),
}

fn gauge(name: &str, value: Number, attrs: Vec<Value>, time: &str) -> Value {
    let point = match value {
        Number::Int(v) => {
            json!({ "asInt": v.to_string(), "timeUnixNano": time, "attributes": attrs })
        }
        Number::Ratio(v) => json!({ "asDouble": v, "timeUnixNano": time, "attributes": attrs }),
    };
    json!({ "name": name, "gauge": { "dataPoints": [point] } })
}

fn metrics_payload(resource: &Resource, metrics: Vec<Value>) -> Payload {
    Payload {
        signal: Signal::Metrics,
        body: json!({ "resourceMetrics": [{
            "resource": resource.json(),
            "scopeMetrics": [{ "scope": { "name": "cc-obs-ledger" }, "metrics": metrics }],
        }] }),
    }
}

fn logs_payload(resource: &Resource, records: Vec<Value>) -> Payload {
    Payload {
        signal: Signal::Logs,
        body: json!({ "resourceLogs": [{
            "resource": resource.json(),
            "scopeLogs": [{ "scope": { "name": "cc-obs-ledger" }, "logRecords": records }],
        }] }),
    }
}

fn log_record(name: &str, time: &str, attrs: Vec<Value>) -> Value {
    json!({
        "timeUnixNano": time,
        "severityText": "INFO",
        "body": { "stringValue": name },
        "attributes": attrs,
    })
}

fn agent_kind(sidechain: bool) -> &'static str {
    if sidechain {
        "subagent"
    } else {
        "main"
    }
}

fn agent_id_attribute(agent_id: Option<&str>) -> Option<Value> {
    agent_id.map(|id| json!({ "key": "agent_id", "value": { "stringValue": id } }))
}

fn request_metrics(request: &Request, time: &str) -> Vec<Value> {
    let attrs = || {
        let mut base = attributes(
            [
                ("session.id", request.session_id.clone()),
                ("project", request.project.clone()),
                ("model", request.model.clone()),
                ("agent", agent_kind(request.sidechain).to_owned()),
            ]
            .into_iter(),
        );
        base.extend(agent_id_attribute(request.agent_id.as_deref()));
        base.push(int_attribute("turn", request.turn));
        base
    };
    let mut metrics = vec![gauge(
        "cc_obs_ledger_context_tokens",
        Number::Int(request.usage.context_tokens()),
        attrs(),
        time,
    )];
    if let Some(ratio) = request.usage.cache_hit_ratio() {
        metrics.push(gauge(
            "cc_obs_ledger_cache_hit_ratio",
            Number::Ratio(ratio),
            attrs(),
            time,
        ));
    }
    if request.cache_creation_reported {
        metrics.push(gauge(
            "cc_obs_ledger_cache_creation_tokens",
            Number::Int(request.usage.cache_creation),
            attrs(),
            time,
        ));
    }
    if let Some(seconds) = request.seconds_since_prev {
        metrics.push(gauge(
            "cc_obs_ledger_seconds_since_prev_request",
            Number::Int(seconds),
            attrs(),
            time,
        ));
    }
    metrics
}

/// One series per installed skill, from the listing the session started with. Host
/// labels only (from the resource): no session, so the series count is the number of
/// skills, not skills times sessions.
fn skill_listing_metrics(parsed: &Parsed, time: &str) -> Vec<Value> {
    parsed
        .skill_listing
        .iter()
        .flatten()
        .map(|skill| {
            gauge(
                "cc_obs_ledger_skill_listed_tokens",
                Number::Int(skill.chars.checked_div(4).unwrap_or(0)),
                attributes([("skill_name", skill.name.clone())].into_iter()),
                time,
            )
        })
        .collect()
}

/// 1 per MCP server named in the session's MCP instructions.
fn mcp_server_metrics(parsed: &Parsed, time: &str) -> Vec<Value> {
    parsed
        .mcp_servers
        .iter()
        .flatten()
        .map(|name| {
            gauge(
                "cc_obs_ledger_mcp_server_connected",
                Number::Int(1),
                attributes([("mcp_server_name", name.clone())].into_iter()),
                time,
            )
        })
        .collect()
}

/// Requests in this parse per session, project, model and agent, as a delta
/// counter (the collector turns it cumulative). No turn or request id label:
/// that would be one series per request.
fn request_count_metric(requests: &[Request], time: &str) -> Option<Value> {
    let mut counts: BTreeMap<(&str, &str, &str, &str, Option<&str>), u64> = BTreeMap::new();
    for request in requests {
        let key = (
            request.session_id.as_str(),
            request.project.as_str(),
            request.model.as_str(),
            agent_kind(request.sidechain),
            request.agent_id.as_deref(),
        );
        let count = counts.entry(key).or_insert(0);
        *count = count.saturating_add(1);
    }
    if counts.is_empty() {
        return None;
    }
    let points: Vec<Value> = counts
        .into_iter()
        .map(|((session, project, model, agent, agent_id), count)| {
            let mut attrs = attributes(
                [
                    ("session.id", session.to_owned()),
                    ("project", project.to_owned()),
                    ("model", model.to_owned()),
                    ("agent", agent.to_owned()),
                ]
                .into_iter(),
            );
            attrs.extend(agent_id_attribute(agent_id));
            json!({
                "asInt": count.to_string(),
                "startTimeUnixNano": time,
                "timeUnixNano": time,
                "attributes": attrs,
            })
        })
        .collect();
    Some(json!({
        "name": "cc_obs_ledger_requests_total",
        "sum": {
            "aggregationTemporality": AGGREGATION_DELTA,
            "isMonotonic": true,
            "dataPoints": points,
        },
    }))
}

fn tool_call_record(call: &ToolCall, time: &str) -> Value {
    let mut attrs = attributes(
        [
            ("event.name", "cc_obs_ledger.tool_call".to_owned()),
            ("session.id", call.session_id.clone()),
            ("tool_name", call.name.clone()),
            ("agent", agent_kind(call.sidechain).to_owned()),
            ("request_id", call.request_id.clone()),
            ("input_hash", call.input_hash.clone()),
            ("input_prefix_hash", call.input_prefix_hash.clone()),
        ]
        .into_iter(),
    );
    if let Some(prompt_id) = &call.prompt_id {
        attrs.extend(attributes([("prompt_id", prompt_id.clone())].into_iter()));
    }
    attrs.extend(agent_id_attribute(call.agent_id.as_deref()));
    if let Some(shape) = &call.command_shape {
        attrs.extend(attributes([("command_shape", shape.clone())].into_iter()));
    }
    attrs.push(int_attribute("turn", call.turn));
    attrs.push(int_attribute("seq", call.seq));
    attrs.push(int_attribute("input_bytes", call.input_bytes));
    if let Some(bytes) = call.result_bytes {
        attrs.push(int_attribute("result_bytes", bytes));
    }
    log_record("cc_obs_ledger.tool_call", time, attrs)
}

/// What a `Stop` hook sends: context size, cache hit ratio, cache creation and the
/// gap since the previous request per request, a request counter, the skill listing
/// and MCP servers when the parse saw them, and one log record per tool call.
pub fn turn_payloads(resource: &Resource, parsed: &Parsed) -> Vec<Payload> {
    let time = now_nanos();
    let mut payloads = Vec::new();
    let mut metrics: Vec<Value> = parsed
        .requests
        .iter()
        .flat_map(|request| request_metrics(request, &time))
        .collect();
    metrics.extend(request_count_metric(&parsed.requests, &time));
    metrics.extend(skill_listing_metrics(parsed, &time));
    metrics.extend(mcp_server_metrics(parsed, &time));
    if !metrics.is_empty() {
        payloads.push(metrics_payload(resource, metrics));
    }
    let records: Vec<Value> = parsed
        .tool_calls
        .iter()
        .map(|call| tool_call_record(call, &time))
        .collect();
    if !records.is_empty() {
        payloads.push(logs_payload(resource, records));
    }
    payloads
}

/// What a session's whole transcript summed to at one `SessionEnd`. The cursor keeps the
/// last one so the next end can report what happened since. `ends` counts the ends so far.
#[derive(Serialize, Deserialize, Default, Debug, Clone, Copy, PartialEq, Eq)]
pub struct EndTotals {
    pub ends: u64,
    pub requests: u64,
    pub tool_calls: u64,
    pub input: u64,
    pub output: u64,
    pub cache_read: u64,
    pub cache_creation: u64,
}

impl EndTotals {
    /// The totals of `parsed`, counted as the end after `previous`.
    pub fn after(previous: &EndTotals, parsed: &Parsed) -> Self {
        let usage = parsed.total_usage();
        Self {
            ends: previous.ends.saturating_add(1),
            requests: parsed.requests.len() as u64,
            tool_calls: parsed.tool_calls.len() as u64,
            input: usage.input,
            output: usage.output,
            cache_read: usage.cache_read,
            cache_creation: usage.cache_creation,
        }
    }

    fn same_activity(&self, other: &EndTotals) -> bool {
        Self { ends: 0, ..*self } == Self { ends: 0, ..*other }
    }
}

fn bool_attribute(key: &str, value: bool) -> Value {
    json!({ "key": key, "value": { "boolValue": value } })
}

/// What a `SessionEnd` hook sends: the measured fixed context split by the census,
/// and one summary log record. The record is cumulative over the whole transcript and
/// also carries the change since `previous`, the totals at the last end. An end with no
/// change since `previous` sends nothing, so the record count never inflates a resume.
pub fn session_payloads(
    resource: &Resource,
    parsed: &Parsed,
    census: Option<&Census>,
    previous: &EndTotals,
) -> Vec<Payload> {
    let Some(first) = parsed.requests.first() else {
        return Vec::new();
    };
    let totals = EndTotals::after(previous, parsed);
    if previous.ends > 0 && totals.same_activity(previous) {
        return Vec::new();
    }
    let time = now_nanos();
    let session = first.session_id.clone();
    let prompt_tokens = parsed.first_prompt_chars.checked_div(4).unwrap_or(0);
    let fixed_total = first.usage.context_tokens().saturating_sub(prompt_tokens);

    let component = |name: &str, tokens: u64| {
        gauge(
            "cc_obs_ledger_fixed_context_tokens",
            Number::Int(tokens),
            attributes(
                [
                    ("session.id", session.clone()),
                    ("project", first.project.clone()),
                    ("component", name.to_owned()),
                ]
                .into_iter(),
            ),
            &time,
        )
    };
    let mut metrics = vec![component("total", fixed_total)];
    if let Some(census) = census {
        let mut explained = 0u64;
        for (name, tokens) in &census.components {
            metrics.push(component(name, *tokens));
            explained = explained.saturating_add(*tokens);
        }
        metrics.push(component("other", fixed_total.saturating_sub(explained)));
    }

    let usage = parsed.total_usage();
    let mut attrs = attributes(
        [
            ("event.name", "cc_obs_ledger.session".to_owned()),
            ("session.id", session),
            ("project", first.project.clone()),
        ]
        .into_iter(),
    );
    attrs.push(int_attribute("requests", parsed.requests.len() as u64));
    attrs.push(int_attribute("tool_calls", parsed.tool_calls.len() as u64));
    attrs.push(int_attribute("input_tokens", usage.input));
    attrs.push(int_attribute("output_tokens", usage.output));
    attrs.push(int_attribute("cache_read_tokens", usage.cache_read));
    attrs.push(int_attribute("cache_creation_tokens", usage.cache_creation));
    attrs.push(int_attribute("skipped_lines", parsed.skipped_lines as u64));
    attrs.push(int_attribute("end_index", totals.ends));
    attrs.push(bool_attribute("cumulative", true));
    let delta = |key: &str, now: u64, before: u64| int_attribute(key, now.saturating_sub(before));
    attrs.push(delta("requests_delta", totals.requests, previous.requests));
    attrs.push(delta(
        "tool_calls_delta",
        totals.tool_calls,
        previous.tool_calls,
    ));
    attrs.push(delta("input_tokens_delta", totals.input, previous.input));
    attrs.push(delta("output_tokens_delta", totals.output, previous.output));
    attrs.push(delta(
        "cache_read_tokens_delta",
        totals.cache_read,
        previous.cache_read,
    ));
    attrs.push(delta(
        "cache_creation_tokens_delta",
        totals.cache_creation,
        previous.cache_creation,
    ));

    vec![
        metrics_payload(resource, metrics),
        logs_payload(
            resource,
            vec![log_record("cc_obs_ledger.session", &time, attrs)],
        ),
    ]
}
