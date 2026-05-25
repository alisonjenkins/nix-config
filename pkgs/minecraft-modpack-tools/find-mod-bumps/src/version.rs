// Maven-style version-range parsing and version comparison. Mirrors the
// Python implementation so behaviour stays bug-for-bug compatible with the
// old script while we transition.
use regex::Regex;
use std::cmp::Ordering;
use std::sync::OnceLock;

fn re_strip_forge() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| Regex::new(r"(?i)^(?:Neo)?Forge-").unwrap())
}
fn re_strip_mc() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| Regex::new(r"^1\.21(?:\.\d+)?-").unwrap())
}
fn re_head_digits() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| Regex::new(r"^(\d+(?:\.\d+)*)").unwrap())
}
fn re_range() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| {
        Regex::new(r"^\s*([\[\(])\s*([^,\]\)]*)\s*,\s*([^,\]\)]*)\s*([\]\)])\s*$").unwrap()
    })
}

/// Convert a free-form version string into a tuple suitable for ordinal
/// comparison. Strips common prefixes (`v`, `Forge-`, `NeoForge-`,
/// `1.21.1-`) and reads the leading dotted number, dropping any
/// pre-release / build suffix.
pub fn version_key(v: &str) -> Vec<u32> {
    let v = v.trim().trim_start_matches('v');
    let v = re_strip_forge().replace(v, "").into_owned();
    let v = re_strip_mc().replace(&v, "").into_owned();
    match re_head_digits().captures(&v) {
        Some(c) => c[1]
            .split('.')
            .map(|p| p.parse::<u32>().unwrap_or(0))
            .collect(),
        None => vec![0],
    }
}

pub fn cmp_versions(a: &[u32], b: &[u32]) -> Ordering {
    for i in 0..a.len().max(b.len()) {
        let av = a.get(i).copied().unwrap_or(0);
        let bv = b.get(i).copied().unwrap_or(0);
        match av.cmp(&bv) {
            Ordering::Equal => continue,
            o => return o,
        }
    }
    Ordering::Equal
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Range {
    pub lo_inc: bool,
    pub lo: String,
    pub hi: String,
    pub hi_inc: bool,
}

/// Parse a Maven-style range like `[1.0,2.0)`. `None` means "no
/// constraint" (empty/`*`). A bare version like `1.0` maps to `[1.0,)`.
pub fn parse_version_range(spec: &str) -> Option<Range> {
    if spec.is_empty() || spec == "*" {
        return None;
    }
    if let Some(c) = re_range().captures(spec) {
        return Some(Range {
            lo_inc: &c[1] == "[",
            lo: c[2].trim().to_string(),
            hi: c[3].trim().to_string(),
            hi_inc: &c[4] == "]",
        });
    }
    Some(Range {
        lo_inc: true,
        lo: spec.trim().to_string(),
        hi: String::new(),
        hi_inc: false,
    })
}

pub fn in_range(version: &str, spec: &str) -> bool {
    if version.is_empty() {
        return true;
    }
    let r = match parse_version_range(spec) {
        None => return true,
        Some(r) => r,
    };
    let vk = version_key(version);
    if !r.lo.is_empty() {
        let lk = version_key(&r.lo);
        match cmp_versions(&vk, &lk) {
            Ordering::Less => return false,
            Ordering::Equal if !r.lo_inc => return false,
            _ => {}
        }
    }
    if !r.hi.is_empty() {
        let hk = version_key(&r.hi);
        match cmp_versions(&vk, &hk) {
            Ordering::Greater => return false,
            Ordering::Equal if !r.hi_inc => return false,
            _ => {}
        }
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_key_strips_prefixes() {
        assert_eq!(version_key("1.2.3"), vec![1, 2, 3]);
        assert_eq!(version_key("v1.2.3"), vec![1, 2, 3]);
        assert_eq!(version_key("NeoForge-21.1.74"), vec![21, 1, 74]);
        assert_eq!(version_key("forge-21.1.74"), vec![21, 1, 74]);
        assert_eq!(version_key("1.21.1-1.2.3"), vec![1, 2, 3]);
        assert_eq!(version_key("1.21-1.2.3"), vec![1, 2, 3]);
    }

    #[test]
    fn version_key_handles_suffixes() {
        // Drops pre-release / build metadata.
        assert_eq!(version_key("1.2.3-beta"), vec![1, 2, 3]);
        assert_eq!(version_key("1.2.3+meta"), vec![1, 2, 3]);
    }

    #[test]
    fn version_key_handles_garbage() {
        assert_eq!(version_key(""), vec![0]);
        assert_eq!(version_key("abc"), vec![0]);
    }

    #[test]
    fn cmp_versions_pads_with_zero() {
        assert_eq!(cmp_versions(&[1, 2], &[1, 2, 0]), Ordering::Equal);
        assert_eq!(cmp_versions(&[1, 2], &[1, 2, 1]), Ordering::Less);
        assert_eq!(cmp_versions(&[1, 3], &[1, 2, 9]), Ordering::Greater);
    }

    #[test]
    fn parse_open_and_closed_ranges() {
        let r = parse_version_range("[1.0,2.0)").unwrap();
        assert!(r.lo_inc && !r.hi_inc);
        assert_eq!(r.lo, "1.0");
        assert_eq!(r.hi, "2.0");

        let r = parse_version_range("(1.0,2.0]").unwrap();
        assert!(!r.lo_inc && r.hi_inc);

        // Bare-version => [v,)
        let r = parse_version_range("1.5").unwrap();
        assert_eq!(r.lo, "1.5");
        assert!(r.hi.is_empty());
        assert!(r.lo_inc);

        // Unbounded hi
        let r = parse_version_range("[1.0,)").unwrap();
        assert_eq!(r.lo, "1.0");
        assert!(r.hi.is_empty());
    }

    #[test]
    fn parse_range_wildcards() {
        assert!(parse_version_range("").is_none());
        assert!(parse_version_range("*").is_none());
    }

    #[test]
    fn in_range_inclusive_exclusive() {
        // [1.0,2.0)
        assert!(in_range("1.0", "[1.0,2.0)"));
        assert!(in_range("1.5", "[1.0,2.0)"));
        assert!(!in_range("2.0", "[1.0,2.0)"));
        assert!(!in_range("0.9", "[1.0,2.0)"));
        // (1.0,2.0]
        assert!(!in_range("1.0", "(1.0,2.0]"));
        assert!(in_range("2.0", "(1.0,2.0]"));
        // [1.0,) — open-ended upper
        assert!(in_range("99.0", "[1.0,)"));
        assert!(!in_range("0.5", "[1.0,)"));
        // empty version => true (treat as no constraint)
        assert!(in_range("", "[1.0,2.0)"));
        // empty/wildcard spec
        assert!(in_range("1.0", ""));
        assert!(in_range("1.0", "*"));
    }

    #[test]
    fn in_range_real_world() {
        // From the user's known-good bumps. Sample mods.toml ranges.
        assert!(in_range("6.0.10", "[6.0.0,7.0.0)"));
        assert!(!in_range("7.0.0", "[6.0.0,7.0.0)"));
        assert!(in_range("21.1.74", "[21.1.0,)"));
    }
}
