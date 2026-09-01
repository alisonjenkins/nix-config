use crate::event::Event;
use chrono::{DateTime, TimeZone, Utc};
use serde::Serialize;
use std::collections::BTreeMap;
use std::time::Duration;
use thiserror::Error;

#[derive(Debug, Error, PartialEq)]
pub enum HistogramError {
    #[error("invalid bucket duration {0:?}: {1}")]
    InvalidBucketDuration(String, String),
}

#[derive(Debug, Serialize, PartialEq)]
pub struct HistogramBucket {
    pub bucket_start: DateTime<Utc>,
    pub count: usize,
}

#[derive(Debug, Serialize, PartialEq)]
pub struct HistogramResult {
    pub buckets: Vec<HistogramBucket>,
}

pub fn parse_bucket_duration(input: &str) -> Result<Duration, HistogramError> {
    let duration = humantime::parse_duration(input)
        .map_err(|e| HistogramError::InvalidBucketDuration(input.to_string(), e.to_string()))?;

    // histogram() casts bucket.as_secs() to i64; a duration whose
    // seconds don't fit would wrap to a negative bucket size there.
    if i64::try_from(duration.as_secs()).is_err() {
        return Err(HistogramError::InvalidBucketDuration(
            input.to_string(),
            "duration exceeds i64::MAX seconds".to_string(),
        ));
    }

    Ok(duration)
}

pub fn histogram(events: &[Event], bucket: Duration) -> HistogramResult {
    let bucket_seconds = bucket.as_secs().max(1) as i64;
    let mut counts: BTreeMap<i64, usize> = BTreeMap::new();

    for event in events {
        #[allow(clippy::arithmetic_side_effects)] // timestamp() is a real calendar second count, far below i64::MAX for any event this tool will ever see; bucket_seconds is >= 1 by construction above.
        let bucket_index = event.timestamp.timestamp() / bucket_seconds;
        let entry = counts.entry(bucket_index).or_insert(0);
        *entry = entry.saturating_add(1);
    }

    let buckets = counts
        .into_iter()
        .map(|(bucket_index, count)| {
            #[allow(clippy::arithmetic_side_effects)] // same bound as above: bucket_index * bucket_seconds stays far below i64::MAX.
            let bucket_start_secs = bucket_index * bucket_seconds;
            HistogramBucket {
                bucket_start: Utc
                    .timestamp_opt(bucket_start_secs, 0)
                    .single()
                    .unwrap_or_else(Utc::now),
                count,
            }
        })
        .collect();

    HistogramResult { buckets }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]
    use super::*;

    fn event_at(unix_seconds: i64) -> Event {
        Event {
            timestamp: Utc.timestamp_opt(unix_seconds, 0).single().unwrap_or_else(Utc::now),
            labels: BTreeMap::new(),
            value: None,
            body: None,
        }
    }

    #[test]
    fn parses_a_valid_duration_string() {
        let result = parse_bucket_duration("5m");
        assert_eq!(result, Ok(Duration::from_secs(300)));
    }

    #[test]
    fn rejects_an_invalid_duration_string() {
        let result = parse_bucket_duration("not-a-duration");
        assert!(result.is_err());
    }

    #[test]
    fn rejects_a_duration_whose_seconds_overflow_i64() {
        // humantime parses this fine as a u64-second Duration, but
        // histogram() later casts .as_secs() to i64, which would wrap
        // negative for a value this large. Regression test for the
        // Copilot-review finding.
        let result = parse_bucket_duration("500000000000y");
        assert!(result.is_err());
    }

    #[test]
    fn groups_events_into_time_buckets() {
        // Two events one second apart both fall in the same 60s bucket
        // starting at unix time 0; a third event 65s later falls in
        // the next bucket.
        let events = vec![event_at(0), event_at(1), event_at(65)];

        let result = histogram(&events, Duration::from_secs(60));

        assert_eq!(result.buckets.len(), 2);
        assert_eq!(result.buckets[0].count, 2);
        assert_eq!(result.buckets[1].count, 1);
    }
}
