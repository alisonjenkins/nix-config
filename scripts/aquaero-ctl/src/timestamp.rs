//! UTC timestamps in ISO 8601, without a date-time dependency.

use std::time::{SystemTime, UNIX_EPOCH};

/// 9999-12-31T23:59:59Z. Larger values are clamped so the civil-date
/// arithmetic below cannot overflow and the year always has four digits.
const MAX_UNIX_SECS: i64 = 253_402_300_799;

const SECS_PER_DAY: i64 = 86_400;

/// A second-resolution instant, always UTC.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub struct UtcTimestamp {
    secs: i64,
}

impl UtcTimestamp {
    /// Seconds since 1970-01-01T00:00:00Z, clamped to years 1970 to 9999.
    pub fn from_unix(secs: i64) -> Self {
        Self {
            secs: secs.clamp(0, MAX_UNIX_SECS),
        }
    }

    /// The current time. A clock set before 1970 reads as the epoch.
    pub fn now() -> Self {
        let secs = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .ok()
            .and_then(|d| i64::try_from(d.as_secs()).ok())
            .unwrap_or(0);
        Self::from_unix(secs)
    }

    /// `2026-10-13T09:50:12Z`.
    pub fn iso(&self) -> String {
        let c = self.civil();
        format!(
            "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
            c.year, c.month, c.day, c.hour, c.minute, c.second
        )
    }

    /// `20261013T095012Z`: the same instant without separators, for file
    /// names. It sorts in time order.
    pub fn compact(&self) -> String {
        let c = self.civil();
        format!(
            "{:04}{:02}{:02}T{:02}{:02}{:02}Z",
            c.year, c.month, c.day, c.hour, c.minute, c.second
        )
    }

    // Every operand is bounded by the clamp in `from_unix` (at most year 9999),
    // so none of this arithmetic can overflow an i64.
    #[allow(clippy::arithmetic_side_effects)]
    fn civil(&self) -> Civil {
        // Civil-from-days after Howard Hinnant's date algorithms.
        let days = self.secs.div_euclid(SECS_PER_DAY);
        let secs_of_day = self.secs.rem_euclid(SECS_PER_DAY);

        let z = days + 719_468;
        let era = z.div_euclid(146_097);
        let doe = z.rem_euclid(146_097);
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        let mp = (5 * doy + 2) / 153;
        let day = doy - (153 * mp + 2) / 5 + 1;
        let month = if mp < 10 { mp + 3 } else { mp - 9 };
        let year = yoe + era * 400 + i64::from(month <= 2);

        Civil {
            year,
            month,
            day,
            hour: secs_of_day / 3_600,
            minute: secs_of_day % 3_600 / 60,
            second: secs_of_day % 60,
        }
    }
}

struct Civil {
    year: i64,
    month: i64,
    day: i64,
    hour: i64,
    minute: i64,
    second: i64,
}
