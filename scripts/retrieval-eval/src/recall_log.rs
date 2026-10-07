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
    /// The hook gave up (server down, timeout, no cache) and injected nothing.
    #[serde(default)]
    pub failed: bool,
    /// The embedding server was unreachable and the matches are keyword (BM25) ones.
    #[serde(default)]
    pub fallback: bool,
}

impl Entry {
    pub fn failure(kind: &str, at: &str) -> Self {
        Self {
            at: at.to_owned(),
            kind: kind.to_owned(),
            best_score: None,
            matches: 0,
            full: 0,
            tokens: 0,
            failed: true,
            fallback: false,
        }
    }
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
    /// Of `prompts`, how many were served by the keyword fallback.
    pub fallback: usize,
    /// Prompts where the hook gave up; not counted in `prompts`.
    pub failed: usize,
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

/// The current time as `YYYY-MM-DDTHH:MM:SSZ`.
pub fn now_iso8601() -> String {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_secs());
    iso8601(secs)
}

/// Records that the hook gave up on a prompt, so an outage shows in the summary.
/// A log that cannot be written is ignored: the hook must never fail a prompt.
pub fn append_failure(path: &std::path::Path, kind: &str) {
    let _ = append_rotating(
        path,
        &Entry::failure(kind, &now_iso8601()),
        DEFAULT_ROTATION,
    );
}

/// The entry as one JSON line, newline included.
pub fn to_line(entry: &Entry) -> String {
    let mut line = serde_json::to_string(entry).unwrap_or_default();
    line.push('\n');
    line
}

/// Appends the entry to the log at `path`, creating the file and its directory.
pub fn append(path: &std::path::Path, entry: &Entry) -> std::io::Result<()> {
    use std::io::Write;
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let mut file = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)?;
    file.write_all(to_line(entry).as_bytes())
}

/// When the log is rotated and how many rotated files are kept.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Rotation {
    /// Rotate before an append when the log has reached this many bytes.
    pub max_bytes: u64,
    /// Rotated `.N.gz` files to keep; older ones are deleted.
    pub keep: usize,
}

/// About 10,000 prompts at roughly 120 bytes a line.
pub const DEFAULT_ROTATION: Rotation = Rotation {
    max_bytes: 1_048_576,
    keep: 5,
};

/// Like `append`, but first moves a log that has reached `rotation.max_bytes`
/// to `<path>.1.gz` (shifting older ones up and dropping those past `keep`).
pub fn append_rotating(
    path: &std::path::Path,
    entry: &Entry,
    rotation: Rotation,
) -> std::io::Result<()> {
    if std::fs::metadata(path).is_ok_and(|m| m.len() >= rotation.max_bytes) {
        // The entry matters more than the housekeeping: a failed rotation is
        // retried on the next prompt.
        let _ = rotate(path, rotation);
    }
    append(path, entry)
}

/// A rotation older than this is assumed to have died holding its lock.
const LOCK_STALE: std::time::Duration = std::time::Duration::from_secs(60);

fn with_suffix(path: &std::path::Path, suffix: &str) -> std::path::PathBuf {
    let mut name = path.as_os_str().to_owned();
    name.push(suffix);
    name.into()
}

fn rotated_path(path: &std::path::Path, n: usize) -> std::path::PathBuf {
    with_suffix(path, &format!(".{n}.gz"))
}

/// Hooks run concurrently, so only the one that takes the lock rotates; the
/// others append to the old file and carry on.
fn rotate(path: &std::path::Path, rotation: Rotation) -> std::io::Result<()> {
    let lock = with_suffix(path, ".lock");
    let stale = std::fs::metadata(&lock)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.elapsed().ok())
        .is_some_and(|age| age > LOCK_STALE);
    if stale {
        let _ = std::fs::remove_file(&lock);
    }
    std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&lock)?;
    let result = rotate_locked(path, rotation);
    let _ = std::fs::remove_file(&lock);
    result
}

fn rotate_locked(path: &std::path::Path, rotation: Rotation) -> std::io::Result<()> {
    use std::io::Write;
    if !std::fs::metadata(path).is_ok_and(|m| m.len() >= rotation.max_bytes) {
        return Ok(());
    }
    if rotation.keep == 0 {
        return std::fs::remove_file(path);
    }
    let _ = std::fs::remove_file(rotated_path(path, rotation.keep));
    for n in (1..rotation.keep).rev() {
        if rotated_path(path, n).exists() {
            std::fs::rename(
                rotated_path(path, n),
                rotated_path(path, n.saturating_add(1)),
            )?;
        }
    }
    // Renaming first means lines appended while compressing go to a fresh log.
    let moving = with_suffix(path, ".rotating");
    std::fs::rename(path, &moving)?;
    let raw = std::fs::read(&moving)?;
    let mut encoder = flate2::write::GzEncoder::new(
        std::fs::File::create(rotated_path(path, 1))?,
        flate2::Compression::default(),
    );
    encoder.write_all(&raw)?;
    encoder.finish()?;
    std::fs::remove_file(&moving)
}

/// The text of the log and its rotated files, oldest first.
pub fn read_all(path: &std::path::Path) -> std::io::Result<String> {
    use std::io::Read;
    let mut rotated = Vec::new();
    while rotated_path(path, rotated.len().saturating_add(1)).exists() {
        rotated.push(rotated_path(path, rotated.len().saturating_add(1)));
    }
    let mut out = String::new();
    for file in rotated.iter().rev() {
        flate2::read::GzDecoder::new(std::fs::File::open(file)?).read_to_string(&mut out)?;
    }
    match std::fs::read_to_string(path) {
        Ok(text) => out.push_str(&text),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => return Err(error),
    }
    Ok(out)
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
            let all_of_kind: Vec<&Entry> = entries.iter().filter(|e| e.kind == kind).collect();
            let failed = all_of_kind.iter().filter(|e| e.failed).count();
            let of_kind: Vec<&Entry> = all_of_kind.into_iter().filter(|e| !e.failed).collect();
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
                fallback: of_kind.iter().filter(|e| e.fallback).count(),
                failed,
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
        "| kind | prompts | injected | in full | tokens/prompt | tokens/injection | median best score | keyword fallback | failed |\n|---|---|---|---|---|---|---|---|---|\n",
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
            "| {} | {} | {} ({:.0}%) | {} ({:.0}%) | {:.0} | {:.0} | {} | {} | {} |\n",
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
            s.fallback,
            s.failed,
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
            failed: false,
            fallback: false,
        }
    }

    #[test]
    fn a_failure_entry_has_no_score_and_no_injection() {
        let failure = Entry::failure("memory", "2026-10-07T12:00:00Z");
        assert!(failure.failed);
        assert_eq!(failure.best_score, None);
        assert_eq!((failure.matches, failure.full, failure.tokens), (0, 0, 0));
    }

    #[test]
    fn summary_counts_prompts_served_by_the_keyword_fallback() {
        let mut keyword = entry("memory", Some(3.2), 2, 0, 90);
        keyword.fallback = true;
        let entries = vec![entry("memory", Some(0.8), 1, 0, 100), keyword];
        let sum = &summarise(&entries)[0];
        assert_eq!((sum.prompts, sum.fallback), (2, 1));
        assert!(render_summary(std::slice::from_ref(sum)).contains("| 1 | 0 |"));
    }

    #[test]
    fn old_log_lines_without_a_fallback_field_still_parse() {
        let old = r#"{"at":"t","kind":"memory","best_score":0.8,"matches":1,"full":0,"tokens":9}"#;
        assert!(!parse_log(old)[0].fallback);
    }

    #[test]
    fn old_log_lines_without_a_failed_field_still_parse() {
        let old = r#"{"at":"t","kind":"memory","best_score":0.8,"matches":1,"full":0,"tokens":9}"#;
        let parsed = parse_log(old);
        assert_eq!(parsed.len(), 1);
        assert!(!parsed[0].failed);
    }

    #[test]
    fn summary_counts_failures_apart_from_prompts_that_were_served() {
        let mut entries = vec![entry("memory", Some(0.8), 1, 0, 100)];
        entries.push(Entry::failure("memory", "t"));
        entries.push(Entry::failure("memory", "t"));
        let sum = &summarise(&entries)[0];
        assert_eq!(sum.prompts, 1);
        assert_eq!(sum.failed, 2);
        assert!(render_summary(std::slice::from_ref(sum)).contains("| 2 |"));
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
    fn append_creates_the_directory_and_keeps_earlier_lines() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("state/recall.jsonl");
        append(&path, &entry("memory", Some(0.8), 1, 1, 500)).unwrap();
        append(&path, &entry("skills", None, 0, 0, 0)).unwrap();
        let entries = parse_log(&std::fs::read_to_string(&path).unwrap());
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[1].kind, "skills");
    }

    fn gz(path: &std::path::Path, n: usize) -> std::path::PathBuf {
        let mut name = path.as_os_str().to_owned();
        name.push(format!(".{n}.gz"));
        name.into()
    }

    fn tag(n: usize) -> Entry {
        entry("memory", Some(0.5), n, 0, n)
    }

    const TINY: Rotation = Rotation {
        max_bytes: 200,
        keep: 2,
    };

    #[test]
    fn a_small_log_is_appended_to_without_rotating() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("recall.jsonl");
        append_rotating(&path, &tag(1), DEFAULT_ROTATION).unwrap();
        append_rotating(&path, &tag(2), DEFAULT_ROTATION).unwrap();
        assert_eq!(parse_log(&std::fs::read_to_string(&path).unwrap()).len(), 2);
        assert!(!gz(&path, 1).exists());
    }

    #[test]
    fn a_full_log_is_gzipped_to_dot_one_and_a_new_log_started() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("recall.jsonl");
        for n in 1..=3 {
            append_rotating(&path, &tag(n), TINY).unwrap();
        }
        assert!(gz(&path, 1).exists());
        let current = parse_log(&std::fs::read_to_string(&path).unwrap());
        assert!(current.len() < 3);
        let all = parse_log(&read_all(&path).unwrap());
        assert_eq!(all.iter().map(|e| e.matches).collect::<Vec<_>>(), [1, 2, 3]);
    }

    #[test]
    fn only_keep_rotated_files_survive_and_the_oldest_go_first() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("recall.jsonl");
        for n in 1..=30 {
            append_rotating(&path, &tag(n), TINY).unwrap();
        }
        assert!(gz(&path, 1).exists() && gz(&path, 2).exists());
        assert!(!gz(&path, 3).exists());
        let all: Vec<usize> = parse_log(&read_all(&path).unwrap())
            .iter()
            .map(|e| e.matches)
            .collect();
        assert!(all.len() < 30, "the oldest lines were dropped");
        assert_eq!(all.last(), Some(&30));
        assert!(all.windows(2).all(|w| w[0] < w[1]), "order is kept");
    }

    #[test]
    fn a_missing_log_reads_as_empty() {
        let dir = tempfile::tempdir().unwrap();
        assert_eq!(read_all(&dir.path().join("none.jsonl")).unwrap(), "");
    }

    #[test]
    fn a_rotation_already_in_progress_is_left_alone_and_the_entry_still_lands() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("recall.jsonl");
        for n in 1..=2 {
            append_rotating(&path, &tag(n), TINY).unwrap();
        }
        let mut lock = path.as_os_str().to_owned();
        lock.push(".lock");
        std::fs::write(&lock, "").unwrap();
        append_rotating(&path, &tag(3), TINY).unwrap();
        assert!(parse_log(&read_all(&path).unwrap())
            .iter()
            .any(|e| e.matches == 3));
    }

    #[test]
    fn summary_of_nothing_is_empty() {
        assert!(summarise(&[]).is_empty());
    }
}
