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
    /// The memory's text after its description line.
    pub body: String,
    pub score: f64,
}

/// How much of a match is put in front of the model.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Inject {
    /// Path, score and one-line description of each match; the model reads the file.
    Snippets,
    /// The best match in full, the others as snippets.
    TopBody,
    /// Every match in full.
    Bodies,
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

/// A memory's description is the first line of its chunk text, the rest its body.
pub fn hit(chunk: &Chunk, score: f64) -> Hit {
    let mut lines = chunk.text.splitn(2, '\n');
    let description = lines.next().unwrap_or_default().to_owned();
    let body = lines.next().unwrap_or_default().trim().to_owned();
    Hit {
        id: chunk.id.clone(),
        description,
        body,
        score,
    }
}

/// The text injected into the session as snippets; empty when there is nothing to inject.
pub fn render_context(memory_dir: &Path, hits: &[Hit]) -> String {
    render_context_with(memory_dir, hits, Inject::Snippets, 0)
}

/// The text injected into the session; empty when there is nothing to inject.
/// Bodies are cut at `body_chars` characters.
pub fn render_context_with(
    memory_dir: &Path,
    hits: &[Hit],
    inject: Inject,
    body_chars: usize,
) -> String {
    if hits.is_empty() {
        return String::new();
    }
    let mut out = String::from(match inject {
        Inject::Snippets => {
            "Possibly relevant memories (semantic match, best first). Read a file if it applies:\n"
        }
        Inject::TopBody => {
            "Possibly relevant memories (semantic match, best first). The best match is shown in full; read a file if another applies:\n"
        }
        Inject::Bodies => "Possibly relevant memories (semantic match, best first), shown in full:\n",
    });
    for (n, hit) in hits.iter().enumerate() {
        let path = memory_dir.join(&hit.id);
        let in_full = match inject {
            Inject::Snippets => false,
            Inject::TopBody => n == 0,
            Inject::Bodies => true,
        };
        if in_full {
            let _ = writeln!(
                out,
                "\n## {} ({:.2})\n{}\n\n{}",
                path.display(),
                hit.score,
                hit.description,
                cap_body(&hit.body, body_chars)
            );
        } else {
            let _ = writeln!(
                out,
                "- {} ({:.2}): {}",
                path.display(),
                hit.score,
                hit.description
            );
        }
    }
    out
}

fn cap_body(body: &str, max_chars: usize) -> String {
    if body.chars().count() <= max_chars {
        return body.to_owned();
    }
    let head: String = body.chars().take(max_chars).collect();
    format!("{head}\n[truncated; read the file for the rest]")
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
                body: "body line".to_owned(),
                score: 0.5
            }
        );
    }

    fn hit_with_body(id: &str, score: f64, body: &str) -> Hit {
        Hit {
            id: id.to_owned(),
            description: format!("about {id}"),
            body: body.to_owned(),
            score,
        }
    }

    #[test]
    fn top_body_mode_shows_the_best_match_in_full_and_the_rest_as_snippets() {
        let hits = [
            hit_with_body("a.md", 0.9, "the full fix for a"),
            hit_with_body("b.md", 0.8, "the full fix for b"),
        ];
        let text = render_context_with(Path::new("/mem"), &hits, Inject::TopBody, 1000);
        assert!(text.contains("/mem/a.md (0.90)"));
        assert!(text.contains("the full fix for a"));
        assert!(text.contains("/mem/b.md (0.80)"));
        assert!(text.contains("about b.md"));
        assert!(!text.contains("the full fix for b"));
    }

    #[test]
    fn bodies_mode_shows_every_match_in_full() {
        let hits = [
            hit_with_body("a.md", 0.9, "fix a"),
            hit_with_body("b.md", 0.8, "fix b"),
        ];
        let text = render_context_with(Path::new("/mem"), &hits, Inject::Bodies, 1000);
        assert!(text.contains("fix a") && text.contains("fix b"));
    }

    #[test]
    fn snippets_mode_never_includes_a_body() {
        let hits = [hit_with_body("a.md", 0.9, "secret body")];
        let text = render_context_with(Path::new("/mem"), &hits, Inject::Snippets, 1000);
        assert!(text.contains("about a.md") && !text.contains("secret body"));
    }

    #[test]
    fn a_long_body_is_cut_and_says_so() {
        let hits = [hit_with_body("a.md", 0.9, &"x".repeat(500))];
        let text = render_context_with(Path::new("/mem"), &hits, Inject::TopBody, 100);
        assert!(text.contains(&"x".repeat(100)));
        assert!(!text.contains(&"x".repeat(101)));
        assert!(text.contains("truncated"));
    }

    #[test]
    fn a_short_body_is_not_marked_truncated() {
        let hits = [hit_with_body("a.md", 0.9, "short")];
        let text = render_context_with(Path::new("/mem"), &hits, Inject::TopBody, 100);
        assert!(!text.contains("truncated"));
    }

    #[test]
    fn every_mode_is_empty_without_hits() {
        for mode in [Inject::Snippets, Inject::TopBody, Inject::Bodies] {
            assert_eq!(render_context_with(Path::new("/mem"), &[], mode, 100), "");
        }
    }

    #[test]
    fn context_lists_path_score_and_description() {
        let hits = [Hit {
            id: "feedback_sudo.md".to_owned(),
            description: "Agent cannot run sudo".to_owned(),
            body: String::new(),
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
