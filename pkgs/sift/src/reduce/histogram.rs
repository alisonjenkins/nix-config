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

    // histogram() only buckets at whole-second granularity
    // (bucket.as_secs()) — silently accepting "0s"/"500ms" (as_secs()
    // == 0) or "1500ms" (as_secs() == 1 but a nonzero subsec_nanos())
    // would discard the caller's requested sub-second resolution
    // without telling them.
    if duration.as_secs() == 0 || duration.subsec_nanos() != 0 {
        return Err(HistogramError::InvalidBucketDuration(
            input.to_string(),
            "duration must be a whole number of seconds, at least 1s (sub-second buckets are not supported)"
                .to_string(),
        ));
    }

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
    // `bucket` is normally produced by parse_bucket_duration, which
    // already rejects a seconds count too large for i64 — but
    // histogram() is a public fn any caller can invoke directly with
    // an arbitrary Duration, so clamp defensively rather than wrap
    // negative on the `as i64` cast.
    let bucket_seconds = bucket.as_secs().min(i64::MAX as u64).max(1) as i64;
    let mut counts: BTreeMap<i64, usize> = BTreeMap::new();

    for event in events {
        // div_euclid, not `/` — plain integer division truncates
        // toward zero, which puts a pre-epoch event like -1s into
        // bucket 0 instead of the preceding bucket. div_euclid is
        // floor division, correct for both signs.
        let bucket_index = event.timestamp.timestamp().div_euclid(bucket_seconds);
        let entry = counts.entry(bucket_index).or_insert(0);
        *entry = entry.saturating_add(1);
    }

    let buckets = counts
        .into_iter()
        .map(|(bucket_index, count)| {
            #[allow(clippy::arithmetic_side_effects)] // same bound as above: bucket_index * bucket_seconds stays far below i64::MAX.
            let bucket_start_secs = bucket_index * bucket_seconds;
            HistogramBucket {
                // bucket_start_secs is a product of two real, bounded
                // i64 values, so this can't fail in practice — but a
                // deterministic sentinel (not the current wall clock)
                // keeps a hypothetical failure visibly wrong rather
                // than silently plausible.
                bucket_start: Utc
                    .timestamp_opt(bucket_start_secs, 0)
                    .single()
                    .unwrap_or(DateTime::<Utc>::MIN_UTC),
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
    fn rejects_a_sub_second_bucket_duration() {
        // humantime parses "500ms" fine, but histogram() only buckets
        // at whole-second granularity — silently rounding this up to
        // 1s would discard the caller's requested resolution without
        // telling them. Regression test for the Copilot-review finding.
        let result = parse_bucket_duration("500ms");
        assert!(matches!(
            result,
            Err(HistogramError::InvalidBucketDuration(_, _))
        ));
    }

    #[test]
    fn rejects_a_zero_second_bucket_duration() {
        let result = parse_bucket_duration("0s");
        assert!(matches!(
            result,
            Err(HistogramError::InvalidBucketDuration(_, _))
        ));
    }

    #[test]
    fn rejects_a_bucket_duration_with_a_nonzero_fractional_second() {
        // as_secs() == 1 here, so the earlier as_secs()==0 check alone
        // would miss this — histogram() would still silently bucket
        // it as a whole 1s, discarding the 500ms the caller asked for.
        // Regression test for the Copilot-review finding.
        let result = parse_bucket_duration("1500ms");
        assert!(matches!(
            result,
            Err(HistogramError::InvalidBucketDuration(_, _))
        ));
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

    #[test]
    fn a_pre_epoch_event_falls_in_the_preceding_bucket_not_bucket_zero() {
        // Plain `/` truncates toward zero, so -1i64 / 60 == 0 — that
        // would put a 1-second-before-epoch event in the same bucket
        // as epoch itself. div_euclid is floor division: -1 belongs to
        // the bucket starting at -60, not 0. Regression test for the
        // Copilot-review finding.
        let events = vec![event_at(-1), event_at(0)];

        let result = histogram(&events, Duration::from_secs(60));

        assert_eq!(result.buckets.len(), 2);
        assert_eq!(result.buckets[0].bucket_start.timestamp(), -60);
        assert_eq!(result.buckets[0].count, 1);
        assert_eq!(result.buckets[1].bucket_start.timestamp(), 0);
        assert_eq!(result.buckets[1].count, 1);
    }

    #[test]
    fn does_not_wrap_negative_for_a_bucket_duration_that_bypasses_parse_bucket_duration() {
        // histogram() is public and callable with any Duration, not
        // just one that went through parse_bucket_duration's i64
        // guard. Regression test for the Copilot-review finding: this
        // used to panic or bucket with a wrapped-negative bucket size.
        let events = vec![event_at(0)];

        let result = histogram(&events, Duration::from_secs(u64::MAX));

        assert_eq!(result.buckets.len(), 1);
        assert_eq!(result.buckets[0].count, 1);
    }
}
