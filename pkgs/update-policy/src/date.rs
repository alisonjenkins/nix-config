//! Minimal civil-date handling (YYYY-MM-DD), enough to compare review dates.

use std::fmt;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub struct Date {
    /// Days since 1970-01-01.
    days: i64,
}

impl Date {
    pub fn parse(s: &str) -> Option<Date> {
        let mut it = s.split('-');
        let (y, m, d) = (it.next()?, it.next()?, it.next()?);
        if it.next().is_some() || y.len() != 4 || m.len() != 2 || d.len() != 2 {
            return None;
        }
        let (y, m, d): (i64, u32, u32) = (y.parse().ok()?, m.parse().ok()?, d.parse().ok()?);
        if !(1..=12).contains(&m) || d == 0 || d > days_in_month(y, m) {
            return None;
        }
        Some(Date { days: days_from_civil(y, m, d) })
    }

    pub fn from_unix_seconds(secs: i64) -> Date {
        Date { days: secs.div_euclid(86_400) }
    }

    pub fn today() -> Date {
        Date::from_unix_seconds(now_unix_seconds())
    }

    pub fn plus_days(self, n: u32) -> Date {
        Date { days: self.days + i64::from(n) }
    }

    pub fn days_until(self, later: Date) -> i64 {
        later.days - self.days
    }
}

/// Seconds since the Unix epoch for a UTC RFC 3339 timestamp as GitHub writes
/// it (`2026-11-23T22:39:57Z`, optionally with fractional seconds). Offsets
/// other than `Z` are rejected rather than guessed at.
pub fn parse_utc_timestamp(s: &str) -> Option<i64> {
    let s = s.strip_suffix('Z')?;
    let (date, time) = s.split_once('T')?;
    let date = Date::parse(date)?;
    let time = time.split_once('.').map_or(time, |(whole, frac)| {
        if !frac.is_empty() && frac.bytes().all(|b| b.is_ascii_digit()) { whole } else { "" }
    });
    let mut it = time.split(':');
    let (h, m, sec) = (it.next()?, it.next()?, it.next()?);
    if it.next().is_some() || [h, m, sec].iter().any(|p| p.len() != 2 || !p.bytes().all(|b| b.is_ascii_digit())) {
        return None;
    }
    let (h, m, sec): (i64, i64, i64) = (h.parse().ok()?, m.parse().ok()?, sec.parse().ok()?);
    if h > 23 || m > 59 || sec > 60 {
        return None;
    }
    Some(date.days * 86_400 + h * 3_600 + m * 60 + sec)
}

/// Seconds since the Unix epoch now.
pub fn now_unix_seconds() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

fn is_leap(y: i64) -> bool {
    (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
}

fn days_in_month(y: i64, m: u32) -> u32 {
    match m {
        2 if is_leap(y) => 29,
        2 => 28,
        4 | 6 | 9 | 11 => 30,
        _ => 31,
    }
}

/// Howard Hinnant's days_from_civil.
fn days_from_civil(y: i64, m: u32, d: u32) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let m = m as i64;
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + d as i64 - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (if m <= 2 { y + 1 } else { y }, m, d)
}

impl fmt::Display for Date {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let (y, m, d) = civil_from_days(self.days);
        write!(f, "{y:04}-{m:02}-{d:02}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn epoch_and_known_dates() {
        assert_eq!(Date::parse("1970-01-01").unwrap().days, 0);
        assert_eq!(Date::parse("2000-03-01").unwrap().days, 11_017);
        assert_eq!(Date::parse("2026-11-20").unwrap(), Date::from_unix_seconds(1_795_132_800));
    }

    #[test]
    fn round_trips_through_display() {
        for s in ["1970-01-01", "2024-02-29", "2026-11-20", "2100-12-31", "1969-12-31"] {
            assert_eq!(Date::parse(s).unwrap().to_string(), s);
        }
    }

    #[test]
    fn every_day_from_1600_to_2400_round_trips() {
        let start = Date::parse("1600-01-01").unwrap().days;
        let end = Date::parse("2400-12-31").unwrap().days;
        let mut expected = (1600_i64, 1_u32, 1_u32);
        for days in start..=end {
            let (y, m, d) = civil_from_days(days);
            assert_eq!((y, m, d), expected, "day {days}");
            assert_eq!(days_from_civil(y, m, d), days);
            expected = if d < days_in_month(y, m) {
                (y, m, d + 1)
            } else if m < 12 {
                (y, m + 1, 1)
            } else {
                (y + 1, 1, 1)
            };
        }
    }

    #[test]
    fn rejects_invalid() {
        for bad in ["2026-02-30", "2025-02-29", "2100-02-29", "2026-13-01", "2026-00-10", "2026-1-01",
                    "26-01-01", "2026-01-01-01", "x", "2026-01-00", "2026-04-31"] {
            assert!(Date::parse(bad).is_none(), "{bad}");
        }
        assert!(Date::parse("2000-02-29").is_some());
        assert!(Date::parse("2026-12-31").is_some());
    }

    #[test]
    fn days_until() {
        let a = Date::parse("2026-11-20").unwrap();
        let b = Date::parse("2026-12-01").unwrap();
        assert_eq!(a.days_until(b), 11);
        assert_eq!(b.days_until(a), -11);
        assert!(a < b);
        assert_eq!(a.plus_days(11), b);
        assert_eq!(a.plus_days(0), a);
    }

    #[test]
    fn parses_github_timestamps() {
        assert_eq!(parse_utc_timestamp("1970-01-01T00:00:00Z"), Some(0));
        assert_eq!(parse_utc_timestamp("1970-01-02T01:02:03Z"), Some(86_400 + 3_723));
        assert_eq!(parse_utc_timestamp("2026-11-23T22:39:57Z"), Some(1_795_132_800 + 3 * 86_400 + 81_597));
        assert_eq!(parse_utc_timestamp("2026-11-23T22:39:57.123Z"), parse_utc_timestamp("2026-11-23T22:39:57Z"));
        assert_eq!(parse_utc_timestamp("2026-11-23T23:59:60Z"), Some(1_795_132_800 + 4 * 86_400));
    }

    #[test]
    fn rejects_bad_timestamps() {
        for bad in ["2026-11-23T22:39:57", "2026-11-23T22:39:57+01:00", "2026-11-23 22:39:57Z", "2026-11-23T24:00:00Z",
                    "2026-11-23T22:60:00Z", "2026-11-23T22:39:61Z", "2026-11-23T2:39:57Z", "2026-11-23T22:39Z",
                    "2026-11-23T22:39:57:00Z", "2026-11-23T22:39:57.Z", "2026-11-23T22:39:57.1aZ", "2026-02-30T00:00:00Z",
                    "2026-11-23T+1:39:57Z", ""] {
            assert_eq!(parse_utc_timestamp(bad), None, "{bad}");
        }
    }

    #[test]
    fn now_is_after_this_code_was_written() {
        assert!(now_unix_seconds() > 1_795_000_000);
    }

    #[test]
    fn negative_unix_seconds_round_down() {
        assert_eq!(Date::from_unix_seconds(-1).to_string(), "1969-12-31");
        assert_eq!(Date::from_unix_seconds(86_399).to_string(), "1970-01-01");
    }
}
