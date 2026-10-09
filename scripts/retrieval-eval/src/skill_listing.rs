//! What the skill listing costs. Claude Code puts one `- name: description`
//! line per skill in every session and stops at a fixed share of the context
//! window, so each skill added makes every other one cost more or fall off.
use std::fs;
use std::path::Path;

use crate::corpus::{frontmatter_field, skill_names, CorpusError};

/// Claude Code cuts a description in the listing at this many characters.
pub const DESCRIPTION_CHARS: usize = 1536;
const BYTES_PER_TOKEN: usize = 4;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry {
    pub name: String,
    pub description: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Audit {
    /// Skills with their listing cost in tokens, heaviest first.
    pub skills: Vec<(String, usize)>,
    pub total_tokens: usize,
    pub cap_tokens: usize,
    /// Skills of the average size that still fit under the cap (0 when over).
    pub headroom_skills: usize,
    /// Description length each skill could have if the listing held `target_skills`.
    pub budget_chars: usize,
    pub target_skills: usize,
}

impl Audit {
    pub fn over_cap(&self) -> bool {
        self.total_tokens > self.cap_tokens
    }
}

/// The line the listing holds for one skill, description cut at `description_chars`.
pub fn listing_line(entry: &Entry, description_chars: usize) -> String {
    let description: String = entry.description.chars().take(description_chars).collect();
    format!("- {}: {description}", entry.name)
}

fn tokens_of_bytes(bytes: usize) -> usize {
    bytes.div_ceil(BYTES_PER_TOKEN)
}

/// Longest description (characters) that lets `skills` average-named skills
/// share `cap_tokens`, counting the `- name: ` prefix and a newline per line.
pub fn description_budget(skills: usize, cap_tokens: usize, mean_name_chars: usize) -> usize {
    if skills == 0 {
        return DESCRIPTION_CHARS;
    }
    let per_line = cap_tokens
        .saturating_mul(BYTES_PER_TOKEN)
        .checked_div(skills)
        .unwrap_or(0);
    // "- " + name + ": " + newline
    per_line.saturating_sub(mean_name_chars.saturating_add(5))
}

pub fn audit(entries: &[Entry], cap_tokens: usize, target_skills: usize) -> Audit {
    // The newline between lines is part of what each skill costs.
    let bytes: Vec<(String, usize)> = entries
        .iter()
        .map(|e| {
            (
                e.name.clone(),
                listing_line(e, DESCRIPTION_CHARS).len().saturating_add(1),
            )
        })
        .collect();
    let total_tokens = tokens_of_bytes(bytes.iter().map(|(_, b)| *b).sum());
    let mut skills: Vec<(String, usize)> = bytes
        .into_iter()
        .map(|(name, b)| (name, tokens_of_bytes(b)))
        .collect();
    skills.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
    let mean_tokens = total_tokens.checked_div(skills.len()).unwrap_or(0);
    let headroom_skills = cap_tokens
        .saturating_sub(total_tokens)
        .checked_div(mean_tokens)
        .unwrap_or(0);
    let mean_name_chars = entries
        .iter()
        .map(|e| e.name.chars().count())
        .sum::<usize>()
        .checked_div(entries.len())
        .unwrap_or(0);
    Audit {
        skills,
        total_tokens,
        cap_tokens,
        headroom_skills,
        budget_chars: description_budget(target_skills, cap_tokens, mean_name_chars),
        target_skills,
    }
}

/// One entry per skill directory under `skills_root` that holds a `SKILL.md`.
pub fn load_entries(skills_root: &Path) -> Result<Vec<Entry>, CorpusError> {
    let mut entries = Vec::new();
    for name in skill_names(skills_root)? {
        let path = skills_root.join(&name).join("SKILL.md");
        let raw = fs::read_to_string(&path).map_err(|source| CorpusError::Read { path, source })?;
        entries.push(Entry {
            description: frontmatter_field(&raw, "description").unwrap_or_default(),
            name,
        });
    }
    Ok(entries)
}

pub fn render(audit: &Audit, show: usize) -> String {
    let mut out = format!(
        "{} skills, listing ≈ {} tokens against a cap of {} ({})\n",
        audit.skills.len(),
        audit.total_tokens,
        audit.cap_tokens,
        if audit.over_cap() {
            "OVER: skills past the cap are not listed".to_owned()
        } else {
            format!(
                "room for about {} more skills of average size",
                audit.headroom_skills
            )
        }
    );
    out.push_str("\n| skill | listing tokens |\n|---|---|\n");
    for (name, tokens) in audit.skills.iter().take(show) {
        out.push_str(&format!("| {name} | {tokens} |\n"));
    }
    out.push_str(&format!(
        "\nTo hold {} skills under the cap, each description can run about {} characters.\n",
        audit.target_skills, audit.budget_chars
    ));
    out
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]
mod tests {
    use super::*;

    fn entry(name: &str, description: &str) -> Entry {
        Entry {
            name: name.to_owned(),
            description: description.to_owned(),
        }
    }

    fn many(count: usize, description_chars: usize) -> Vec<Entry> {
        (0..count)
            .map(|n| entry(&format!("skill-{n:03}"), &"d".repeat(description_chars)))
            .collect()
    }

    #[test]
    fn a_listing_line_cuts_the_description() {
        let line = listing_line(&entry("git", "abcdefgh"), 3);
        assert_eq!(line, "- git: abc");
    }

    #[test]
    fn the_audit_sums_the_listing_and_ranks_the_heaviest_first() {
        let entries = [entry("small", "x"), entry("big", &"y".repeat(400))];
        let a = audit(&entries, 1000, 10);
        assert_eq!(a.skills[0].0, "big");
        assert!(a.total_tokens >= a.skills[0].1);
        assert!(!a.over_cap());
    }

    #[test]
    fn headroom_counts_more_skills_of_average_size_and_is_zero_when_over() {
        let a = audit(&many(10, 100), 10_000, 100);
        assert!(a.headroom_skills > 0);
        let full = audit(&many(10, 100), a.total_tokens, 100);
        assert_eq!(full.headroom_skills, 0);
        let over = audit(&many(10, 100), 5, 100);
        assert!(over.over_cap());
        assert_eq!(over.headroom_skills, 0);
    }

    #[test]
    fn a_hundred_skills_at_current_sizes_overflow_a_cap_one_percent_of_200k_tokens() {
        let a = audit(&many(100, 400), 2000, 100);
        assert!(a.over_cap());
    }

    #[test]
    fn the_description_budget_shrinks_as_skills_are_added() {
        let at_20 = description_budget(20, 2000, 12);
        let at_100 = description_budget(100, 2000, 12);
        assert!(at_20 > at_100, "{at_20} vs {at_100}");
        // 8000 bytes / 100 skills = 80 per line, minus "- " + 12 + ": " + newline.
        assert_eq!(at_100, 80 - 17);
    }

    #[test]
    fn descriptions_trimmed_to_the_budget_fit_the_cap() {
        let budget = description_budget(100, 2000, 9);
        let entries: Vec<Entry> = many(100, budget);
        assert!(!audit(&entries, 2000, 100).over_cap());
    }

    #[test]
    fn no_skills_is_an_empty_listing_not_an_error() {
        let a = audit(&[], 2000, 100);
        assert_eq!((a.total_tokens, a.headroom_skills), (0, 0));
        assert!(!a.over_cap());
    }
}
