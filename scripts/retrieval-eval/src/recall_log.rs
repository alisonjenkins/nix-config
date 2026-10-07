//! A per-prompt record of what a recall hook did, kept so a trial of real
//! prompts can say how often a memory or skill matched and what it cost.
//! It holds scores and counts only, never the prompt.
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Entry {
    /// ISO8601 UTC.
    pub at: String,
    /// `memory` or `skills`.
    pub kind: String,
    /// The best score over everything searched, injected or not.
    pub best_score: Option<f64>,
    /// Matches put in front of the model.
    pub matches: usize,
    /// Of those, how many were shown in full rather than as a snippet.
    pub full: usize,
    /// Rough tokens the injection added to the prompt.
    pub tokens: usize,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Summary {
    pub kind: String,
    pub prompts: usize,
    pub injected: usize,
    pub injected_full: usize,
    pub mean_tokens_per_prompt: f64,
    pub mean_tokens_per_injection: f64,
    pub best_score_median: Option<f64>,
}

/// `unix_secs` as `YYYY-MM-DDTHH:MM:SSZ`.
// Days-to-civil-date arithmetic on a u64 of seconds: the values stay far below
// i64::MAX for any real clock, and the formula needs plain operators to read.
#[allow(clippy::arithmetic_side_effects)]
pub fn iso8601(unix_secs: u64) -> String {
    let days = (unix_secs / 86_400) as i64;
    let rest = unix_secs % 86_400;
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let day_of_era = z.rem_euclid(146_097);
    let year_of_era =
        (day_of_era - day_of_era / 1_460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let mp = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = year_of_era + era * 400 + i64::from(month <= 2);
    format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}Z",
        rest / 3_600,
        rest % 3_600 / 60,
        rest % 60
    )
}

/// The entry as one JSON line, newline included.
pub fn to_line(entry: &Entry) -> String {
    let mut line = serde_json::to_string(entry).unwrap_or_default();
    line.push('\n');
    line
}

/// Entries from a log; lines that do not parse are skipped.
pub fn parse_log(text: &str) -> Vec<Entry> {
    text.lines()
        .filter_map(|line| serde_json::from_str(line).ok())
        .collect()
}

/// One summary per kind, in order of first appearance.
pub fn summarise(entries: &[Entry]) -> Vec<Summary> {
    let mut kinds: Vec<&str> = Vec::new();
    for entry in entries {
        if !kinds.contains(&entry.kind.as_str()) {
            kinds.push(&entry.kind);
        }
    }
    kinds
        .into_iter()
        .map(|kind| {
            let of_kind: Vec<&Entry> = entries.iter().filter(|e| e.kind == kind).collect();
            let injected: Vec<&&Entry> = of_kind.iter().filter(|e| e.matches > 0).collect();
            let total_tokens: usize = of_kind.iter().map(|e| e.tokens).sum();
            let mut scores: Vec<f64> = of_kind.iter().filter_map(|e| e.best_score).collect();
            scores.sort_by(f64::total_cmp);
            Summary {
                kind: kind.to_owned(),
                prompts: of_kind.len(),
                injected: injected.len(),
                injected_full: of_kind.iter().filter(|e| e.full > 0).count(),
                mean_tokens_per_prompt: mean(total_tokens, of_kind.len()),
                mean_tokens_per_injection: mean(total_tokens, injected.len()),
                best_score_median: scores.get(scores.len() / 2).copied(),
            }
        })
        .collect()
}

fn mean(total: usize, count: usize) -> f64 {
    if count == 0 {
        0.0
    } else {
        total as f64 / count as f64
    }
}

/// The summaries as a Markdown table.
pub fn render_summary(summaries: &[Summary]) -> String {
    let mut out = String::from(
        "| kind | prompts | injected | in full | tokens/prompt | tokens/injection | median best score |\n|---|---|---|---|---|---|---|\n",
    );
    for s in summaries {
        let share = |n: usize| {
            if s.prompts == 0 {
                0.0
            } else {
                100.0 * n as f64 / s.prompts as f64
            }
        };
        out.push_str(&format!(
            "| {} | {} | {} ({:.0}%) | {} ({:.0}%) | {:.0} | {:.0} | {} |\n",
            s.kind,
            s.prompts,
            s.injected,
            share(s.injected),
            s.injected_full,
            share(s.injected_full),
            s.mean_tokens_per_prompt,
            s.mean_tokens_per_injection,
            s.best_score_median
                .map_or_else(|| "-".to_owned(), |v| format!("{v:.2}")),
        ));
    }
    out
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]
mod tests {
    use super::*;

    fn entry(kind: &str, best: Option<f64>, matches: usize, full: usize, tokens: usize) -> Entry {
        Entry {
            at: "2026-10-07T12:00:00Z".to_owned(),
            kind: kind.to_owned(),
            best_score: best,
            matches,
            full,
            tokens,
        }
    }

    #[test]
    fn iso8601_formats_known_instants() {
        assert_eq!(iso8601(0), "1970-01-01T00:00:00Z");
        assert_eq!(iso8601(951_782_400), "2000-02-29T00:00:00Z");
        assert_eq!(iso8601(1_000_000_000), "2001-09-09T01:46:40Z");
        assert_eq!(iso8601(1_791_388_800), "2026-10-07T16:00:00Z");
    }

    #[test]
    fn a_line_round_trips_and_ends_in_a_newline() {
        let original = entry("memory", Some(0.81), 2, 1, 900);
        let line = to_line(&original);
        assert!(line.ends_with('\n'));
        assert_eq!(parse_log(&line), vec![original]);
    }

    #[test]
    fn a_line_holds_no_prompt_field() {
        let line = to_line(&entry("memory", None, 0, 0, 0));
        assert!(!line.contains("prompt"));
        assert!(line.contains("\"best_score\":null"));
    }

    #[test]
    fn unparseable_lines_are_skipped() {
        let good = to_line(&entry("skills", Some(0.7), 1, 0, 40));
        let text = format!("not json\n{good}\n\n{{\"at\": 3}}\n");
        assert_eq!(parse_log(&text).len(), 1);
    }

    #[test]
    fn summary_counts_per_kind_and_averages_over_all_prompts() {
        let entries = vec![
            entry("memory", Some(0.5), 0, 0, 0),
            entry("memory", Some(0.8), 2, 1, 1000),
            entry("memory", Some(0.72), 1, 0, 200),
            entry("memory", None, 0, 0, 0),
            entry("skills", Some(0.9), 1, 1, 600),
        ];
        let sums = summarise(&entries);
        assert_eq!(sums.len(), 2);
        let memory = &sums[0];
        assert_eq!(memory.kind, "memory");
        assert_eq!(memory.prompts, 4);
        assert_eq!(memory.injected, 2);
        assert_eq!(memory.injected_full, 1);
        assert!((memory.mean_tokens_per_prompt - 300.0).abs() < 1e-9);
        assert!((memory.mean_tokens_per_injection - 600.0).abs() < 1e-9);
        assert_eq!(memory.best_score_median, Some(0.72));
        assert_eq!(sums[1].kind, "skills");
        assert_eq!(sums[1].prompts, 1);
    }

    #[test]
    fn summary_of_nothing_is_empty() {
        assert!(summarise(&[]).is_empty());
    }
}
