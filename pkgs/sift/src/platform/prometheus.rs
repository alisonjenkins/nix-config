use crate::event::Event;
use chrono::{TimeZone, Utc};
use serde::Deserialize;
use std::collections::BTreeMap;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum PrometheusError {
    #[error("sending Prometheus/Mimir query_range request: {0}")]
    RequestFailed(reqwest::Error),
    #[error("reading Prometheus/Mimir query_range response body: {0}")]
    ResponseReadFailed(reqwest::Error),
    #[error("Prometheus/Mimir returned status {status}: {body}")]
    Status { status: u16, body: String },
    #[error("parsing Prometheus/Mimir query_range response: {0}")]
    Parse(#[from] serde_json::Error),
    #[error("Prometheus/Mimir sample had a non-numeric value: {0:?}")]
    MalformedValue(String),
}

#[derive(Debug, Deserialize)]
struct QueryRangeResponse {
    data: QueryRangeData,
}

#[derive(Debug, Deserialize)]
struct QueryRangeData {
    result: Vec<MatrixResult>,
}

#[derive(Debug, Deserialize)]
struct MatrixResult {
    metric: BTreeMap<String, String>,
    values: Vec<(f64, String)>,
}

/// Parses a Prometheus/Mimir `/api/v1/query_range` JSON response body
/// into `Event`s. Pure function — no I/O — testable against a fixture
/// string without a running instance.
pub fn parse_query_range_response(body: &str) -> Result<Vec<Event>, PrometheusError> {
    let parsed: QueryRangeResponse = serde_json::from_str(body)?;

    let mut events = Vec::new();
    for series in parsed.data.result {
        for (unix_seconds_float, value_str) in series.values {
            let value: f64 = value_str
                .parse()
                .map_err(|_| PrometheusError::MalformedValue(value_str.clone()))?;

            // Prometheus timestamps are float seconds since epoch and
            // can carry sub-second precision (e.g. 1725000000.123) —
            // split into whole seconds and a nanosecond remainder
            // rather than truncating the fractional part away, the
            // same precision loss `platform::loki` had before its fix.
            let seconds = unix_seconds_float.trunc() as i64;
            let fractional_seconds = unix_seconds_float.fract();
            #[allow(clippy::arithmetic_side_effects)] // fract() is in [0.0, 1.0), so this product stays within [0.0, 1_000_000_000.0) and fits u32 after truncation.
            let subsec_nanos = (fractional_seconds * 1_000_000_000.0).round() as u32;

            let timestamp = Utc
                .timestamp_opt(seconds, subsec_nanos)
                .single()
                .ok_or_else(|| PrometheusError::MalformedValue(value_str.clone()))?;

            events.push(Event {
                timestamp,
                labels: series.metric.clone(),
                value: Some(value),
                body: None,
            });
        }
    }

    Ok(events)
}

/// Queries a Prometheus/Mimir instance's `/api/v1/query_range` endpoint
/// and returns parsed events. Not unit-tested directly, same rationale
/// as `loki::fetch`.
pub fn fetch(
    base_url: &str,
    query: &str,
    start_unix_secs: i64,
    end_unix_secs: i64,
    step_secs: u64,
) -> Result<Vec<Event>, PrometheusError> {
    let client = reqwest::blocking::Client::new();
    let response = client
        .get(format!("{base_url}/api/v1/query_range"))
        .query(&[
            ("query", query.to_string()),
            ("start", start_unix_secs.to_string()),
            ("end", end_unix_secs.to_string()),
            ("step", step_secs.to_string()),
        ])
        .send()
        .map_err(PrometheusError::RequestFailed)?;

    let status = response.status();
    if !status.is_success() {
        let body = response.text().unwrap_or_default();
        return Err(PrometheusError::Status {
            status: status.as_u16(),
            body,
        });
    }

    let body = response.text().map_err(PrometheusError::ResponseReadFailed)?;
    parse_query_range_response(&body)
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]
    use super::*;

    const SAMPLE_RESPONSE: &str = r#"{
        "status": "success",
        "data": {
            "resultType": "matrix",
            "result": [
                {
                    "metric": { "__name__": "up", "job": "node" },
                    "values": [
                        [1725000000, "1"],
                        [1725000060, "0"]
                    ]
                }
            ]
        }
    }"#;

    #[test]
    fn parses_matrix_series_into_events_with_labels_and_value() {
        let events = parse_query_range_response(SAMPLE_RESPONSE).unwrap();

        assert_eq!(events.len(), 2);
        assert_eq!(events[0].labels.get("job"), Some(&"node".to_string()));
        assert_eq!(events[0].value, Some(1.0));
        assert_eq!(events[1].value, Some(0.0));
        assert_eq!(events[0].body, None);
    }

    #[test]
    fn preserves_sub_second_timestamp_precision() {
        let body = r#"{"data":{"result":[{"metric":{},"values":[[1725000000.123,"1"]]}]}}"#;

        let events = parse_query_range_response(body).unwrap();

        assert_eq!(events[0].timestamp.timestamp(), 1725000000);
        // 0.123s = 123,000,000ns; float round-trip can be off by a
        // handful of ns, so check within a small tolerance rather than
        // exact equality.
        let nanos = events[0].timestamp.timestamp_subsec_nanos();
        assert!(
            (123_000_000_i64 - i64::from(nanos)).abs() < 1000,
            "expected ~123_000_000 subsec nanos, got {nanos}"
        );
    }

    #[test]
    fn rejects_malformed_json() {
        let result = parse_query_range_response("not json");
        assert!(result.is_err());
    }

    #[test]
    fn rejects_a_non_numeric_value() {
        let bad = r#"{"data":{"result":[{"metric":{},"values":[[1725000000,"not-a-number"]]}]}}"#;
        let result = parse_query_range_response(bad);
        assert!(matches!(result, Err(PrometheusError::MalformedValue(_))));
    }
}
