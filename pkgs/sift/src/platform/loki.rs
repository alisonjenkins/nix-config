use crate::auth::Auth;
use crate::event::Event;
use chrono::{TimeZone, Utc};
use serde::Deserialize;
use std::collections::BTreeMap;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum LokiError {
    #[error("sending Loki query_range request: {0}")]
    RequestFailed(reqwest::Error),
    #[error("reading Loki query_range response body: {0}")]
    ResponseReadFailed(reqwest::Error),
    #[error("Loki returned status {status}: {body}")]
    Status { status: u16, body: String },
    #[error("parsing Loki query_range response: {0}")]
    Parse(#[from] serde_json::Error),
    #[error("Loki log entry had a non-numeric or malformed timestamp: {0:?}")]
    MalformedTimestamp(String),
    #[error("Loki query_range reported status {status:?}: {message}")]
    ApiError { status: String, message: String },
}

#[derive(Debug, Deserialize)]
struct QueryRangeResponse {
    status: String,
    #[serde(default)]
    data: Option<QueryRangeData>,
    #[serde(rename = "errorType", default)]
    error_type: Option<String>,
    #[serde(default)]
    error: Option<String>,
}

#[derive(Debug, Deserialize, Default)]
struct QueryRangeData {
    result: Vec<StreamResult>,
}

#[derive(Debug, Deserialize)]
struct StreamResult {
    stream: BTreeMap<String, String>,
    values: Vec<[String; 2]>,
}

/// Parses a Loki `/loki/api/v1/query_range` JSON response body into
/// `Event`s. Pure function — no I/O — so it's testable against a fixture
/// string without a running Loki instance.
pub fn parse_query_range_response(body: &str) -> Result<Vec<Event>, LokiError> {
    let parsed: QueryRangeResponse = serde_json::from_str(body)?;

    if parsed.status != "success" {
        let message = parsed
            .error
            .or(parsed.error_type)
            .unwrap_or_else(|| "no error message provided".to_string());
        return Err(LokiError::ApiError {
            status: parsed.status,
            message,
        });
    }

    let mut events = Vec::new();
    for stream in parsed.data.unwrap_or_default().result {
        for [ns_timestamp, line] in stream.values {
            let nanos: i64 = ns_timestamp
                .parse()
                .map_err(|_| LokiError::MalformedTimestamp(ns_timestamp.clone()))?;
            // div_euclid/rem_euclid, not `/`/`%`, so a full nanosecond
            // timestamp keeps its sub-second precision instead of being
            // truncated to whole seconds — two log lines a few
            // nanoseconds apart must not collapse to the same instant.
            let seconds = nanos.div_euclid(1_000_000_000);
            let nanos_remainder = nanos.rem_euclid(1_000_000_000) as u32;
            let timestamp = Utc
                .timestamp_opt(seconds, nanos_remainder)
                .single()
                .ok_or_else(|| LokiError::MalformedTimestamp(ns_timestamp.clone()))?;

            events.push(Event {
                timestamp,
                labels: stream.stream.clone(),
                value: None,
                body: Some(line),
            });
        }
    }

    Ok(events)
}

/// Queries a Loki instance's `/loki/api/v1/query_range` endpoint and
/// returns parsed events. Not unit-tested directly — it's a thin
/// wrapper around `reqwest` plus `parse_query_range_response`, which
/// carries the actual logic and is tested above.
pub fn fetch(
    base_url: &str,
    query: &str,
    start_unix_ns: i64,
    end_unix_ns: i64,
    limit: usize,
    auth: &Auth,
) -> Result<Vec<Event>, LokiError> {
    let client = reqwest::blocking::Client::new();
    let request = client
        .get(format!("{base_url}/loki/api/v1/query_range"))
        .query(&[
            ("query", query.to_string()),
            ("start", start_unix_ns.to_string()),
            ("end", end_unix_ns.to_string()),
            ("limit", limit.to_string()),
        ]);
    let response = auth.apply(request).send().map_err(LokiError::RequestFailed)?;

    let status = response.status();
    if !status.is_success() {
        let body = match response.text() {
            Ok(body) => body,
            Err(read_err) => format!("<failed to read error response body: {read_err}>"),
        };
        return Err(LokiError::Status {
            status: status.as_u16(),
            body,
        });
    }

    let body = response.text().map_err(LokiError::ResponseReadFailed)?;
    parse_query_range_response(&body)
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

    const SAMPLE_RESPONSE: &str = r#"{
        "status": "success",
        "data": {
            "resultType": "streams",
            "result": [
                {
                    "stream": { "app": "checkout", "level": "error" },
                    "values": [
                        ["1725000000000000000", "connection timeout"],
                        ["1725000001000000000", "connection timeout"]
                    ]
                }
            ]
        }
    }"#;

    #[test]
    fn parses_streams_into_events_with_labels_and_body() {
        let events = parse_query_range_response(SAMPLE_RESPONSE).unwrap();

        assert_eq!(events.len(), 2);
        assert_eq!(events[0].labels.get("app"), Some(&"checkout".to_string()));
        assert_eq!(events[0].labels.get("level"), Some(&"error".to_string()));
        assert_eq!(events[0].body, Some("connection timeout".to_string()));
        assert_eq!(events[0].value, None);
    }

    #[test]
    fn preserves_sub_second_timestamp_precision() {
        let body = r#"{"status":"success","data":{"result":[{"stream":{},"values":[["1725000000123456789","x"]]}]}}"#;

        let events = parse_query_range_response(body).unwrap();

        assert_eq!(events[0].timestamp.timestamp(), 1725000000);
        assert_eq!(events[0].timestamp.timestamp_subsec_nanos(), 123456789);
    }

    #[test]
    fn rejects_malformed_json() {
        let result = parse_query_range_response("not json");
        assert!(result.is_err());
    }

    #[test]
    fn rejects_a_non_numeric_timestamp() {
        let bad = r#"{"status":"success","data":{"result":[{"stream":{},"values":[["not-a-number","x"]]}]}}"#;
        let result = parse_query_range_response(bad);
        assert!(matches!(result, Err(LokiError::MalformedTimestamp(_))));
    }

    #[test]
    fn surfaces_loki_api_level_error_status_and_message() {
        // A 200 response body can still carry status="error" — this
        // used to fall through to a generic serde JSON-parse failure
        // and discard Loki's structured error message. Regression test
        // for the Copilot-review finding.
        let body = r#"{"status":"error","errorType":"bad_data","error":"parse error: unexpected character"}"#;

        let result = parse_query_range_response(body);

        match result {
            Err(LokiError::ApiError { status, message }) => {
                assert_eq!(status, "error");
                assert_eq!(message, "parse error: unexpected character");
            }
            other => panic!("expected LokiError::ApiError, got {other:?}"),
        }
    }
}
