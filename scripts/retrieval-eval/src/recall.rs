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
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Inject {
    /// Path, score and one-line description of each match; the model reads the file.
    Snippets,
    /// The best match in full, the others as snippets.
    TopBody,
    /// Every match in full.
    Bodies,
    /// A match scoring at least this much in full, the rest as snippets: confident
    /// matches save the model a read, tentative ones cost only a line.
    Tiered { body_score: f64 },
}

/// What Claude Code itself puts in the prompt slot: background-task events and
/// system reminders. They are not the user's words, so retrieving for them only
/// adds noise, and blocking one loses the event.
const AUTOMATED_PREFIXES: [&str; 3] = [
    "<task-notification",
    "[SYSTEM NOTIFICATION",
    "<system-reminder",
];

/// The user's prompt from a UserPromptSubmit hook payload, or `None` when it
/// is absent, unparseable, automated, or too short to be worth a lookup.
pub fn prompt_from_hook_input(stdin_json: &str) -> Option<String> {
    let payload: serde_json::Value = serde_json::from_str(stdin_json).ok()?;
    let prompt = payload.get("prompt")?.as_str()?.trim();
    if prompt.chars().count() < MIN_PROMPT_CHARS
        || AUTOMATED_PREFIXES.iter().any(|p| prompt.starts_with(p))
    {
        return None;
    }
    Some(prompt.chars().take(MAX_PROMPT_CHARS).collect())
}

/// Claude Code's `session_id` and `prompt_id` from a hook payload, for joining the
/// hook's telemetry with Claude Code's own. Empty or absent ids are `None`.
pub fn ids_from_hook_input(stdin_json: &str) -> (Option<String>, Option<String>) {
    let payload: serde_json::Value = serde_json::from_str(stdin_json).unwrap_or_default();
    let id = |key: &str| {
        payload
            .get(key)
            .and_then(serde_json::Value::as_str)
            .filter(|s| !s.is_empty())
            .map(str::to_owned)
    };
    (id("session_id"), id("prompt_id"))
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
        Inject::Tiered { .. } => {
            "Possibly relevant memories (semantic match, best first). Confident matches are shown in full; read a file if a tentative one applies:\n"
        }
    });
    for (n, hit) in hits.iter().enumerate() {
        let path = memory_dir.join(&hit.id);
        if shown_in_full(inject, n, hit.score) {
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

/// What a hook does when it cannot retrieve memories or skills (server down after
/// the retries, or the corpus unreadable).
#[derive(Debug, Clone, Copy, PartialEq, Eq, clap::ValueEnum)]
pub enum OnUnavailable {
    /// Block the prompt (exit 2), so it is never answered without the context that
    /// might have stopped a mistake. The default.
    Block,
    /// Inject the keyword (BM25) matches instead.
    Keyword,
    /// Let the prompt through with nothing injected.
    Allow,
}

/// Longest a blocking hook waits for the embedding server. Normally it answers in
/// tens of milliseconds; after the machine has swapped the server out it needs
/// several seconds to page back in, and giving up then blocks the prompt.
const BLOCKING_WAIT: std::time::Duration = std::time::Duration::from_secs(8);

/// Longest a hook that can fall back (keyword matches, or nothing) waits: it has
/// a way out, so a stalled server should not also cost the prompt seconds.
const FALLBACK_WAIT: std::time::Duration = std::time::Duration::from_secs(3);

/// How long a hook waits for the embedding server, by what it does on failure.
pub fn hook_timeout(on_unavailable: OnUnavailable) -> std::time::Duration {
    match on_unavailable {
        OnUnavailable::Block => BLOCKING_WAIT,
        OnUnavailable::Keyword | OnUnavailable::Allow => FALLBACK_WAIT,
    }
}

/// A hook refused a prompt; `main` turns this into exit code 2 and prints it.
#[derive(Debug, thiserror::Error)]
#[error("{0}")]
pub struct Blocked(pub String);

/// The message a blocked prompt shows its user.
pub fn blocked_message(hook: &str, reason: &str) -> String {
    format!(
        "{hook}: prompt blocked because its memories or skills could not be retrieved ({reason}). \
         Start the embedding server and send it again, or run the hook with \
         --on-unavailable keyword|allow to let prompts through without them."
    )
}

/// Runs `attempt` until it succeeds or `budget` has passed, pausing `pause`
/// between tries, and returns the last error when it gives up. Covers a server
/// that is restarting, which refuses connections for about a second.
pub fn retry_until<T, E>(
    budget: std::time::Duration,
    pause: std::time::Duration,
    mut attempt: impl FnMut() -> Result<T, E>,
) -> Result<T, E> {
    let started = std::time::Instant::now();
    loop {
        match attempt() {
            Ok(value) => return Ok(value),
            Err(error) => {
                if started.elapsed().saturating_add(pause) >= budget {
                    return Err(error);
                }
            }
        }
        std::thread::sleep(pause);
    }
}

/// Best keyword (BM25) matches for `query`, best first, at most `top`, dropping
/// chunks that share no word with it. What a hook falls back to when the embedding
/// server cannot be reached, so a prompt still gets the memories and skill
/// sections that name what it asks about.
pub fn keyword_fallback(chunks: &[Chunk], query: &str, top: usize) -> Vec<(String, f64)> {
    let mut bm25 = crate::bm25::Bm25::new();
    if crate::retriever::Retriever::index(&mut bm25, chunks).is_err() {
        return Vec::new();
    }
    bm25.score_all(query)
        .map(|scored| {
            scored
                .into_iter()
                .filter(|(_, score)| *score > 0.0)
                .take(top)
                .collect()
        })
        .unwrap_or_default()
}

/// Skill sections to inject; empty when there are none. A hit's `id` is
/// `<skill>/<file>#<heading>` and its `body` the section text, cut at `max_chars`.
pub fn render_sections(skills_root: &Path, hits: &[Hit], max_chars: usize) -> String {
    if hits.is_empty() {
        return String::new();
    }
    let mut out = String::from(
        "Skill sections that may apply (semantic match, best first). Follow them if they fit the request; read the file for more:\n",
    );
    for hit in hits {
        let (file, heading) = hit.id.split_once('#').unwrap_or((hit.id.as_str(), ""));
        let _ = writeln!(
            out,
            "\n## {}#{heading} ({:.2})\n{}",
            skills_root.join(file).display(),
            hit.score,
            cap_body(&hit.body, max_chars)
        );
    }
    out
}

fn shown_in_full(inject: Inject, index: usize, score: f64) -> bool {
    match inject {
        Inject::Snippets => false,
        Inject::TopBody => index == 0,
        Inject::Bodies => true,
        Inject::Tiered { body_score } => score >= body_score,
    }
}

/// How many of `hits` `render_context_with` shows in full.
pub fn full_count(hits: &[Hit], inject: Inject) -> usize {
    hits.iter()
        .enumerate()
        .filter(|(n, hit)| shown_in_full(inject, *n, hit.score))
        .count()
}

fn cap_body(body: &str, max_chars: usize) -> String {
    if body.chars().count() <= max_chars {
        return body.to_owned();
    }
    let head: String = body.chars().take(max_chars).collect();
    format!("{head}\n[truncated; read the file for the rest]")
}

/// A names-only index of the memory files, in place of a full `MEMORY.md`: the
/// hook injects whatever matches each prompt, and the model opens a file from
/// this list when nothing matched.
pub fn render_catalogue(names: &[String]) -> String {
    let mut sorted: Vec<&str> = names
        .iter()
        .map(String::as_str)
        .filter(|name| *name != "MEMORY.md")
        .collect();
    sorted.sort_unstable();
    let mut out = String::from(
        "# Memory catalogue\n\n\
         Names only. The memories that match each prompt are injected with it; open a file \
         from this list when nothing matched.\n\n",
    );
    for name in sorted {
        let _ = writeln!(out, "- {name}");
    }
    out
}

/// Writes `content` to `path` unless it already holds exactly that, so a file
/// watcher is not woken by a rewrite that changes nothing. True if it wrote.
pub fn write_if_changed(path: &Path, content: &str) -> std::io::Result<bool> {
    if std::fs::read_to_string(path).is_ok_and(|current| current == content) {
        return Ok(false);
    }
    std::fs::write(path, content)?;
    Ok(true)
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
    fn tiered_mode_shows_only_confident_matches_in_full() {
        let hits = [
            hit_with_body("a.md", 0.82, "fix a"),
            hit_with_body("b.md", 0.77, "fix b"),
            hit_with_body("c.md", 0.71, "fix c"),
        ];
        let text = render_context_with(
            Path::new("/mem"),
            &hits,
            Inject::Tiered { body_score: 0.76 },
            1000,
        );
        assert!(text.contains("fix a") && text.contains("fix b"));
        assert!(!text.contains("fix c"));
        assert!(text.contains("/mem/c.md (0.71): about c.md"));
    }

    #[test]
    fn tiered_mode_with_nothing_confident_is_all_snippets() {
        let hits = [hit_with_body("a.md", 0.71, "fix a")];
        let text = render_context_with(
            Path::new("/mem"),
            &hits,
            Inject::Tiered { body_score: 0.76 },
            1000,
        );
        assert!(!text.contains("fix a") && text.contains("about a.md"));
    }

    #[test]
    fn claude_codes_session_and_prompt_ids_come_from_the_payload() {
        let json = r#"{"session_id":"s-1","prompt_id":"p-9","prompt":"hello there world"}"#;
        assert_eq!(
            ids_from_hook_input(json),
            (Some("s-1".to_owned()), Some("p-9".to_owned()))
        );
        assert_eq!(ids_from_hook_input(r#"{"session_id":"s-1"}"#).1, None);
        assert_eq!(ids_from_hook_input("not json"), (None, None));
        assert_eq!(ids_from_hook_input(r#"{"session_id":""}"#).0, None);
    }

    #[test]
    fn retry_until_returns_the_first_success_after_some_failures() {
        let mut calls = 0;
        let result: Result<u32, &str> = retry_until(
            std::time::Duration::from_secs(5),
            std::time::Duration::from_millis(1),
            || {
                calls += 1;
                if calls < 3 {
                    Err("not yet")
                } else {
                    Ok(calls)
                }
            },
        );
        assert_eq!(result, Ok(3));
    }

    #[test]
    fn retry_until_gives_up_at_the_budget_with_the_last_error() {
        let mut calls = 0;
        let result: Result<(), String> = retry_until(
            std::time::Duration::from_millis(30),
            std::time::Duration::from_millis(5),
            || {
                calls += 1;
                Err(format!("attempt {calls}"))
            },
        );
        assert!(calls >= 2, "retried at least once");
        assert_eq!(result, Err(format!("attempt {calls}")));
    }

    #[test]
    fn keyword_fallback_ranks_by_shared_words_and_drops_zero_scores() {
        let chunks = [
            ("a.md", "gearbox oil change interval"),
            ("b.md", "tomato watering schedule"),
            ("c.md", "gearbox noise at idle"),
        ]
        .map(|(id, text)| Chunk {
            id: id.to_owned(),
            title: id.to_owned(),
            text: text.to_owned(),
        });
        let hits = keyword_fallback(&chunks, "why is the gearbox noisy", 5);
        let ids: Vec<&str> = hits.iter().map(|(id, _)| id.as_str()).collect();
        assert_eq!(ids.len(), 2);
        assert!(ids.contains(&"a.md") && ids.contains(&"c.md"));
        assert!(keyword_fallback(&chunks, "quantum chromodynamics", 5).is_empty());
        assert_eq!(keyword_fallback(&chunks, "gearbox", 1).len(), 1);
    }

    fn section(id: &str, score: f64, text: &str) -> Hit {
        Hit {
            id: id.to_owned(),
            description: String::new(),
            body: text.to_owned(),
            score,
        }
    }

    #[test]
    fn sections_are_listed_with_their_file_path_and_text() {
        let hits = [
            section("prog/languages/rust.md#Toolchain", 0.83, "use cargo"),
            section("prog/SKILL.md#Rules", 0.74, "be good"),
        ];
        let text = render_sections(Path::new("/skills"), &hits, 1000);
        assert!(text.starts_with("Skill sections that may apply"));
        assert!(text.contains("## /skills/prog/languages/rust.md#Toolchain (0.83)\nuse cargo"));
        assert!(text.contains("## /skills/prog/SKILL.md#Rules (0.74)\nbe good"));
        assert!(text.find("rust.md").unwrap() < text.find("SKILL.md").unwrap());
    }

    #[test]
    fn long_sections_are_cut_and_point_to_the_file() {
        let hits = [section("p/a.md#H", 0.8, &"x".repeat(50))];
        let text = render_sections(Path::new("/s"), &hits, 10);
        assert!(text.contains(&"x".repeat(10)) && !text.contains(&"x".repeat(11)));
        assert!(text.contains("[truncated; read the file for the rest]"));
    }

    #[test]
    fn no_sections_render_nothing() {
        assert_eq!(render_sections(Path::new("/s"), &[], 100), "");
    }

    #[test]
    fn full_count_matches_what_render_shows_in_full() {
        let hits = [
            hit_with_body("a.md", 0.82, "fix a"),
            hit_with_body("b.md", 0.71, "fix b"),
        ];
        assert_eq!(full_count(&hits, Inject::Snippets), 0);
        assert_eq!(full_count(&hits, Inject::TopBody), 1);
        assert_eq!(full_count(&hits, Inject::Bodies), 2);
        assert_eq!(full_count(&hits, Inject::Tiered { body_score: 0.76 }), 1);
        assert_eq!(full_count(&[], Inject::Bodies), 0);
    }

    fn names(items: &[&str]) -> Vec<String> {
        items.iter().map(|s| (*s).to_owned()).collect()
    }

    #[test]
    fn catalogue_lists_every_name_sorted_one_per_line() {
        let text = render_catalogue(&names(&["b.md", "a.md", "c.md"]));
        let lines: Vec<&str> = text.lines().filter(|l| l.starts_with("- ")).collect();
        assert_eq!(lines, ["- a.md", "- b.md", "- c.md"]);
    }

    #[test]
    fn catalogue_never_lists_the_index_itself() {
        let text = render_catalogue(&names(&["MEMORY.md", "a.md"]));
        assert!(!text.contains("MEMORY.md\n") && text.contains("- a.md"));
    }

    #[test]
    fn catalogue_says_what_it_is_for() {
        let text = render_catalogue(&names(&["a.md"]));
        assert!(text.starts_with("# Memory catalogue"));
        assert!(text.contains("injected"));
    }

    #[test]
    fn catalogue_is_deterministic_and_ends_with_a_newline() {
        let a = render_catalogue(&names(&["b.md", "a.md"]));
        assert_eq!(a, render_catalogue(&names(&["a.md", "b.md"])));
        assert!(a.ends_with('\n'));
    }

    #[test]
    fn write_if_changed_writes_new_content_once() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("MEMORY.md");
        assert!(write_if_changed(&path, "one\n").unwrap());
        assert!(!write_if_changed(&path, "one\n").unwrap());
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "one\n");
    }

    #[test]
    fn write_if_changed_rewrites_when_the_content_differs() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("MEMORY.md");
        write_if_changed(&path, "one\n").unwrap();
        assert!(write_if_changed(&path, "two\n").unwrap());
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "two\n");
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
