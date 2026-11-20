//! `update-policy check`: every source of code has a tier, and every Action
//! outside the `own` tier is pinned to a commit.

use crate::date::Date;
use crate::lock::LockedInput;
use crate::sources::Sources;
use crate::workflows::ActionUse;
use std::fmt;

pub const OWN_TIER: &str = "own";
const POLICY: &str = "docs/update-policy.md";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Severity {
    Error,
    Warning,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Finding {
    pub severity: Severity,
    pub message: String,
}

impl fmt::Display for Finding {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let label = match self.severity {
            Severity::Error => "error",
            Severity::Warning => "warning",
        };
        write!(f, "{label}: {}", self.message)
    }
}

fn error(message: String) -> Finding {
    Finding { severity: Severity::Error, message }
}

fn warning(message: String) -> Finding {
    Finding { severity: Severity::Warning, message }
}

/// Suggests the narrowest pattern for a key: `kind:owner/repo` style keys
/// keep their first two path segments.
pub fn suggested_pattern(key: &str) -> String {
    match key.split_once(':') {
        Some((kind @ ("github" | "action"), path)) => {
            let mut segs = path.split('/');
            match (segs.next(), segs.next()) {
                (Some(o), Some(r)) => format!("{kind}:{o}/{r}"),
                _ => key.to_string(),
            }
        }
        _ => key.to_string(),
    }
}

pub fn check(sources: &Sources, inputs: &[LockedInput], actions: &[ActionUse], today: Date) -> Vec<Finding> {
    let mut out = Vec::new();

    for input in inputs {
        let Some(key) = &input.key else { continue };
        if sources.resolve(key).is_none() {
            out.push(error(format!(
                "flake input `{}` ({}) has no trust tier. Add {{\"match\": \"{}\", \"tier\": \"...\"}} to pins/sources.json; tiers are described in {POLICY}",
                input.via,
                input.original,
                suggested_pattern(key),
            )));
        }
    }

    for a in actions {
        let key = a.key();
        match sources.resolve(&key) {
            None => out.push(error(format!(
                "{}:{}: action `{}` has no trust tier. Add {{\"match\": \"{}\", \"tier\": \"...\"}} to pins/sources.json; tiers are described in {POLICY}",
                a.file, a.line, a.repo, suggested_pattern(&key),
            ))),
            Some(entry) if entry.tier != OWN_TIER && !a.is_pinned() => out.push(error(format!(
                "{}:{}: action `{}` is referenced as `@{}`, which can move. Pin it to a full commit SHA (`{}@<40-hex sha> # {}`); only the `own` tier may use a branch or tag",
                a.file,
                a.line,
                a.repo,
                if a.reference.is_empty() { "<nothing>" } else { &a.reference },
                a.repo,
                if a.reference.is_empty() { "<tag>" } else { &a.reference },
            ))),
            Some(_) => {}
        }
    }

    for x in sources.exceptions() {
        let info = x.exception.as_ref().expect("exceptions carry their info");
        let left = today.days_until(info.review_by);
        if left < 0 {
            out.push(warning(format!(
                "exception `{}` (tier `{}`) passed its review date {} ({} days ago): re-check it and move `review_by` forward, or remove it. Reason given: {}",
                x.pattern.as_str(), x.tier, info.review_by, -left, info.reason,
            )));
        }
    }

    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sources() -> Sources {
        Sources::parse(
            r#"{"schema": 1,
                "tiers": {
                  "own": {"cooldown_days": 0, "automerge": true, "description": "o"},
                  "core": {"cooldown_days": 3, "automerge": true, "description": "c"}
                },
                "sources": [
                  {"match": "github:nixos/nixpkgs", "tier": "core"},
                  {"match": "github:alisonjenkins/*", "tier": "own"},
                  {"match": "action:actions/*", "tier": "core"},
                  {"match": "action:alisonjenkins/*", "tier": "own"}
                ],
                "exceptions": [
                  {"match": "github:old/thing", "tier": "core", "reason": "trial", "review_by": "2026-11-01"},
                  {"match": "github:new/thing", "tier": "core", "reason": "trial", "review_by": "2026-11-20"}
                ]}"#,
        )
        .unwrap()
    }

    fn input(via: &str, key: Option<&str>) -> LockedInput {
        LockedInput { node: via.into(), via: via.into(), key: key.map(str::to_string), original: "type=github".into() }
    }

    fn action(repo: &str, reference: &str) -> ActionUse {
        ActionUse { file: ".github/workflows/x.yaml".into(), line: 3, repo: repo.into(), reference: reference.into() }
    }

    const SHA: &str = "3d3c42e5aac5ba805825da76410c181273ba90b1";
    fn today() -> Date {
        Date::parse("2026-11-20").unwrap()
    }

    #[test]
    fn clean_repo_has_only_the_expired_exception_warning() {
        let got = check(
            &sources(),
            &[input("nixpkgs", Some("github:nixos/nixpkgs")), input("local", None), input("mine", Some("github:alisonjenkins/x"))],
            &[action("actions/checkout", SHA), action("alisonjenkins/act", "main")],
            today(),
        );
        assert_eq!(got.len(), 1, "{got:#?}");
        assert_eq!(got[0].severity, Severity::Warning);
        assert_eq!(
            got[0].to_string(),
            "warning: exception `github:old/thing` (tier `core`) passed its review date 2026-11-01 (19 days ago): re-check it and move `review_by` forward, or remove it. Reason given: trial"
        );
    }

    #[test]
    fn exception_due_today_is_not_yet_expired() {
        let got = check(&sources(), &[], &[], Date::parse("2026-11-01").unwrap());
        assert!(got.is_empty(), "{got:#?}");
    }

    #[test]
    fn untiered_input_is_an_error_with_a_fix() {
        let got = check(&sources(), &[input("stylix/base16", Some("github:senchopens/base16.nix"))], &[], today());
        let errors: Vec<_> = got.iter().filter(|f| f.severity == Severity::Error).collect();
        assert_eq!(errors.len(), 1);
        assert_eq!(
            errors[0].message,
            "flake input `stylix/base16` (type=github) has no trust tier. Add {\"match\": \"github:senchopens/base16.nix\", \"tier\": \"...\"} to pins/sources.json; tiers are described in docs/update-policy.md"
        );
    }

    #[test]
    fn untiered_and_unpinned_actions() {
        let got = check(
            &sources(),
            &[],
            &[action("fluxcd/flux2", "main"), action("actions/cache", "v4"), action("actions/x", "")],
            today(),
        );
        let errors: Vec<String> = got.iter().filter(|f| f.severity == Severity::Error).map(|f| f.message.clone()).collect();
        assert_eq!(errors.len(), 3, "{errors:#?}");
        assert!(errors[0].starts_with(".github/workflows/x.yaml:3: action `fluxcd/flux2` has no trust tier"));
        assert!(errors[0].contains("\"match\": \"action:fluxcd/flux2\""));
        assert_eq!(
            errors[1],
            ".github/workflows/x.yaml:3: action `actions/cache` is referenced as `@v4`, which can move. Pin it to a full commit SHA (`actions/cache@<40-hex sha> # v4`); only the `own` tier may use a branch or tag"
        );
        assert!(errors[2].contains("referenced as `@<nothing>`"));
        assert!(errors[2].contains("# <tag>"));
    }

    #[test]
    fn suggested_patterns() {
        assert_eq!(suggested_pattern("action:github/codeql-action"), "action:github/codeql-action");
        assert_eq!(suggested_pattern("github:a/b"), "github:a/b");
        assert_eq!(suggested_pattern("action:a/b/sub/path"), "action:a/b");
        assert_eq!(suggested_pattern("github:a/b/c"), "github:a/b");
        assert_eq!(suggested_pattern("github:a"), "github:a");
        assert_eq!(suggested_pattern("tarball:https://x/y"), "tarball:https://x/y");
        assert_eq!(suggested_pattern("gitlab:h/o/r"), "gitlab:h/o/r");
    }

    #[test]
    fn findings_display_with_severity() {
        assert_eq!(error("x".into()).to_string(), "error: x");
        assert_eq!(warning("y".into()).to_string(), "warning: y");
    }
}
