use std::fmt::Write;
use std::path::Path;

use crate::corpus::Chunk;

/// Acknowledgements like "yes" or "continue" carry no retrieval signal.
pub const MIN_PROMPT_CHARS: usize = 12;
/// A long paste would only dilute the query vector and slow the embed call.
pub const MAX_PROMPT_CHARS: usize = 2000;

#[derive(Debug, Clone, PartialEq)]
pub struct Hit {
    pub id: String,
    pub description: String,
    pub score: f64,
}

/// The user's prompt from a UserPromptSubmit hook payload, or `None` when it
/// is absent, unparseable, or too short to be worth a lookup.
pub fn prompt_from_hook_input(stdin_json: &str) -> Option<String> {
    let payload: serde_json::Value = serde_json::from_str(stdin_json).ok()?;
    let prompt = payload.get("prompt")?.as_str()?.trim();
    if prompt.chars().count() < MIN_PROMPT_CHARS {
        return None;
    }
    Some(prompt.chars().take(MAX_PROMPT_CHARS).collect())
}

/// Best-first scored ids, filtered to `score >= min_score`, at most `top`.
pub fn select(scored: &[(String, f64)], min_score: f64, top: usize) -> Vec<(String, f64)> {
    scored
        .iter()
        .filter(|(_, score)| *score >= min_score)
        .take(top)
        .cloned()
        .collect()
}

/// A memory's description is the first line of its chunk text.
pub fn hit(chunk: &Chunk, score: f64) -> Hit {
    Hit {
        id: chunk.id.clone(),
        description: chunk.text.lines().next().unwrap_or_default().to_owned(),
        score,
    }
}

/// The text injected into the session; empty when there is nothing to inject.
pub fn render_context(memory_dir: &Path, hits: &[Hit]) -> String {
    if hits.is_empty() {
        return String::new();
    }
    let mut out = String::from(
        "Possibly relevant memories (semantic match, best first). Read a file if it applies:\n",
    );
    for hit in hits {
        let path = memory_dir.join(&hit.id);
        let _ = writeln!(
            out,
            "- {} ({:.2}): {}",
            path.display(),
            hit.score,
            hit.description
        );
    }
    out
}

/// UserPromptSubmit hook stdout; `None` when there is no context to add.
pub fn hook_output(context: &str) -> Option<String> {
    if context.is_empty() {
        return None;
    }
    Some(
        serde_json::json!({
            "hookSpecificOutput": {
                "hookEventName": "UserPromptSubmit",
                "additionalContext": context,
            }
        })
        .to_string(),
    )
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]
mod tests {
    use super::*;

    fn scored(items: &[(&str, f64)]) -> Vec<(String, f64)> {
        items.iter().map(|(id, s)| ((*id).to_owned(), *s)).collect()
    }

    #[test]
    fn prompt_is_read_from_the_hook_payload() {
        let json = r#"{"session_id":"x","prompt":"why does examplarr fail to log in"}"#;
        assert_eq!(
            prompt_from_hook_input(json).as_deref(),
            Some("why does examplarr fail to log in")
        );
    }

    #[test]
    fn missing_or_malformed_payload_yields_no_prompt() {
        assert_eq!(prompt_from_hook_input(r#"{"cwd":"/"}"#), None);
        assert_eq!(prompt_from_hook_input("not json"), None);
        assert_eq!(prompt_from_hook_input(r#"{"prompt":42}"#), None);
    }

    #[test]
    fn short_prompts_are_skipped() {
        assert_eq!(prompt_from_hook_input(r#"{"prompt":"yes"}"#), None);
        assert_eq!(
            prompt_from_hook_input(r#"{"prompt":"   continue   "}"#),
            None
        );
    }

    #[test]
    fn long_prompts_are_truncated() {
        let long = "x".repeat(MAX_PROMPT_CHARS * 2);
        let json = serde_json::json!({ "prompt": long }).to_string();
        let prompt = prompt_from_hook_input(&json).unwrap();
        assert_eq!(prompt.chars().count(), MAX_PROMPT_CHARS);
    }

    #[test]
    fn select_applies_threshold_then_limit_keeping_order() {
        let all = scored(&[("a", 0.9), ("b", 0.8), ("c", 0.7), ("d", 0.2)]);
        assert_eq!(select(&all, 0.5, 2), scored(&[("a", 0.9), ("b", 0.8)]));
        assert_eq!(
            select(&all, 0.5, 10),
            scored(&[("a", 0.9), ("b", 0.8), ("c", 0.7)])
        );
    }

    #[test]
    fn select_returns_nothing_when_no_score_clears_the_threshold() {
        assert!(select(&scored(&[("a", 0.1)]), 0.5, 3).is_empty());
    }

    #[test]
    fn hit_takes_the_first_text_line_as_description() {
        let chunk = Chunk {
            id: "m.md".to_owned(),
            title: "m".to_owned(),
            text: "one-line description\nbody line".to_owned(),
        };
        assert_eq!(
            hit(&chunk, 0.5),
            Hit {
                id: "m.md".to_owned(),
                description: "one-line description".to_owned(),
                score: 0.5
            }
        );
    }

    #[test]
    fn context_lists_path_score_and_description() {
        let hits = [Hit {
            id: "feedback_sudo.md".to_owned(),
            description: "Agent cannot run sudo".to_owned(),
            score: 0.714,
        }];
        let text = render_context(Path::new("/mem"), &hits);
        assert!(text.contains("/mem/feedback_sudo.md"));
        assert!(text.contains("0.71"));
        assert!(text.contains("Agent cannot run sudo"));
    }

    #[test]
    fn context_is_empty_without_hits() {
        assert_eq!(render_context(Path::new("/mem"), &[]), "");
    }

    #[test]
    fn hook_output_wraps_context_for_user_prompt_submit() {
        let out = hook_output("remember this").unwrap();
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v["hookSpecificOutput"]["hookEventName"], "UserPromptSubmit");
        assert_eq!(
            v["hookSpecificOutput"]["additionalContext"],
            "remember this"
        );
    }

    #[test]
    fn hook_output_is_none_for_empty_context() {
        assert_eq!(hook_output(""), None);
    }
}
