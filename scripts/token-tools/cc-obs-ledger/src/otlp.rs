//! OTLP/HTTP JSON payloads. Only counts, sizes, names, ids and keyed hashes go in;
//! never transcript text or tool input.

use std::time::{SystemTime, UNIX_EPOCH};

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
    metrics
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
    attrs.push(int_attribute("turn", call.turn));
    attrs.push(int_attribute("seq", call.seq));
    attrs.push(int_attribute("input_bytes", call.input_bytes));
    if let Some(bytes) = call.result_bytes {
        attrs.push(int_attribute("result_bytes", bytes));
    }
    log_record("cc_obs_ledger.tool_call", time, attrs)
}

/// What a `Stop` hook sends: context size and cache hit ratio per request, and one
/// log record per tool call.
pub fn turn_payloads(resource: &Resource, parsed: &Parsed) -> Vec<Payload> {
    let time = now_nanos();
    let mut payloads = Vec::new();
    let metrics: Vec<Value> = parsed
        .requests
        .iter()
        .flat_map(|request| request_metrics(request, &time))
        .collect();
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

/// What a `SessionEnd` hook sends: the measured fixed context split by the census,
/// and one summary log record.
pub fn session_payloads(
    resource: &Resource,
    parsed: &Parsed,
    census: Option<&Census>,
) -> Vec<Payload> {
    let Some(first) = parsed.requests.first() else {
        return Vec::new();
    };
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

    vec![
        metrics_payload(resource, metrics),
        logs_payload(
            resource,
            vec![log_record("cc_obs_ledger.session", &time, attrs)],
        ),
    ]
}
