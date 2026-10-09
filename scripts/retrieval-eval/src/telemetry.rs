//! Ships a hook run to Grafana Loki (as a log line) and Tempo (as a trace) over
//! their HTTP APIs. Only what the log already holds: scores, counts and timings,
//! never the prompt. Delivery is best effort and happens outside the hook's own
//! process (`memory-recall ship`), so a slow or unreachable backend never delays a
//! prompt.
use std::time::Duration;

use crate::recall_log::{to_line, Entry};

const SEND_TIMEOUT: Duration = Duration::from_secs(3);

/// Where to send, from the hook's flags.
#[derive(Debug, Clone, Default, PartialEq, Eq, clap::Args)]
pub struct Targets {
    /// Loki base URL, e.g. http://loki:3100 (log lines go to /loki/api/v1/push).
    #[arg(long)]
    pub loki_url: Option<String>,
    /// OTLP/HTTP base URL of Tempo or a collector, e.g. http://tempo:4318 (spans go
    /// to /v1/traces).
    #[arg(long)]
    pub otlp_endpoint: Option<String>,
    /// X-Scope-OrgID for a multi-tenant Loki or Tempo.
    #[arg(long)]
    pub telemetry_tenant: Option<String>,
    /// Extra Loki labels and span resource attributes, as KEY=VALUE (repeatable).
    #[arg(long = "telemetry-label")]
    pub telemetry_labels: Vec<String>,
    /// A file of extra HTTP headers, one `Name: value` per line, sent to Loki and
    /// Tempo, for authentication (`Authorization: Bearer ...`). Read when sending, so
    /// a secret stays in a file (a sops-nix path) and out of the process list and
    /// the Nix store.
    #[arg(long)]
    pub telemetry_headers_file: Option<std::path::PathBuf>,
}

impl Targets {
    pub fn enabled(&self) -> bool {
        self.loki_url.is_some() || self.otlp_endpoint.is_some()
    }

    /// The `--telemetry-label` pairs; entries without `=` are dropped.
    pub fn label_pairs(&self) -> Vec<(String, String)> {
        self.telemetry_labels
            .iter()
            .filter_map(|l| l.split_once('='))
            .map(|(k, v)| (k.to_owned(), v.to_owned()))
            .collect()
    }
}

/// The flags `recall-ship` takes for these targets.
pub fn ship_args(targets: &Targets) -> Vec<String> {
    let mut args = Vec::new();
    let mut flag = |name: &str, value: &Option<String>| {
        if let Some(value) = value {
            args.push(name.to_owned());
            args.push(value.clone());
        }
    };
    flag("--loki-url", &targets.loki_url);
    flag("--otlp-endpoint", &targets.otlp_endpoint);
    flag("--telemetry-tenant", &targets.telemetry_tenant);
    for label in &targets.telemetry_labels {
        args.push("--telemetry-label".to_owned());
        args.push(label.clone());
    }
    if let Some(file) = &targets.telemetry_headers_file {
        args.push("--telemetry-headers-file".to_owned());
        args.push(file.to_string_lossy().into_owned());
    }
    args
}

/// `Name: value` lines of a headers file; blanks, `#` comments and lines without a
/// name or a colon are skipped.
pub fn parse_header_lines(text: &str) -> Vec<(String, String)> {
    text.lines()
        .map(str::trim)
        .filter(|line| !line.is_empty() && !line.starts_with('#'))
        .filter_map(|line| line.split_once(':'))
        .map(|(name, value)| (name.trim(), value.trim()))
        .filter(|(name, _)| !name.is_empty())
        .map(|(name, value)| (name.to_owned(), value.to_owned()))
        .collect()
}

/// Starts `recall-ship` (next to the running binary) in the background with the
/// entry on its stdin and does not wait for it, so the hook returns at once. Any
/// problem is ignored: telemetry must never affect a prompt.
pub fn spawn_ship(targets: &Targets, entry: &Entry) {
    use std::io::Write;
    use std::process::{Command, Stdio};
    if !targets.enabled() {
        return;
    }
    let Some(ship) = std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(|dir| dir.join("recall-ship")))
    else {
        return;
    };
    let Ok(mut child) = Command::new(ship)
        .args(ship_args(targets))
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    else {
        return;
    };
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(to_line(entry).as_bytes());
    }
}

/// Trace and span ids as lowercase hex (32, 16 and 16 characters).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Ids {
    pub trace: String,
    pub root: String,
    pub embed: String,
    /// The span the hook span continues from, when a `traceparent` supplied one.
    pub parent: Option<String>,
}

/// Random ids. Reads /dev/urandom, which Linux and macOS both have; if it cannot
/// be read, falls back to hashing the clock and process id, which is unique enough
/// for ids that only have to differ between hook runs.
pub fn new_ids() -> Ids {
    Ids {
        trace: random_hex(16),
        root: random_hex(8),
        embed: random_hex(8),
        parent: None,
    }
}

/// Ids that continue the W3C `traceparent` (`00-<trace>-<span>-<flags>`) when it is
/// valid: the trace id is kept and the span becomes the hook span's parent. Any
/// other value starts a fresh trace. Claude Code does not set `TRACEPARENT` for
/// hooks today; this is ready for when it does.
pub fn new_ids_from(traceparent: Option<&str>) -> Ids {
    let mut ids = new_ids();
    if let Some((trace, span)) = traceparent.and_then(parse_traceparent) {
        ids.trace = trace;
        ids.parent = Some(span);
    }
    ids
}

fn parse_traceparent(value: &str) -> Option<(String, String)> {
    let mut parts = value.trim().split('-');
    let (version, trace, span, flags) =
        (parts.next()?, parts.next()?, parts.next()?, parts.next()?);
    let lower_hex = |s: &str, len: usize| {
        s.len() == len && s.chars().all(|c| matches!(c, '0'..='9' | 'a'..='f'))
    };
    let nonzero = |s: &str| s.chars().any(|c| c != '0');
    let valid = lower_hex(version, 2)
        && version != "ff"
        && lower_hex(trace, 32)
        && nonzero(trace)
        && lower_hex(span, 16)
        && nonzero(span)
        && lower_hex(flags, 2);
    valid.then(|| (trace.to_owned(), span.to_owned()))
}

fn random_hex(bytes: usize) -> String {
    use std::io::Read;
    let mut buf = vec![0_u8; bytes];
    let read = std::fs::File::open("/dev/urandom").and_then(|mut f| f.read_exact(&mut buf));
    if read.is_err() {
        fill_from_clock(&mut buf);
    }
    // An all-zero id is invalid in OTLP.
    if buf.iter().all(|b| *b == 0) {
        if let Some(last) = buf.last_mut() {
            *last = 1;
        }
    }
    buf.iter().map(|b| format!("{b:02x}")).collect()
}

/// FNV-1a over the clock, the process id and a counter, stretched over `buf`.
fn fill_from_clock(buf: &mut [u8]) {
    use std::sync::atomic::{AtomicU64, Ordering};
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_nanos());
    let mut state: u64 = 0xcbf2_9ce4_8422_2325;
    let seed = [
        nanos as u64,
        u64::from(std::process::id()),
        COUNTER.fetch_add(1, Ordering::Relaxed),
    ];
    for byte in buf.iter_mut() {
        for word in seed {
            state = (state ^ word).wrapping_mul(0x0100_0000_01b3);
        }
        state = state.rotate_left(13);
        *byte = (state >> 24) as u8;
    }
}

fn service_of(entry: &Entry) -> &'static str {
    if entry.kind == "skills" {
        "skill-recall"
    } else {
        "memory-recall"
    }
}

/// Loki label names allow letters, digits and underscores only.
fn label_name(key: &str) -> String {
    key.chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '_' })
        .collect()
}

/// A Loki push request body with one stream and one line: the log entry as JSON.
pub fn loki_push_body(entry: &Entry, labels: &[(String, String)], end_ns: u128) -> String {
    let mut stream = serde_json::Map::new();
    stream.insert("service".into(), service_of(entry).into());
    stream.insert("kind".into(), entry.kind.clone().into());
    for (key, value) in labels {
        stream.insert(label_name(key), value.clone().into());
    }
    serde_json::json!({
        "streams": [{
            "stream": stream,
            "values": [[end_ns.to_string(), to_line(entry).trim_end()]],
        }]
    })
    .to_string()
}

fn attribute(key: &str, value: serde_json::Value) -> serde_json::Value {
    serde_json::json!({ "key": key, "value": value })
}

fn string_value(text: &str) -> serde_json::Value {
    serde_json::json!({ "stringValue": text })
}

fn int_value(n: usize) -> serde_json::Value {
    // OTLP's JSON mapping writes 64-bit integers as strings.
    serde_json::json!({ "intValue": n.to_string() })
}

/// An OTLP/HTTP JSON trace request: a root span for the hook run and, when the
/// embedding was timed, a child span for it.
pub fn otlp_trace_body(
    entry: &Entry,
    labels: &[(String, String)],
    ids: &Ids,
    end_ns: u128,
) -> String {
    let to_ns = |ms: f64| (ms.max(0.0) * 1_000_000.0) as u128;
    let start_ns = end_ns.saturating_sub(entry.duration_ms.map_or(0, to_ns));
    let mut attributes = vec![
        attribute("recall.kind", string_value(&entry.kind)),
        attribute("recall.matches", int_value(entry.matches)),
        attribute("recall.full", int_value(entry.full)),
        attribute("recall.tokens", int_value(entry.tokens)),
        attribute(
            "recall.fallback",
            serde_json::json!({ "boolValue": entry.fallback }),
        ),
        attribute(
            "recall.failed",
            serde_json::json!({ "boolValue": entry.failed }),
        ),
    ];
    if let Some(score) = entry.best_score {
        attributes.push(attribute(
            "recall.best_score",
            serde_json::json!({ "doubleValue": score }),
        ));
    }
    attributes.push(attribute(
        "recall.outcome",
        string_value(entry.outcome.as_str()),
    ));
    if let Some(cause) = &entry.cause {
        attributes.push(attribute("recall.cause", string_value(cause)));
    }
    let status = if entry.failed {
        serde_json::json!({ "code": 2, "message": "memories or skills could not be retrieved" })
    } else {
        serde_json::json!({ "code": 1 })
    };
    for (key, id) in [
        ("session.id", &entry.session_id),
        ("prompt.id", &entry.prompt_id),
    ] {
        if let Some(id) = id {
            attributes.push(attribute(key, string_value(id)));
        }
    }
    let name = format!("{}.hook", service_of(entry));
    let mut root = serde_json::json!({
        "traceId": ids.trace,
        "spanId": ids.root,
        "name": name,
        "kind": 1,
        "startTimeUnixNano": start_ns.to_string(),
        "endTimeUnixNano": end_ns.to_string(),
        "attributes": attributes,
        "status": status,
    });
    if let (Some(parent), Some(object)) = (&ids.parent, root.as_object_mut()) {
        object.insert("parentSpanId".to_owned(), parent.clone().into());
    }
    let mut spans = vec![root];
    if let Some(embed_ms) = entry.embed_ms {
        spans.push(serde_json::json!({
            "traceId": ids.trace,
            "spanId": ids.embed,
            "parentSpanId": ids.root,
            "name": "embed",
            "kind": 3,
            "startTimeUnixNano": start_ns.to_string(),
            "endTimeUnixNano": start_ns.saturating_add(to_ns(embed_ms)).min(end_ns).to_string(),
            "status": { "code": 1 },
        }));
    }
    let mut resource = vec![attribute("service.name", string_value(service_of(entry)))];
    resource.extend(labels.iter().map(|(k, v)| attribute(k, string_value(v))));
    serde_json::json!({
        "resourceSpans": [{
            "resource": { "attributes": resource },
            "scopeSpans": [{ "scope": { "name": "memory-recall" }, "spans": spans }],
        }]
    })
    .to_string()
}

/// The pairs of an `OTEL_RESOURCE_ATTRIBUTES` value (`k1=v1,k2=v2`); pairs without
/// `=` or with an empty key are dropped.
pub fn parse_resource_attributes(value: &str) -> Vec<(String, String)> {
    value
        .split(',')
        .filter_map(|pair| pair.split_once('='))
        .map(|(key, value)| (key.trim(), value.trim()))
        .filter(|(key, _)| !key.is_empty())
        .map(|(key, value)| (key.to_owned(), value.to_owned()))
        .collect()
}

/// The pairs whose key, with `.` replaced by `_`, is a valid Loki label name
/// (`[a-zA-Z_][a-zA-Z0-9_]*`), under that name.
pub fn loki_labels_from(pairs: &[(String, String)]) -> Vec<(String, String)> {
    pairs
        .iter()
        .map(|(key, value)| (key.replace('.', "_"), value.clone()))
        .filter(|(key, _)| {
            let mut chars = key.chars();
            chars
                .next()
                .is_some_and(|c| c.is_ascii_alphabetic() || c == '_')
                && chars.all(|c| c.is_ascii_alphanumeric() || c == '_')
        })
        .collect()
}

/// An OTLP/HTTP JSON metrics request for one hook run. Counters are deltas (one
/// run's contribution); latency is a gauge of that run, since a histogram of one
/// observation per process adds nothing a gauge does not.
pub fn otlp_metrics_body(entry: &Entry, resource: &[(String, String)], end_ns: u128) -> String {
    let service = service_of(entry);
    let start_ns = end_ns.saturating_sub(
        entry
            .duration_ms
            .map_or(0, |ms| (ms.max(0.0) * 1_000_000.0) as u128),
    );
    let point = |extra: Option<(&str, &str)>, value: serde_json::Value| {
        let mut attributes = vec![attribute("service", string_value(service))];
        if let Some((key, text)) = extra {
            attributes.push(attribute(key, string_value(text)));
        }
        let mut point = serde_json::json!({
            "attributes": attributes,
            "startTimeUnixNano": start_ns.to_string(),
            "timeUnixNano": end_ns.to_string(),
        });
        if let (Some(object), Some(fields)) = (point.as_object_mut(), value.as_object()) {
            object.extend(fields.clone());
        }
        point
    };
    let counter = |name: &str, point: serde_json::Value| {
        serde_json::json!({
            "name": name,
            "sum": {
                "dataPoints": [point],
                "aggregationTemporality": 1,
                "isMonotonic": true,
            },
        })
    };
    let as_int = |n: usize| serde_json::json!({ "asInt": n.to_string() });
    let mut metrics = vec![
        counter(
            "recall_requests_total",
            point(Some(("outcome", entry.outcome.as_str())), as_int(1)),
        ),
        counter(
            "recall_hits_total",
            point(None, as_int(usize::from(entry.matches > 0))),
        ),
        counter(
            "recall_tokens_injected_total",
            point(None, as_int(entry.tokens)),
        ),
    ];
    if let Some(ms) = entry.duration_ms {
        metrics.push(serde_json::json!({
            "name": "recall_latency_seconds",
            "gauge": { "dataPoints": [point(None, serde_json::json!({ "asDouble": ms / 1000.0 }))] },
        }));
    }
    let mut attributes = vec![attribute("service.name", string_value(service))];
    attributes.extend(resource.iter().map(|(k, v)| attribute(k, string_value(v))));
    serde_json::json!({
        "resourceMetrics": [{
            "resource": { "attributes": attributes },
            "scopeMetrics": [{ "scope": { "name": "memory-recall" }, "metrics": metrics }],
        }]
    })
    .to_string()
}

fn now_ns() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_nanos())
}

fn post(
    url: &str,
    tenant: Option<&str>,
    headers: &[(String, String)],
    body: &str,
) -> Result<(), String> {
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .timeout_global(Some(SEND_TIMEOUT))
        .build()
        .into();
    let mut request = agent.post(url).header("content-type", "application/json");
    if let Some(tenant) = tenant {
        request = request.header("X-Scope-OrgID", tenant);
    }
    for (name, value) in headers {
        request = request.header(name.as_str(), value.as_str());
    }
    request
        .send(body)
        .map(|_| ())
        .map_err(|error| format!("{url}: {error}"))
}

/// Posts `entry` to every configured backend; one result per attempt.
pub fn send(targets: &Targets, entry: &Entry) -> Vec<Result<(), String>> {
    let env_pairs = std::env::var("OTEL_RESOURCE_ATTRIBUTES")
        .map(|value| parse_resource_attributes(&value))
        .unwrap_or_default();
    let mut resource = targets.label_pairs();
    resource.extend(env_pairs.iter().cloned());
    let mut loki_labels = targets.label_pairs();
    loki_labels.extend(loki_labels_from(&env_pairs));
    let tenant = targets.telemetry_tenant.as_deref();
    let end_ns = now_ns();
    let mut results = Vec::new();
    let headers = match &targets.telemetry_headers_file {
        Some(file) => match std::fs::read_to_string(file) {
            Ok(text) => parse_header_lines(&text),
            Err(error) => {
                // Sending without the credentials would only be refused; say why.
                return vec![Err(format!("read {}: {error}", file.display()))];
            }
        },
        None => Vec::new(),
    };
    if let Some(base) = &targets.loki_url {
        let url = format!("{}/loki/api/v1/push", base.trim_end_matches('/'));
        let body = loki_push_body(entry, &loki_labels, end_ns);
        results.push(post(&url, tenant, &headers, &body));
    }
    if let Some(base) = &targets.otlp_endpoint {
        let url = format!("{}/v1/traces", base.trim_end_matches('/'));
        let traceparent = std::env::var("TRACEPARENT").ok();
        let body = otlp_trace_body(
            entry,
            &resource,
            &new_ids_from(traceparent.as_deref()),
            end_ns,
        );
        results.push(post(&url, tenant, &headers, &body));
        let url = format!("{}/v1/metrics", base.trim_end_matches('/'));
        let body = otlp_metrics_body(entry, &resource, end_ns);
        results.push(post(&url, tenant, &headers, &body));
    }
    results
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]
mod tests {
    use super::*;
    use crate::recall_log::Outcome;

    fn entry() -> Entry {
        Entry {
            at: "2026-10-08T10:00:00Z".to_owned(),
            kind: "memory".to_owned(),
            best_score: Some(0.81),
            matches: 2,
            full: 1,
            tokens: 640,
            failed: false,
            fallback: false,
            duration_ms: Some(40.0),
            embed_ms: Some(25.0),
            session_id: None,
            prompt_id: None,
            outcome: Outcome::Success,
            cause: None,
        }
    }

    fn labels() -> Vec<(String, String)> {
        vec![("host".to_owned(), "desk".to_owned())]
    }

    #[test]
    fn label_pairs_split_on_the_first_equals_and_drop_malformed_ones() {
        let targets = Targets {
            telemetry_labels: vec!["host=desk".into(), "bad".into(), "a=b=c".into()],
            ..Targets::default()
        };
        assert_eq!(
            targets.label_pairs(),
            [("host".into(), "desk".into()), ("a".into(), "b=c".into())]
        );
    }

    #[test]
    fn ship_args_repeat_only_what_is_set() {
        let targets = Targets {
            loki_url: Some("http://l:3100".into()),
            otlp_endpoint: None,
            telemetry_tenant: Some("t1".into()),
            telemetry_labels: vec!["host=desk".into(), "env=dev".into()],
            telemetry_headers_file: None,
        };
        assert_eq!(
            ship_args(&targets),
            [
                "--loki-url",
                "http://l:3100",
                "--telemetry-tenant",
                "t1",
                "--telemetry-label",
                "host=desk",
                "--telemetry-label",
                "env=dev"
            ]
        );
        assert!(ship_args(&Targets::default()).is_empty());
    }

    #[test]
    fn header_lines_are_name_colon_value_with_comments_and_blanks_ignored() {
        let text = "# Loki\nAuthorization: Bearer s3cret\n\n  X-Extra :  a: b  \nnot a header\n: novalue\n";
        assert_eq!(
            parse_header_lines(text),
            [
                ("Authorization".to_owned(), "Bearer s3cret".to_owned()),
                ("X-Extra".to_owned(), "a: b".to_owned())
            ]
        );
        assert!(parse_header_lines("").is_empty());
    }

    #[test]
    fn the_headers_file_is_passed_by_path_never_by_content() {
        let targets = Targets {
            otlp_endpoint: Some("http://t:4318".into()),
            telemetry_headers_file: Some("/run/secrets/otel-headers".into()),
            ..Targets::default()
        };
        let args = ship_args(&targets);
        assert!(args
            .windows(2)
            .any(|w| w == ["--telemetry-headers-file", "/run/secrets/otel-headers"]));
    }

    #[test]
    fn nothing_is_enabled_without_a_url() {
        assert!(!Targets::default().enabled());
        let loki = Targets {
            loki_url: Some("http://l".into()),
            ..Targets::default()
        };
        assert!(loki.enabled());
    }

    #[test]
    fn ids_have_the_right_widths_and_differ_between_calls() {
        let (a, b) = (new_ids(), new_ids());
        assert_eq!(a.trace.len(), 32);
        assert_eq!(a.root.len(), 16);
        assert_eq!(a.embed.len(), 16);
        assert!(a.trace.chars().all(|c| c.is_ascii_hexdigit()));
        assert_ne!(a.trace, b.trace);
        assert_ne!(a.root, a.embed);
    }

    #[test]
    fn a_valid_traceparent_supplies_the_trace_and_the_parent_span() {
        let tp = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01";
        let ids = new_ids_from(Some(tp));
        assert_eq!(ids.trace, "4bf92f3577b34da6a3ce929d0e0e4736");
        assert_eq!(ids.parent.as_deref(), Some("00f067aa0ba902b7"));
        assert_ne!(
            ids.root, "00f067aa0ba902b7",
            "the hook span gets its own id"
        );
    }

    #[test]
    fn a_missing_or_malformed_traceparent_starts_a_fresh_trace() {
        for bad in [
            None,
            Some(""),
            Some("garbage"),
            Some("00-short-00f067aa0ba902b7-01"),
            Some("00-4bf92f3577b34da6a3ce929d0e0e4736-short-01"),
            Some("ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"),
            Some("00-00000000000000000000000000000000-00f067aa0ba902b7-01"),
            Some("00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01"),
            Some("00-4BF92F3577B34DA6A3CE929D0E0E4736-00f067aa0ba902b7-01"),
        ] {
            let ids = new_ids_from(bad);
            assert_eq!(ids.parent, None, "{bad:?}");
            assert_eq!(ids.trace.len(), 32);
        }
    }

    #[test]
    fn session_and_prompt_ids_become_span_attributes_and_a_parent_is_linked() {
        let mut with_ids = entry();
        with_ids.session_id = Some("sess-1".to_owned());
        with_ids.prompt_id = Some("prompt-7".to_owned());
        let mut ids = new_ids();
        ids.parent = Some("d".repeat(16));
        let body = otlp_trace_body(&with_ids, &[], &ids, 2_000_000_000_000);
        let value: serde_json::Value = serde_json::from_str(&body).unwrap();
        let root = &value["resourceSpans"][0]["scopeSpans"][0]["spans"][0];
        let attrs = root["attributes"].to_string();
        assert!(attrs.contains("session.id") && attrs.contains("sess-1"));
        assert!(attrs.contains("prompt.id") && attrs.contains("prompt-7"));
        assert_eq!(root["parentSpanId"], "d".repeat(16));
        let without = otlp_trace_body(&entry(), &[], &new_ids(), 2_000_000_000_000);
        let bare: serde_json::Value = serde_json::from_str(&without).unwrap();
        let bare_root = &bare["resourceSpans"][0]["scopeSpans"][0]["spans"][0];
        assert!(!without.contains("session.id"));
        assert!(
            bare_root.get("parentSpanId").is_none(),
            "a fresh trace has no parent"
        );
    }

    #[test]
    fn loki_body_is_one_stream_with_the_labels_and_the_entry_as_the_line() {
        let body = loki_push_body(&entry(), &labels(), 1_791_000_000_000_000_000);
        let value: serde_json::Value = serde_json::from_str(&body).unwrap();
        let stream = &value["streams"][0];
        assert_eq!(stream["stream"]["service"], "memory-recall");
        assert_eq!(stream["stream"]["kind"], "memory");
        assert_eq!(stream["stream"]["host"], "desk");
        let pair = &stream["values"][0];
        assert_eq!(pair[0], "1791000000000000000");
        let line: Entry = serde_json::from_str(pair[1].as_str().unwrap()).unwrap();
        assert_eq!(line, entry());
        assert!(
            !body.contains("\\\"prompt\\\""),
            "ids are shipped, the text is not"
        );
    }

    #[test]
    fn otlp_body_has_a_root_span_and_an_embed_child_inside_it() {
        let ids = Ids {
            trace: "a".repeat(32),
            root: "b".repeat(16),
            embed: "c".repeat(16),
            parent: None,
        };
        let end = 1_791_000_000_000_000_000_u128;
        let body = otlp_trace_body(&entry(), &labels(), &ids, end);
        let value: serde_json::Value = serde_json::from_str(&body).unwrap();
        let resource = &value["resourceSpans"][0]["resource"]["attributes"];
        assert!(resource.to_string().contains("memory-recall"));
        assert!(resource.to_string().contains("desk"));
        let spans = value["resourceSpans"][0]["scopeSpans"][0]["spans"]
            .as_array()
            .unwrap();
        assert_eq!(spans.len(), 2);
        let (root, child) = (&spans[0], &spans[1]);
        assert_eq!(root["name"], "memory-recall.hook");
        assert_eq!(root["traceId"], ids.trace.as_str());
        assert_eq!(root["spanId"], ids.root.as_str());
        assert_eq!(root["endTimeUnixNano"], end.to_string());
        assert_eq!(
            root["startTimeUnixNano"],
            (end - 40_000_000).to_string(),
            "start is the end minus the 40 ms duration"
        );
        assert_eq!(child["name"], "embed");
        assert_eq!(child["parentSpanId"], ids.root.as_str());
        assert_eq!(child["traceId"], ids.trace.as_str());
        assert_eq!(child["startTimeUnixNano"], root["startTimeUnixNano"]);
        let attrs = root["attributes"].to_string();
        assert!(attrs.contains("recall.matches") && attrs.contains("recall.best_score"));
        assert!(!attrs.contains("prompt"));
        assert_eq!(root["status"]["code"], 1);
    }

    #[test]
    fn a_failed_run_is_an_error_span_and_has_no_embed_child_without_a_timing() {
        let mut failed = entry();
        failed.failed = true;
        failed.embed_ms = None;
        let ids = new_ids();
        let body = otlp_trace_body(&failed, &[], &ids, 2_000_000_000_000);
        let value: serde_json::Value = serde_json::from_str(&body).unwrap();
        let spans = value["resourceSpans"][0]["scopeSpans"][0]["spans"]
            .as_array()
            .unwrap();
        assert_eq!(spans.len(), 1);
        assert_eq!(spans[0]["status"]["code"], 2);
    }

    #[test]
    fn a_skills_entry_is_named_for_the_skills_hook() {
        let mut skills = entry();
        skills.kind = "skills".to_owned();
        let body = otlp_trace_body(&skills, &[], &new_ids(), 2_000_000_000_000);
        assert!(body.contains("skill-recall.hook"));
        assert!(loki_push_body(&skills, &[], 1).contains("skill-recall"));
    }

    fn metrics(entry: &Entry, resource: &[(String, String)]) -> serde_json::Value {
        serde_json::from_str(&otlp_metrics_body(entry, resource, 2_000_000_000_000)).unwrap()
    }

    fn metric<'a>(body: &'a serde_json::Value, name: &str) -> &'a serde_json::Value {
        body["resourceMetrics"][0]["scopeMetrics"][0]["metrics"]
            .as_array()
            .unwrap()
            .iter()
            .find(|m| m["name"] == name)
            .expect("metric present")
    }

    fn attr<'a>(point: &'a serde_json::Value, key: &str) -> Option<&'a str> {
        point["attributes"]
            .as_array()?
            .iter()
            .find(|a| a["key"] == key)?["value"]["stringValue"]
            .as_str()
    }

    #[test]
    fn the_four_recall_metrics_carry_service_and_outcome() {
        let body = metrics(&entry(), &[]);
        let requests = &metric(&body, "recall_requests_total")["sum"];
        assert_eq!(requests["aggregationTemporality"], 1);
        assert_eq!(requests["isMonotonic"], true);
        let point = &requests["dataPoints"][0];
        assert_eq!(point["asInt"], "1");
        assert_eq!(attr(point, "service"), Some("memory-recall"));
        assert_eq!(attr(point, "outcome"), Some("success"));
        let hits = &metric(&body, "recall_hits_total")["sum"]["dataPoints"][0];
        assert_eq!(hits["asInt"], "1");
        assert_eq!(attr(hits, "service"), Some("memory-recall"));
        let tokens = &metric(&body, "recall_tokens_injected_total")["sum"];
        assert_eq!(tokens["isMonotonic"], true);
        assert_eq!(tokens["dataPoints"][0]["asInt"], "640");
        let latency = &metric(&body, "recall_latency_seconds")["gauge"]["dataPoints"][0];
        assert!((latency["asDouble"].as_f64().unwrap() - 0.04).abs() < 1e-9);
        assert_eq!(attr(latency, "service"), Some("memory-recall"));
    }

    #[test]
    fn a_run_without_matches_counts_a_request_and_no_hit() {
        let mut empty = entry();
        empty.matches = 0;
        empty.tokens = 0;
        empty.outcome = Outcome::Empty;
        let body = metrics(&empty, &[]);
        let point = &metric(&body, "recall_requests_total")["sum"]["dataPoints"][0];
        assert_eq!(attr(point, "outcome"), Some("empty"));
        let hits = &metric(&body, "recall_hits_total")["sum"]["dataPoints"][0];
        assert_eq!(hits["asInt"], "0");
    }

    #[test]
    fn a_skills_failure_is_counted_under_the_skill_service_with_outcome_error() {
        let mut failed = Entry::failure("skills", "t", "timeout");
        failed.duration_ms = None;
        let body = metrics(&failed, &[]);
        let point = &metric(&body, "recall_requests_total")["sum"]["dataPoints"][0];
        assert_eq!(attr(point, "service"), Some("skill-recall"));
        assert_eq!(attr(point, "outcome"), Some("error"));
        assert!(
            body.to_string().find("recall_latency_seconds").is_none(),
            "no timing, no latency point"
        );
    }

    #[test]
    fn metrics_resource_has_the_service_and_the_extra_attributes() {
        let resource = vec![("review.run".to_owned(), "1".to_owned())];
        let body = metrics(&entry(), &resource);
        let attrs = &body["resourceMetrics"][0]["resource"];
        let text = attrs.to_string();
        assert!(text.contains("memory-recall") && text.contains("review.run"));
    }

    #[test]
    fn outcome_and_cause_are_span_attributes() {
        let failed = Entry::failure("memory", "t", "embedder_unreachable");
        let body = otlp_trace_body(&failed, &[], &new_ids(), 2_000_000_000_000);
        let value: serde_json::Value = serde_json::from_str(&body).unwrap();
        let attrs = value["resourceSpans"][0]["scopeSpans"][0]["spans"][0]["attributes"]
            .as_array()
            .unwrap();
        let find = |key: &str| {
            attrs
                .iter()
                .find(|a| a["key"] == key)
                .and_then(|a| a["value"]["stringValue"].as_str())
        };
        assert_eq!(find("recall.outcome"), Some("error"));
        assert_eq!(find("recall.cause"), Some("embedder_unreachable"));
        let ok = otlp_trace_body(&entry(), &[], &new_ids(), 2_000_000_000_000);
        assert!(ok.contains("\"success\"") && !ok.contains("recall.cause"));
    }

    #[test]
    fn resource_attributes_split_on_commas_and_drop_malformed_pairs() {
        assert_eq!(
            parse_resource_attributes("review.run=1, team = a=b ,bad,=x,,k="),
            [
                ("review.run".to_owned(), "1".to_owned()),
                ("team".to_owned(), "a=b".to_owned()),
                ("k".to_owned(), String::new()),
            ]
        );
        assert!(parse_resource_attributes("").is_empty());
    }

    #[test]
    fn only_attributes_that_make_valid_loki_labels_become_labels() {
        let pairs = [
            ("review.run", "1"),
            ("9lives", "x"),
            ("has-dash", "x"),
            ("host_name", "h"),
        ]
        .map(|(k, v)| (k.to_owned(), v.to_owned()));
        assert_eq!(
            loki_labels_from(&pairs),
            [
                ("review_run".to_owned(), "1".to_owned()),
                ("host_name".to_owned(), "h".to_owned())
            ]
        );
    }

    #[test]
    fn to_line_is_what_loki_stores() {
        let body = loki_push_body(&entry(), &[], 1);
        assert!(body.contains(&to_line(&entry()).trim().replace('"', "\\\"")));
    }
}
