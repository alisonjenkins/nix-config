//! Source keys and the patterns in `pins/sources.json` that match them.
//!
//! A key is `<kind>:<path>`, lowercase, for example `github:nixos/nixpkgs`
//! or `action:actions/checkout`. A pattern has the same shape, and a `*`
//! segment matches exactly one non-empty path segment, never more: a key
//! matches only a pattern with the same number of segments.

use std::cmp::Ordering;
use std::fmt;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Pattern {
    raw: String,
    kind: String,
    segments: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PatternError {
    pub pattern: String,
    pub reason: &'static str,
}

impl fmt::Display for PatternError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "invalid match pattern `{}`: {}", self.pattern, self.reason)
    }
}

impl std::error::Error for PatternError {}

/// Splits `kind:path` into the kind and the path. URLs keep their scheme in
/// the path (`tarball:https://...`).
fn split_key(key: &str) -> Option<(&str, &str)> {
    let (kind, path) = key.split_once(':')?;
    if kind.is_empty() || path.is_empty() {
        return None;
    }
    Some((kind, path))
}

impl Pattern {
    pub fn parse(raw: &str) -> Result<Self, PatternError> {
        let err = |reason| PatternError { pattern: raw.to_string(), reason };
        if raw != raw.to_lowercase() {
            return Err(err("must be lowercase"));
        }
        let (kind, path) = split_key(raw).ok_or_else(|| err("expected `<kind>:<path>`"))?;
        let segments: Vec<String> = path.split('/').map(str::to_string).collect();
        if segments.iter().any(|s| s.contains('*') && s != "*") {
            return Err(err("`*` must be a whole path segment"));
        }
        if segments.iter().all(|s| s == "*" || s.is_empty()) {
            return Err(err("needs at least one literal path segment"));
        }
        Ok(Pattern { raw: raw.to_string(), kind: kind.to_string(), segments })
    }

    pub fn as_str(&self) -> &str {
        &self.raw
    }

    pub fn wildcards(&self) -> usize {
        self.segments.iter().filter(|s| *s == "*").count()
    }

    /// True when `key` (already lowercase) matches this pattern.
    pub fn matches(&self, key: &str) -> bool {
        let Some((kind, path)) = split_key(key) else { return false };
        if kind != self.kind {
            return false;
        }
        let parts: Vec<&str> = path.split('/').collect();
        parts.len() == self.segments.len()
            && self.segments.iter().zip(&parts).all(|(seg, part)| {
                if seg == "*" {
                    !part.is_empty()
                } else {
                    seg == part
                }
            })
    }

    /// Orders patterns so the most specific comes first: fewer wildcards,
    /// then more segments, then longer text.
    pub fn specificity_cmp(&self, other: &Pattern) -> Ordering {
        self.wildcards()
            .cmp(&other.wildcards())
            .then_with(|| other.segments.len().cmp(&self.segments.len()))
            .then_with(|| other.raw.len().cmp(&self.raw.len()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn p(s: &str) -> Pattern {
        Pattern::parse(s).unwrap()
    }

    #[test]
    fn exact_match() {
        assert!(p("github:nixos/nixpkgs").matches("github:nixos/nixpkgs"));
        assert!(!p("github:nixos/nixpkgs").matches("github:nixos/nixpkgs-foo"));
        assert!(!p("github:nixos/nixpkgs").matches("github:nixos"));
        assert!(!p("github:nixos/nixpkgs").matches("github:nixos/nixpkgs/extra"));
    }

    #[test]
    fn kind_must_match() {
        assert!(!p("github:actions/checkout").matches("action:actions/checkout"));
    }

    #[test]
    fn wildcard_repo() {
        assert!(p("github:nix-community/*").matches("github:nix-community/disko"));
        assert!(!p("github:nix-community/*").matches("github:nix-community/"));
        assert!(!p("github:nix-community/*").matches("github:nixos/disko"));
    }

    #[test]
    fn wildcard_never_spans_segments() {
        let pat = p("tarball:https://channels.nixos.org/*/nixexprs.tar.xz");
        assert!(pat.matches("tarball:https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz"));
        assert!(!pat.matches("tarball:https://channels.nixos.org/a/b/nixexprs.tar.xz"));
        assert!(!pat.matches("tarball:https://evil.example/channels.nixos.org/x"));
        // A GitLab subgroup is a deeper path, not a match for the group's `*`.
        assert!(!p("gitlab:gitlab.gnome.org/gnome/*").matches("gitlab:gitlab.gnome.org/gnome/sub/thing"));
        assert!(!p("github:o/*").matches("github:o"));
    }

    #[test]
    fn middle_wildcard_is_one_segment() {
        let pat = p("gitlab:*/gnome/gnome-shell");
        assert!(pat.matches("gitlab:gitlab.gnome.org/gnome/gnome-shell"));
        assert!(!pat.matches("gitlab:a/b/gnome/gnome-shell"));
    }

    #[test]
    fn rejects_bad_patterns() {
        for bad in ["GitHub:x/y", "nokind", ":x", "github:", "github:*", "github:*/*", "github:foo*/bar"] {
            assert!(Pattern::parse(bad).is_err(), "{bad} should be rejected");
        }
    }

    #[test]
    fn error_names_the_pattern_and_reason() {
        let e = Pattern::parse("github:Foo/bar").unwrap_err();
        assert_eq!(e.to_string(), "invalid match pattern `github:Foo/bar`: must be lowercase");
    }

    #[test]
    fn specificity_prefers_fewer_wildcards() {
        let exact = p("github:nix-community/lanzaboote");
        let owner = p("github:nix-community/*");
        assert_eq!(exact.specificity_cmp(&owner), Ordering::Less);
        assert_eq!(owner.specificity_cmp(&exact), Ordering::Greater);
        // Fewer wildcards wins even against a longer pattern.
        let long_wild = p("github:a-very-long-owner-name/*");
        let short_exact = p("github:a/b");
        assert_eq!(short_exact.specificity_cmp(&long_wild), Ordering::Less);
        assert_eq!(long_wild.wildcards(), 1);
        assert_eq!(p("gitlab:*/x/*").wildcards(), 2);
        assert_eq!(short_exact.wildcards(), 0);
    }

    #[test]
    fn specificity_prefers_more_segments_then_length() {
        let deep = p("gitlab:gitlab.gnome.org/gnome/*");
        let shallow = p("gitlab:gitlab.gnome.org/*");
        assert_eq!(deep.specificity_cmp(&shallow), Ordering::Less);
        let long = p("github:abcdef/x");
        let short = p("github:abc/x");
        assert_eq!(long.specificity_cmp(&short), Ordering::Less);
        assert_eq!(long.specificity_cmp(&long.clone()), Ordering::Equal);
    }
}
