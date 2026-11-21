//! `pins/sources.json`: the trust tier of every source of code.

use crate::date::Date;
use crate::pattern::Pattern;
use serde::Deserialize;
use std::collections::BTreeMap;
use std::fmt;

pub const SUPPORTED_SCHEMA: u64 = 1;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RawFile {
    pub schema: u64,
    #[serde(rename = "_doc")]
    pub doc: Option<String>,
    pub tiers: BTreeMap<String, Tier>,
    pub sources: Vec<RawEntry>,
    #[serde(default)]
    pub exceptions: Vec<RawException>,
}

#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct Tier {
    pub cooldown_days: u32,
    pub automerge: bool,
    #[serde(default)]
    pub channel_cooldown_days: Option<u32>,
    pub description: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RawEntry {
    #[serde(rename = "match")]
    pub pattern: String,
    pub tier: String,
    #[serde(default)]
    pub note: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RawException {
    #[serde(rename = "match")]
    pub pattern: String,
    pub tier: String,
    pub reason: String,
    pub review_by: String,
}

#[derive(Debug, Clone)]
pub struct Entry {
    pub pattern: Pattern,
    pub tier: String,
    pub exception: Option<ExceptionInfo>,
}

#[derive(Debug, Clone)]
pub struct ExceptionInfo {
    pub reason: String,
    pub review_by: Date,
}

/// A validated sources file.
#[derive(Debug)]
pub struct Sources {
    pub tiers: BTreeMap<String, Tier>,
    entries: Vec<Entry>,
    exceptions: Vec<Entry>,
}

/// A problem in the sources file itself. Each names what to fix.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SourcesError {
    Json(String),
    Schema { found: u64 },
    NoTiers,
    UnknownTier { pattern: String, tier: String, known: Vec<String> },
    BadPattern(String),
    Duplicate { pattern: String },
    EmptyReason { pattern: String },
    BadDate { pattern: String, value: String },
}

impl fmt::Display for SourcesError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SourcesError::Json(e) => write!(f, "not valid sources JSON: {e}"),
            SourcesError::Schema { found } => write!(
                f,
                "schema {found} is not supported (this tool reads schema {SUPPORTED_SCHEMA}); update the tool or the file"
            ),
            SourcesError::NoTiers => write!(f, "no tiers are defined under `tiers`"),
            SourcesError::UnknownTier { pattern, tier, known } => write!(
                f,
                "`{pattern}` uses tier `{tier}`, which is not defined; use one of: {}",
                known.join(", ")
            ),
            SourcesError::BadPattern(e) => write!(f, "{e}"),
            SourcesError::Duplicate { pattern } => {
                write!(f, "`{pattern}` is listed more than once; keep one entry")
            }
            SourcesError::EmptyReason { pattern } => {
                write!(f, "exception `{pattern}` has an empty `reason`; say why it is allowed")
            }
            SourcesError::BadDate { pattern, value } => write!(
                f,
                "exception `{pattern}` has review_by `{value}`, which is not a YYYY-MM-DD date"
            ),
        }
    }
}

impl Sources {
    /// Parses and validates the file. Returns every problem found, not just
    /// the first, so one run shows everything to fix.
    pub fn parse(text: &str) -> Result<Sources, Vec<SourcesError>> {
        let raw: RawFile =
            serde_json::from_str(text).map_err(|e| vec![SourcesError::Json(e.to_string())])?;
        if raw.schema != SUPPORTED_SCHEMA {
            return Err(vec![SourcesError::Schema { found: raw.schema }]);
        }
        let mut errors = Vec::new();
        if raw.tiers.is_empty() {
            errors.push(SourcesError::NoTiers);
        }
        let known: Vec<String> = raw.tiers.keys().cloned().collect();
        let mut seen = std::collections::BTreeSet::new();

        let check_common = |pattern: &str, tier: &str, errors: &mut Vec<SourcesError>| {
            let parsed = match Pattern::parse(pattern) {
                Ok(p) => Some(p),
                Err(e) => {
                    errors.push(SourcesError::BadPattern(e.to_string()));
                    None
                }
            };
            if !raw.tiers.contains_key(tier) {
                errors.push(SourcesError::UnknownTier {
                    pattern: pattern.to_string(),
                    tier: tier.to_string(),
                    known: known.clone(),
                });
            }
            parsed
        };

        let mut entries = Vec::new();
        for e in &raw.sources {
            if !seen.insert(e.pattern.clone()) {
                errors.push(SourcesError::Duplicate { pattern: e.pattern.clone() });
            }
            if let Some(pattern) = check_common(&e.pattern, &e.tier, &mut errors) {
                entries.push(Entry { pattern, tier: e.tier.clone(), exception: None });
            }
        }

        let mut exceptions = Vec::new();
        let mut seen_exc = std::collections::BTreeSet::new();
        for x in &raw.exceptions {
            if !seen_exc.insert(x.pattern.clone()) {
                errors.push(SourcesError::Duplicate { pattern: x.pattern.clone() });
            }
            let pattern = check_common(&x.pattern, &x.tier, &mut errors);
            if x.reason.trim().is_empty() {
                errors.push(SourcesError::EmptyReason { pattern: x.pattern.clone() });
            }
            let date = Date::parse(&x.review_by);
            if date.is_none() {
                errors.push(SourcesError::BadDate {
                    pattern: x.pattern.clone(),
                    value: x.review_by.clone(),
                });
            }
            if let (Some(pattern), Some(review_by)) = (pattern, date) {
                exceptions.push(Entry {
                    pattern,
                    tier: x.tier.clone(),
                    exception: Some(ExceptionInfo { reason: x.reason.clone(), review_by }),
                });
            }
        }

        if errors.is_empty() {
            Ok(Sources { tiers: raw.tiers, entries, exceptions })
        } else {
            Err(errors)
        }
    }

    /// The entry that decides `key`'s tier. An exception that matches wins
    /// over any source entry; within each list the most specific match wins.
    pub fn resolve(&self, key: &str) -> Option<&Entry> {
        let key = key.to_lowercase();
        best_match(&self.exceptions, &key).or_else(|| best_match(&self.entries, &key))
    }

    pub fn exceptions(&self) -> &[Entry] {
        &self.exceptions
    }
}

fn best_match<'a>(list: &'a [Entry], key: &str) -> Option<&'a Entry> {
    list.iter()
        .filter(|e| e.pattern.matches(key))
        .min_by(|a, b| a.pattern.specificity_cmp(&b.pattern))
}

#[cfg(test)]
mod tests {
    use super::*;

    const TIERS: &str = r#""tiers": {
        "core": {"cooldown_days": 3, "automerge": true, "description": "c"},
        "established": {"cooldown_days": 7, "automerge": true, "description": "e"},
        "sensitive": {"cooldown_days": 7, "automerge": false, "description": "s"}
    }"#;

    fn file(sources: &str, exceptions: &str) -> String {
        format!(r#"{{"schema": 1, {TIERS}, "sources": [{sources}], "exceptions": [{exceptions}]}}"#)
    }

    #[test]
    fn most_specific_entry_wins() {
        let s = Sources::parse(&file(
            r#"{"match": "github:nix-community/*", "tier": "established"},
               {"match": "github:nix-community/lanzaboote", "tier": "sensitive"}"#,
            "",
        ))
        .unwrap();
        assert_eq!(s.resolve("github:nix-community/disko").unwrap().tier, "established");
        assert_eq!(s.resolve("github:nix-community/lanzaboote").unwrap().tier, "sensitive");
        assert_eq!(s.resolve("GitHub:Nix-Community/Lanzaboote").unwrap().tier, "sensitive");
        assert!(s.resolve("github:someone/else").is_none());
    }

    #[test]
    fn exception_beats_a_more_specific_source() {
        let s = Sources::parse(&file(
            r#"{"match": "github:x/y", "tier": "sensitive"}"#,
            r#"{"match": "github:x/*", "tier": "core", "reason": "trial", "review_by": "2027-01-01"}"#,
        ))
        .unwrap();
        let e = s.resolve("github:x/y").unwrap();
        assert_eq!(e.tier, "core");
        assert_eq!(e.exception.as_ref().unwrap().review_by.to_string(), "2027-01-01");
    }

    #[test]
    fn reports_every_problem_at_once() {
        let errs = Sources::parse(&file(
            r#"{"match": "github:a/b", "tier": "nope"},
               {"match": "github:a/b", "tier": "core"},
               {"match": "Bad", "tier": "core"}"#,
            r#"{"match": "github:c/d", "tier": "core", "reason": " ", "review_by": "2027-02-30"}"#,
        ))
        .unwrap_err();
        assert_eq!(errs.len(), 5, "{errs:#?}");
        assert!(errs.contains(&SourcesError::UnknownTier {
            pattern: "github:a/b".into(),
            tier: "nope".into(),
            known: vec!["core".into(), "established".into(), "sensitive".into()],
        }));
        assert!(errs.contains(&SourcesError::Duplicate { pattern: "github:a/b".into() }));
        assert!(errs.contains(&SourcesError::EmptyReason { pattern: "github:c/d".into() }));
        assert!(errs.contains(&SourcesError::BadDate {
            pattern: "github:c/d".into(),
            value: "2027-02-30".into()
        }));
        assert!(errs.iter().any(|e| matches!(e, SourcesError::BadPattern(_))));
    }

    #[test]
    fn duplicate_exception_is_an_error() {
        let x = r#"{"match": "github:c/d", "tier": "core", "reason": "r", "review_by": "2027-01-01"}"#;
        let errs = Sources::parse(&file("", &format!("{x},{x}"))).unwrap_err();
        assert_eq!(errs, vec![SourcesError::Duplicate { pattern: "github:c/d".into() }]);
    }

    #[test]
    fn rejects_unknown_schema_and_fields() {
        let errs = Sources::parse(r#"{"schema": 2, "tiers": {}, "sources": []}"#).unwrap_err();
        assert_eq!(errs, vec![SourcesError::Schema { found: 2 }]);
        let errs = Sources::parse(&file(r#"{"match": "github:a/b", "tier": "core", "teir": "x"}"#, ""))
            .unwrap_err();
        assert!(matches!(&errs[0], SourcesError::Json(m) if m.contains("teir")));
    }

    #[test]
    fn no_tiers_is_an_error() {
        let errs = Sources::parse(r#"{"schema": 1, "tiers": {}, "sources": []}"#).unwrap_err();
        assert_eq!(errs, vec![SourcesError::NoTiers]);
    }

    #[test]
    fn messages_say_what_to_do() {
        let e = SourcesError::UnknownTier {
            pattern: "github:a/b".into(),
            tier: "nope".into(),
            known: vec!["core".into(), "own".into()],
        };
        assert_eq!(e.to_string(), "`github:a/b` uses tier `nope`, which is not defined; use one of: core, own");
        assert!(SourcesError::Schema { found: 9 }.to_string().contains("reads schema 1"));
    }
}
