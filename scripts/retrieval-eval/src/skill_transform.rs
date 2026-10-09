//! Rewrites a `SKILL.md` so Claude Code's always-loaded listing carries a short
//! description, and the full one moves into a `## When to use` section of the
//! body, where the skills hook can retrieve it by meaning. The source file stays
//! as written; this runs when skills are installed.
use std::fs;
use std::path::Path;

use crate::corpus::frontmatter_field;

const HEADING: &str = "When to use";

/// Why a skill cannot be transformed.
#[derive(Debug, PartialEq, Eq)]
pub enum Skipped {
    /// No frontmatter, or no description in it.
    NoDescription,
    /// The description already fits.
    AlreadyShort,
    /// The skill is hidden from the listing, so its description costs nothing.
    NotListed,
}

/// The listing description: the author's `summary:` when there is one, else the
/// first sentence of `description`, cut at a word boundary within `max_chars`.
pub fn short_description(summary: Option<&str>, description: &str, max_chars: usize) -> String {
    let source = summary.unwrap_or_else(|| first_sentence(description));
    cut_at_word(source.trim(), max_chars)
}

fn first_sentence(text: &str) -> &str {
    let mut chars = text.char_indices().peekable();
    while let Some((at, c)) = chars.next() {
        if c == '.' && chars.peek().is_none_or(|(_, next)| next.is_whitespace()) {
            return text.get(..=at).unwrap_or(text);
        }
    }
    text
}

fn cut_at_word(text: &str, max_chars: usize) -> String {
    if text.chars().count() <= max_chars {
        return text.to_owned();
    }
    let head: String = text.chars().take(max_chars).collect();
    let cut = head.rfind(char::is_whitespace).unwrap_or(head.len());
    let kept = head.get(..cut).unwrap_or(&head);
    format!("{}…", kept.trim_end_matches([',', ';', ':', '.', ' ']))
}

/// `summary:` inside a top-level `metadata:` map, the spec's place for extra fields.
fn metadata_summary(header: &str) -> Option<String> {
    let mut in_metadata = false;
    for line in header.lines() {
        if !is_continuation(line) {
            in_metadata = line.trim_end() == "metadata:";
        } else if in_metadata {
            if let Some(value) = line.trim().strip_prefix("summary:") {
                let value = value.trim().trim_matches(['"', '\'']).trim();
                return (!value.is_empty()).then(|| value.to_owned());
            }
        }
    }
    None
}

fn is_continuation(line: &str) -> bool {
    line.starts_with(char::is_whitespace)
}

/// Frontmatter lines with `description` replaced by `short` and `summary`
/// dropped, every other field kept as written.
fn rewrite_header(header: &str, short: &str) -> String {
    let quoted = serde_json::to_string(short).unwrap_or_else(|_| format!("\"{short}\""));
    let mut out: Vec<String> = Vec::new();
    let mut lines = header.lines().peekable();
    while let Some(line) = lines.next() {
        let key = line.split(':').next().unwrap_or_default();
        let owned = !is_continuation(line) && matches!(key, "description" | "summary");
        if owned {
            while lines.next_if(|l| is_continuation(l)).is_some() {}
            if key == "description" {
                out.push(format!("description: {quoted}"));
            }
        } else {
            out.push(line.to_owned());
        }
    }
    out.join("\n")
}

/// `raw` with a short listing description and the full one as a body section.
pub fn transform(raw: &str, max_chars: usize) -> Result<String, Skipped> {
    let rest = raw.strip_prefix("---\n").ok_or(Skipped::NoDescription)?;
    let end = rest.find("\n---\n").ok_or(Skipped::NoDescription)?;
    let (header, body) = (
        rest.get(..end).ok_or(Skipped::NoDescription)?,
        rest.get(end.saturating_add(5)..)
            .ok_or(Skipped::NoDescription)?,
    );
    if frontmatter_field(raw, "disable-model-invocation").as_deref() == Some("true") {
        return Err(Skipped::NotListed);
    }
    let description = frontmatter_field(raw, "description").ok_or(Skipped::NoDescription)?;
    let summary = frontmatter_field(raw, "summary").or_else(|| metadata_summary(header));
    if summary.is_none() && description.chars().count() <= max_chars {
        return Err(Skipped::AlreadyShort);
    }
    let short = short_description(summary.as_deref(), &description, max_chars);

    let heading = if body
        .lines()
        .any(|l| l.trim_end() == format!("## {HEADING}"))
    {
        format!("{HEADING} (full description)")
    } else {
        HEADING.to_owned()
    };
    let section = format!("## {heading}\n\n{description}\n\n");
    let at = if body.starts_with("## ") {
        Some(0)
    } else {
        body.find("\n## ").map(|n| n.saturating_add(1))
    };
    let body = match at {
        Some(at) => format!(
            "{}{section}{}",
            body.get(..at).unwrap_or_default(),
            body.get(at..).unwrap_or_default()
        ),
        None => format!("{}\n\n{section}", body.trim_end()),
    };
    Ok(format!(
        "---\n{}\n---\n{body}",
        rewrite_header(header, &short)
    ))
}

/// What `transform_tree` did to one skill.
#[derive(Debug, PartialEq, Eq)]
pub struct Outcome {
    pub name: String,
    pub skipped: Option<Skipped>,
}

/// For each skill directory under `input` (a child holding `SKILL.md`), writes a
/// directory under `output` with the transformed `SKILL.md` and a symlink to every
/// other entry, so bundled files stay in place. A skipped skill gets its
/// `SKILL.md` linked untouched.
pub fn transform_tree(
    input: &Path,
    output: &Path,
    max_chars: usize,
) -> std::io::Result<Vec<Outcome>> {
    let mut outcomes = Vec::new();
    let mut names: Vec<_> = fs::read_dir(input)?
        .filter_map(Result::ok)
        .filter(|e| e.path().join("SKILL.md").is_file())
        .collect();
    names.sort_by_key(fs::DirEntry::file_name);
    for entry in names {
        let name = entry.file_name().to_string_lossy().into_owned();
        let target = output.join(&name);
        fs::create_dir_all(&target)?;
        for child in fs::read_dir(entry.path())?.filter_map(Result::ok) {
            if child.file_name() != "SKILL.md" {
                symlink(&child.path(), &target.join(child.file_name()))?;
            }
        }
        let source = entry.path().join("SKILL.md");
        let skipped = match transform(&fs::read_to_string(&source)?, max_chars) {
            Ok(text) => {
                let dest = target.join("SKILL.md");
                clear(&dest)?;
                fs::write(dest, text)?;
                None
            }
            Err(why) => {
                symlink(&source, &target.join("SKILL.md"))?;
                Some(why)
            }
        };
        outcomes.push(Outcome { name, skipped });
    }
    Ok(outcomes)
}

/// Removes a file or link at `path` if there is one, so a later write or link
/// replaces it: writing through a link left by an earlier run would overwrite the
/// source it points to. A real directory is left for the caller to trip over.
fn clear(path: &Path) -> std::io::Result<()> {
    match fs::symlink_metadata(path) {
        Ok(meta) if meta.file_type().is_dir() => Ok(()),
        Ok(_) => fs::remove_file(path),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}

#[cfg(unix)]
fn symlink(from: &Path, to: &Path) -> std::io::Result<()> {
    clear(to)?;
    std::os::unix::fs::symlink(from, to)
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]
mod tests {
    use super::*;

    const LONG: &str = "Use when something is broken, failing intermittently or behaving differently than expected. Also covers regressions and flaky builds in any language.";

    fn skill(header: &str, body: &str) -> String {
        format!("---\n{header}\n---\n{body}")
    }

    #[test]
    fn the_short_description_is_the_first_sentence_cut_at_a_word() {
        assert_eq!(
            short_description(None, LONG, 200),
            "Use when something is broken, failing intermittently or behaving differently than expected."
        );
        assert_eq!(
            short_description(None, LONG, 30),
            "Use when something is broken…"
        );
    }

    #[test]
    fn an_authored_summary_wins_over_the_first_sentence() {
        assert_eq!(
            short_description(Some("Debug failures"), LONG, 80),
            "Debug failures"
        );
    }

    #[test]
    fn a_dot_inside_a_word_does_not_end_the_sentence() {
        assert_eq!(
            first_sentence("Edit SKILL.md files. Then more."),
            "Edit SKILL.md files."
        );
    }

    #[test]
    fn the_full_description_moves_into_a_section_before_the_first_heading() {
        let raw = skill(
            &format!("name: debugging\ndescription: {LONG}\nlicense: MIT"),
            "# Debugging\n\nintro text\n\n## Steps\n\n1. look\n",
        );
        let out = transform(&raw, 30).unwrap();
        assert!(out.contains("name: debugging\n"));
        assert!(out.contains("license: MIT\n"));
        assert!(out.contains("description: \"Use when something is broken…\"\n"));
        assert_eq!(
            frontmatter_field(&out, "description").unwrap(),
            "Use when something is broken…"
        );
        let intro = out.find("intro text").unwrap();
        let when = out.find(&format!("## {HEADING}\n\n{LONG}\n")).unwrap();
        let steps = out.find("## Steps").unwrap();
        assert!(intro < when && when < steps, "{out}");
    }

    #[test]
    fn a_folded_block_description_is_replaced_whole() {
        let raw = skill(
            "name: x\ndescription: >\n  Use when something is broken, failing intermittently\n  or behaving differently than expected.\nlicense: MIT",
            "## A\nbody\n",
        );
        let out = transform(&raw, 30).unwrap();
        assert!(!out.contains("  or behaving"), "{out}");
        assert!(out.contains("license: MIT\n"));
        assert!(out.contains("\n## When to use\n\nUse when something is broken, failing intermittently or behaving differently than expected.\n"));
    }

    #[test]
    fn the_summary_field_becomes_the_description_and_is_not_kept() {
        let raw = skill(
            &format!("name: x\ndescription: {LONG}\nsummary: Debug failures"),
            "## A\nb\n",
        );
        let out = transform(&raw, 80).unwrap();
        assert!(out.contains("description: \"Debug failures\""));
        assert!(!out.contains("summary:"));
    }

    #[test]
    fn a_summary_under_metadata_is_the_listing_description_and_stays_in_the_file() {
        let raw = skill(
            &format!("name: x\ndescription: {LONG}\nmetadata:\n  author: me\n  summary: \"Debug flaky failures\""),
            "## A\nb\n",
        );
        let out = transform(&raw, 80).unwrap();
        assert!(
            out.contains("description: \"Debug flaky failures\"\n"),
            "{out}"
        );
        assert!(out.contains("metadata:\n  author: me\n  summary: \"Debug flaky failures\"\n"));
    }

    #[test]
    fn a_body_without_headings_gets_the_section_at_the_end() {
        let raw = skill(&format!("name: x\ndescription: {LONG}"), "just text\n");
        let out = transform(&raw, 40).unwrap();
        assert!(
            out.ends_with(&format!("## {HEADING}\n\n{LONG}\n\n")),
            "{out}"
        );
    }

    #[test]
    fn an_existing_when_to_use_heading_is_not_duplicated() {
        let raw = skill(
            &format!("name: x\ndescription: {LONG}"),
            "## When to use\nown text\n",
        );
        let out = transform(&raw, 40).unwrap();
        assert_eq!(out.matches("## When to use\n").count(), 1);
        assert!(out.contains("## When to use (full description)\n"));
    }

    #[test]
    fn skills_that_need_no_change_are_left_alone() {
        assert_eq!(
            transform(&skill("name: x\ndescription: Short one.", "b"), 80),
            Err(Skipped::AlreadyShort)
        );
        assert_eq!(transform("no frontmatter", 80), Err(Skipped::NoDescription));
        assert_eq!(
            transform(&skill("name: x", "b"), 80),
            Err(Skipped::NoDescription)
        );
        assert_eq!(
            transform(
                &skill(
                    &format!("name: x\ndescription: {LONG}\ndisable-model-invocation: true"),
                    "b"
                ),
                40
            ),
            Err(Skipped::NotListed)
        );
    }

    #[test]
    fn running_again_into_the_same_output_never_writes_through_a_link_into_the_source() {
        let tmp = tempfile::tempdir().unwrap();
        let (input, output) = (tmp.path().join("in"), tmp.path().join("out"));
        let skill = input.join("s1");
        fs::create_dir_all(&skill).unwrap();
        let source = skill_text();
        fs::write(skill.join("SKILL.md"), &source).unwrap();
        fs::write(skill.join("extra.md"), "extra").unwrap();
        fs::create_dir_all(&output).unwrap();

        // First run: nothing needs shortening, so SKILL.md is linked to the source.
        transform_tree(&input, &output, 10_000).unwrap();
        // Second run: now it does; writing must replace the link, not follow it.
        let outcomes = transform_tree(&input, &output, 30).unwrap();
        assert_eq!(outcomes[0].skipped, None);
        assert_eq!(fs::read_to_string(skill.join("SKILL.md")).unwrap(), source);
        assert!(fs::read_to_string(output.join("s1/SKILL.md"))
            .unwrap()
            .contains("## When to use"));
        assert_eq!(
            fs::read_to_string(output.join("s1/extra.md")).unwrap(),
            "extra"
        );
    }

    fn skill_text() -> String {
        skill(&format!("name: s1\ndescription: {LONG}"), "## A\nb\n")
    }

    #[test]
    fn a_tree_is_rewritten_with_bundled_files_linked_and_skipped_skills_untouched() {
        let tmp = tempfile::tempdir().unwrap();
        let (input, output) = (tmp.path().join("in"), tmp.path().join("out"));
        let long = input.join("long");
        fs::create_dir_all(long.join("languages")).unwrap();
        fs::write(
            long.join("SKILL.md"),
            skill(&format!("name: long\ndescription: {LONG}"), "## A\nb\n"),
        )
        .unwrap();
        fs::write(long.join("extra.md"), "extra").unwrap();
        let short = input.join("short");
        fs::create_dir_all(&short).unwrap();
        fs::write(
            short.join("SKILL.md"),
            skill("name: short\ndescription: Tiny.", "b"),
        )
        .unwrap();
        fs::create_dir_all(&output).unwrap();

        let outcomes = transform_tree(&input, &output, 40).unwrap();
        assert_eq!(
            outcomes,
            [
                Outcome {
                    name: "long".into(),
                    skipped: None
                },
                Outcome {
                    name: "short".into(),
                    skipped: Some(Skipped::AlreadyShort)
                },
            ]
        );
        assert!(fs::read_to_string(output.join("long/SKILL.md"))
            .unwrap()
            .contains("## When to use"));
        assert_eq!(
            fs::read_to_string(output.join("long/extra.md")).unwrap(),
            "extra"
        );
        assert!(output.join("long/languages").is_dir());
        assert_eq!(
            fs::read_to_string(output.join("short/SKILL.md")).unwrap(),
            fs::read_to_string(short.join("SKILL.md")).unwrap()
        );
    }
}
