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
    #[error("Prometheus/Mimir sample had a timestamp that could not be constructed: {0:?}")]
    MalformedTimestamp(String),
    #[error("Prometheus/Mimir query_range reported status {status:?}: {message}")]
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

    if parsed.status != "success" {
        let message = parsed
            .error
            .or(parsed.error_type)
            .unwrap_or_else(|| "no error message provided".to_string());
        return Err(PrometheusError::ApiError {
            status: parsed.status,
            message,
        });
    }

    let mut events = Vec::new();
    for series in parsed.data.unwrap_or_default().result {
        for (unix_seconds_float, value_str) in series.values {
            let value: f64 = value_str
                .parse()
                .map_err(|_| PrometheusError::MalformedValue(value_str.clone()))?;

            // Prometheus timestamps are float seconds since epoch and
            // can carry sub-second precision (e.g. 1725000000.123) —
            // split into whole seconds and a nanosecond remainder
            // rather than truncating the fractional part away, the
            // same precision loss `platform::loki` had before its fix.
            //
            // floor() (not trunc()) is required so this stays correct
            // for a timestamp before the epoch: fract() on a negative
            // float is itself negative, which would wrap to a huge
            // value on the `as u32` cast below. floor()-then-subtract
            // keeps the remainder in [0.0, 1.0) regardless of sign.
            let whole_seconds = unix_seconds_float.floor() as i64;
            #[allow(clippy::arithmetic_side_effects)] // whole_seconds is unix_seconds_float.floor(), so this difference stays within [0.0, 1.0).
            let fractional_seconds = unix_seconds_float - whole_seconds as f64;
            #[allow(clippy::arithmetic_side_effects)] // fractional_seconds is in [0.0, 1.0), so this product stays within [0.0, 1_000_000_000.0] and fits u32 after rounding.
            let rounded_subsec_nanos = (fractional_seconds * 1_000_000_000.0).round() as u32;

            // round() on a fract() close to 1.0 can produce exactly
            // 1_000_000_000, which Utc::timestamp_opt rejects as an
            // invalid nanosecond field — carry it into the next second
            // instead of passing it through.
            let (seconds, subsec_nanos) = if rounded_subsec_nanos == 1_000_000_000 {
                (
                    whole_seconds.checked_add(1).ok_or_else(|| {
                        PrometheusError::MalformedTimestamp(unix_seconds_float.to_string())
                    })?,
                    0,
                )
            } else {
                (whole_seconds, rounded_subsec_nanos)
            };

            let timestamp = Utc
                .timestamp_opt(seconds, subsec_nanos)
                .single()
                .ok_or_else(|| {
                    PrometheusError::MalformedTimestamp(unix_seconds_float.to_string())
                })?;

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
        let body = match response.text() {
            Ok(body) => body,
            Err(read_err) => format!("<failed to read error response body: {read_err}>"),
        };
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
        let body = r#"{"status":"success","data":{"result":[{"metric":{},"values":[[1725000000.123,"1"]]}]}}"#;

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
    fn carries_a_fractional_second_that_rounds_up_to_a_whole_second() {
        // fract() here is 0.9999999995, which * 1_000_000_000 rounds to
        // exactly 1_000_000_000 — an invalid nanosecond field on its
        // own second. Regression test for the Copilot-review finding:
        // this used to make Utc::timestamp_opt return None.
        let body = r#"{"status":"success","data":{"result":[{"metric":{},"values":[[1.9999999995,"1"]]}]}}"#;

        let events = parse_query_range_response(body).unwrap();

        assert_eq!(events[0].timestamp.timestamp(), 2);
        assert_eq!(events[0].timestamp.timestamp_subsec_nanos(), 0);
    }

    #[test]
    fn handles_a_pre_epoch_timestamp_correctly() {
        // trunc()/fract() would have given whole_seconds=-1,
        // fract()=-0.25 here, and casting -0.25 * 1e9 to u32 wraps to
        // a huge value instead of erroring. floor()-based splitting
        // must produce -2 whole seconds with a 0.75s remainder.
        let body = r#"{"status":"success","data":{"result":[{"metric":{},"values":[[-1.25,"1"]]}]}}"#;

        let events = parse_query_range_response(body).unwrap();

        assert_eq!(events[0].timestamp.timestamp(), -2);
        assert_eq!(events[0].timestamp.timestamp_subsec_nanos(), 750_000_000);
    }

    #[test]
    fn rejects_malformed_json() {
        let result = parse_query_range_response("not json");
        assert!(result.is_err());
    }

    #[test]
    fn rejects_a_non_numeric_value() {
        let bad = r#"{"status":"success","data":{"result":[{"metric":{},"values":[[1725000000,"not-a-number"]]}]}}"#;
        let result = parse_query_range_response(bad);
        assert!(matches!(result, Err(PrometheusError::MalformedValue(_))));
    }

    #[test]
    fn surfaces_prometheus_api_level_error_status_and_message() {
        // A 200 response body can still carry status="error" — this
        // used to fall through to a generic serde JSON-parse failure
        // and discard the server's structured error message.
        // Regression test for the Copilot-review finding.
        let body = r#"{"status":"error","errorType":"bad_data","error":"invalid parameter"}"#;

        let result = parse_query_range_response(body);

        match result {
            Err(PrometheusError::ApiError { status, message }) => {
                assert_eq!(status, "error");
                assert_eq!(message, "invalid parameter");
            }
            other => panic!("expected PrometheusError::ApiError, got {other:?}"),
        }
    }
}
