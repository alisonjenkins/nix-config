use std::collections::HashSet;

use serde::{Deserialize, Serialize};
use thiserror::Error;

/// Facts found in `text` and facts asked for, matched as case-insensitive substrings.
pub fn fact_coverage(text: &str, facts: &[String]) -> (usize, usize) {
    let haystack = text.to_lowercase();
    let found = facts
        .iter()
        .filter(|fact| haystack.contains(&fact.to_lowercase()))
        .count();
    (found, facts.len())
}

#[derive(Debug, Clone, PartialEq)]
pub struct CavememHit {
    pub id: u64,
    pub score: f64,
    pub session: String,
    pub snippet: String,
}

/// Parses `cavemem search` stdout: `id<TAB>score<TAB>session<TAB>snippet` per
/// line. Notices such as `semantic disabled: ...` and malformed lines are skipped.
pub fn parse_cavemem_search(stdout: &str) -> Vec<CavememHit> {
    stdout
        .lines()
        .filter_map(|line| {
            let mut fields = line.splitn(4, '\t');
            let id = fields.next()?.parse().ok()?;
            let score = fields.next()?.parse().ok()?;
            let session = fields.next()?.to_owned();
            let snippet = fields.next()?.to_owned();
            Some(CavememHit {
                id,
                score,
                session,
                snippet,
            })
        })
        .collect()
}

/// Hits recorded before `cutoff_id`, so today's own session cannot answer its test.
pub fn before_cutoff(hits: Vec<CavememHit>, cutoff_id: u64) -> Vec<CavememHit> {
    hits.into_iter().filter(|hit| hit.id < cutoff_id).collect()
}

#[derive(Debug, Error)]
pub enum ClaudeError {
    #[error("claude output is not the expected JSON: {0}")]
    Parse(String),
    #[error("claude reported an error: {0}")]
    Reported(String),
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ClaudeCall {
    pub text: String,
    /// Fresh, cache-read and cache-written input tokens together.
    pub input_tokens: u64,
    pub output_tokens: u64,
    pub api_ms: f64,
    pub cost_usd: f64,
}

/// Parses `claude -p --output-format json` output.
pub fn parse_claude_json(stdout: &str) -> Result<ClaudeCall, ClaudeError> {
    let value: serde_json::Value =
        serde_json::from_str(stdout).map_err(|e| ClaudeError::Parse(e.to_string()))?;
    let text = value
        .get("result")
        .and_then(serde_json::Value::as_str)
        .ok_or_else(|| ClaudeError::Parse("no `result` string".to_owned()))?
        .to_owned();
    if value
        .get("is_error")
        .and_then(serde_json::Value::as_bool)
        .unwrap_or(false)
    {
        return Err(ClaudeError::Reported(text));
    }
    let usage = |key: &str| {
        value
            .get("usage")
            .and_then(|u| u.get(key))
            .and_then(serde_json::Value::as_u64)
            .unwrap_or(0)
    };
    let number = |key: &str| {
        value
            .get(key)
            .and_then(serde_json::Value::as_f64)
            .unwrap_or(0.0)
    };
    Ok(ClaudeCall {
        text,
        input_tokens: usage("input_tokens")
            .saturating_add(usage("cache_creation_input_tokens"))
            .saturating_add(usage("cache_read_input_tokens")),
        output_tokens: usage("output_tokens"),
        api_ms: number("duration_api_ms"),
        cost_usd: number("total_cost_usd"),
    })
}

/// Memory file names from `known` that `text` mentions, in order, once each.
pub fn extract_files(text: &str, known: &HashSet<String>, max: usize) -> Vec<String> {
    let mut found: Vec<String> = Vec::new();
    let tokens = text.split(|c: char| !(c.is_alphanumeric() || matches!(c, '_' | '.' | '-')));
    for token in tokens {
        let name = token.trim_end_matches('.');
        if known.contains(name) && !found.iter().any(|f| f == name) {
            found.push(name.to_owned());
            if found.len() >= max {
                break;
            }
        }
    }
    found
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]
mod tests {
    use super::*;

    fn facts(items: &[&str]) -> Vec<String> {
        items.iter().map(|s| (*s).to_owned()).collect()
    }

    #[test]
    fn coverage_counts_case_insensitive_substrings() {
        let text = "Add ::1 to the AllowListSetting, then restart exampled";
        assert_eq!(
            fact_coverage(text, &facts(&["::1", "allowlistsetting", "ThreadPool"])),
            (2, 3)
        );
    }

    #[test]
    fn coverage_of_no_facts_is_zero_of_zero() {
        assert_eq!(fact_coverage("anything", &[]), (0, 0));
    }

    #[test]
    fn parses_tab_separated_hits_and_skips_notices() {
        let out = "semantic disabled: Local embedding provider requires x\n\
                   36457\t38.169\tad80d8f1-aaaa\t…auth-bypass [whitelist]. Must cover BOTH…\n\
                   not a hit line\n\
                   36460\t12.5\tbeef\tsecond\twith a tab\n";
        let hits = parse_cavemem_search(out);
        assert_eq!(hits.len(), 2);
        assert_eq!(hits[0].id, 36457);
        assert!((hits[0].score - 38.169).abs() < 1e-9);
        assert_eq!(hits[0].session, "ad80d8f1-aaaa");
        assert!(hits[0].snippet.contains("auth-bypass"));
        assert_eq!(hits[1].snippet, "second\twith a tab");
    }

    #[test]
    fn empty_output_has_no_hits() {
        assert!(parse_cavemem_search("").is_empty());
    }

    #[test]
    fn cutoff_drops_hits_at_or_after_the_boundary_keeping_order() {
        let hit = |id| CavememHit {
            id,
            score: 1.0,
            session: String::new(),
            snippet: String::new(),
        };
        let kept = before_cutoff(vec![hit(10), hit(500), hit(20), hit(499)], 500);
        assert_eq!(kept.iter().map(|h| h.id).collect::<Vec<_>>(), [10, 20, 499]);
    }

    #[test]
    fn claude_json_sums_all_input_token_kinds() {
        let json = r#"{"is_error":false,"result":"ok","duration_api_ms":1472,
            "total_cost_usd":0.0114,
            "usage":{"input_tokens":2,"cache_creation_input_tokens":2839,
                     "cache_read_input_tokens":100,"output_tokens":4}}"#;
        let call = parse_claude_json(json).unwrap();
        assert_eq!(call.text, "ok");
        assert_eq!(call.input_tokens, 2941);
        assert_eq!(call.output_tokens, 4);
        assert!((call.api_ms - 1472.0).abs() < 1e-9);
        assert!((call.cost_usd - 0.0114).abs() < 1e-9);
    }

    #[test]
    fn claude_reported_errors_are_errors_with_the_message() {
        let json = r#"{"is_error":true,"result":"Not logged in","usage":{}}"#;
        let err = parse_claude_json(json).unwrap_err();
        assert!(err.to_string().contains("Not logged in"));
    }

    #[test]
    fn claude_garbage_is_a_parse_error() {
        assert!(matches!(
            parse_claude_json("not json"),
            Err(ClaudeError::Parse(_))
        ));
    }

    fn known() -> HashSet<String> {
        ["a-b.md", "c.md", "d_e.md"]
            .map(str::to_owned)
            .into_iter()
            .collect()
    }

    #[test]
    fn extract_files_finds_known_names_in_order_once() {
        let text = "I would read:\n- c.md\n- `a-b.md`\nand c.md again, plus x.md";
        assert_eq!(extract_files(text, &known(), 5), ["c.md", "a-b.md"]);
    }

    #[test]
    fn extract_files_honours_the_limit_and_none() {
        assert_eq!(
            extract_files("a-b.md c.md d_e.md", &known(), 2),
            ["a-b.md", "c.md"]
        );
        assert!(extract_files("NONE", &known(), 3).is_empty());
    }

    #[test]
    fn extract_files_matches_full_paths() {
        let text = "/home/u/memory/d_e.md (0.81): something";
        assert_eq!(extract_files(text, &known(), 3), ["d_e.md"]);
    }
}
