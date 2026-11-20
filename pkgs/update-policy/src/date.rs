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
        let secs = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);
        Date::from_unix_seconds(secs)
    }

    pub fn days_until(self, later: Date) -> i64 {
        later.days - self.days
    }
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
    }

    #[test]
    fn negative_unix_seconds_round_down() {
        assert_eq!(Date::from_unix_seconds(-1).to_string(), "1969-12-31");
        assert_eq!(Date::from_unix_seconds(86_399).to_string(), "1970-01-01");
    }
}
