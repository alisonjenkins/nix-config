use crate::event::Event;
use chrono::{TimeZone, Utc};
use serde::Deserialize;
use std::collections::BTreeMap;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum LokiError {
    #[error("requesting Loki query_range: {0}")]
    Request(#[from] reqwest::Error),
    #[error("Loki returned status {status}: {body}")]
    Status { status: u16, body: String },
    #[error("parsing Loki query_range response: {0}")]
    Parse(#[from] serde_json::Error),
    #[error("Loki log entry had a non-numeric or malformed timestamp: {0:?}")]
    MalformedTimestamp(String),
}

#[derive(Debug, Deserialize)]
struct QueryRangeResponse {
    data: QueryRangeData,
}

#[derive(Debug, Deserialize)]
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

    let mut events = Vec::new();
    for stream in parsed.data.result {
        for [ns_timestamp, line] in stream.values {
            let nanos: i64 = ns_timestamp
                .parse()
                .map_err(|_| LokiError::MalformedTimestamp(ns_timestamp.clone()))?;
            #[allow(clippy::arithmetic_side_effects)] // Loki timestamps are nanoseconds since epoch as returned by the platform; division by 1_000_000_000 cannot overflow.
            let seconds = nanos / 1_000_000_000;
            let timestamp = Utc
                .timestamp_opt(seconds, 0)
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
) -> Result<Vec<Event>, LokiError> {
    let client = reqwest::blocking::Client::new();
    let response = client
        .get(format!("{base_url}/loki/api/v1/query_range"))
        .query(&[
            ("query", query.to_string()),
            ("start", start_unix_ns.to_string()),
            ("end", end_unix_ns.to_string()),
            ("limit", limit.to_string()),
        ])
        .send()?;

    let status = response.status();
    if !status.is_success() {
        let body = response.text().unwrap_or_default();
        return Err(LokiError::Status {
            status: status.as_u16(),
            body,
        });
    }

    let body = response.text()?;
    parse_query_range_response(&body)
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]
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
    fn rejects_malformed_json() {
        let result = parse_query_range_response("not json");
        assert!(result.is_err());
    }

    #[test]
    fn rejects_a_non_numeric_timestamp() {
        let bad = r#"{"data":{"result":[{"stream":{},"values":[["not-a-number","x"]]}]}}"#;
        let result = parse_query_range_response(bad);
        assert!(matches!(result, Err(LokiError::MalformedTimestamp(_))));
    }
}
