//! Time windows: `--since 7d`, `--until 2026-10-09`, `2026-09-01..2026-09-08`.
use time::format_description::well_known::Rfc3339;
use time::{Date, Month, OffsetDateTime};

use crate::error::Error;

pub const DEFAULT_SINCE: &str = "7d";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Window {
    pub secs: u64,
    /// Unix seconds the window ends at; `None` means now.
    pub end: Option<i64>,
}

impl Window {
    pub fn end_unix(&self) -> i64 {
        self.end.unwrap_or_else(now_unix)
    }

    pub fn start_unix(&self) -> i64 {
        self.end_unix()
            .saturating_sub(i64::try_from(self.secs).unwrap_or(i64::MAX))
    }

    /// PromQL range literal, e.g. `604800s`.
    pub fn prom(&self) -> String {
        format!("{}s", self.secs)
    }

    pub fn ending(self, end: Option<i64>) -> Self {
        Self { end, ..self }
    }
}

pub fn now_unix() -> i64 {
    OffsetDateTime::now_utc().unix_timestamp()
}

pub fn iso(unix: i64) -> String {
    OffsetDateTime::from_unix_timestamp(unix)
        .ok()
        .and_then(|t| t.format(&Rfc3339).ok())
        .unwrap_or_default()
}

pub fn parse_iso(text: &str) -> Option<i64> {
    OffsetDateTime::parse(text, &Rfc3339)
        .ok()
        .map(OffsetDateTime::unix_timestamp)
}

fn parse_date(text: &str) -> Option<i64> {
    let mut parts = text.split('-');
    let year = parts.next()?.parse::<i32>().ok()?;
    let month = Month::try_from(parts.next()?.parse::<u8>().ok()?).ok()?;
    let day = parts.next()?.parse::<u8>().ok()?;
    if parts.next().is_some() {
        return None;
    }
    let date = Date::from_calendar_date(year, month, day).ok()?;
    Some(date.midnight().assume_utc().unix_timestamp())
}

pub fn parse_since(value: &str) -> Result<Window, Error> {
    let bad = |reason: &str| Error::BadArgument {
        flag: "--since",
        value: value.to_owned(),
        reason: reason.to_owned(),
    };
    let unit = value.chars().last().ok_or_else(|| bad("empty"))?;
    let unit_secs: u64 = match unit {
        's' => 1,
        'm' => 60,
        'h' => 3600,
        'd' => 86_400,
        'w' => 604_800,
        _ => return Err(bad("unit must be one of s, m, h, d, w")),
    };
    let count = value
        .strip_suffix(unit)
        .and_then(|digits| digits.parse::<u64>().ok())
        .ok_or_else(|| bad("expected a whole number before the unit"))?;
    let secs = count
        .checked_mul(unit_secs)
        .filter(|s| *s > 0)
        .ok_or_else(|| bad("must be positive and fit in 64 bits"))?;
    Ok(Window { secs, end: None })
}

pub fn parse_until(value: &str) -> Result<i64, Error> {
    parse_date(value).ok_or_else(|| Error::BadArgument {
        flag: "--until",
        value: value.to_owned(),
        reason: "expected a date like 2026-10-09".to_owned(),
    })
}

pub fn parse_range(flag: &'static str, value: &str) -> Result<Window, Error> {
    let bad = |reason: &str| Error::BadArgument {
        flag,
        value: value.to_owned(),
        reason: reason.to_owned(),
    };
    let (from, to) = value
        .split_once("..")
        .ok_or_else(|| bad("expected START..END"))?;
    let start = parse_date(from).ok_or_else(|| bad("START is not a date like 2026-09-01"))?;
    let end = parse_date(to).ok_or_else(|| bad("END is not a date like 2026-09-08"))?;
    let secs = u64::try_from(end.saturating_sub(start))
        .ok()
        .filter(|s| *s > 0)
        .ok_or_else(|| bad("END must be after START"))?;
    Ok(Window {
        secs,
        end: Some(end),
    })
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    #[test]
    fn since_units() {
        for (text, secs) in [
            ("30s", 30),
            ("5m", 300),
            ("2h", 7200),
            ("7d", 604_800),
            ("1w", 604_800),
        ] {
            assert_eq!(parse_since(text).unwrap().secs, secs, "{text}");
        }
        for text in ["", "d", "7", "0d", "7x", "-1d", "1.5d"] {
            assert!(parse_since(text).is_err(), "{text}");
        }
    }

    #[test]
    fn range_is_midnight_to_midnight() {
        let w = parse_range("--a", "2026-09-01..2026-09-08").unwrap();
        assert_eq!(w.secs, 604_800);
        assert_eq!(w.end, Some(1_788_825_600));
        assert!(parse_range("--a", "2026-09-08..2026-09-01").is_err());
        assert!(parse_range("--a", "2026-13-01..2026-14-01").is_err());
    }

    #[test]
    fn iso_round_trip() {
        assert_eq!(iso(1_791_504_000), "2026-10-09T00:00:00Z");
        assert_eq!(parse_iso("2026-10-09T00:00:00Z"), Some(1_791_504_000));
    }
}
