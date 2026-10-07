//! Pieces shared by the memory and skills comparisons: key-fact scoring, one
//! isolated `claude -p` call, and the result tables.
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::bench::percentile;
use crate::compare::{fact_coverage, parse_claude_json, ClaudeCall};

/// Marks every prompt a comparison sends, so a leak into cavemem's capture
/// shows up as a search hit for it.
pub const MARKER: &str = "RECALLBENCH-7f3a";
const CLAUDE_ATTEMPTS: u32 = 3;

#[derive(Debug, Clone, Deserialize)]
pub struct Fact {
    pub text: String,
    /// `description` for detail a one-line summary carries, `body` for the rest.
    pub r#where: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Item {
    pub q: String,
    pub expect: Vec<String>,
    pub facts: Vec<Fact>,
}

#[derive(Debug, Deserialize)]
pub struct FactsFile {
    pub queries: Vec<Item>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Coverage {
    pub desc_found: usize,
    pub desc_total: usize,
    pub body_found: usize,
    pub body_total: usize,
}

impl Coverage {
    pub fn of(text: &str, facts: &[Fact]) -> Self {
        let split = |label: &str| -> (usize, usize) {
            let wanted: Vec<String> = facts
                .iter()
                .filter(|f| f.r#where == label)
                .map(|f| f.text.clone())
                .collect();
            fact_coverage(text, &wanted)
        };
        let (desc_found, desc_total) = split("description");
        let (body_found, body_total) = split("body");
        Self {
            desc_found,
            desc_total,
            body_found,
            body_total,
        }
    }

    pub fn add(&mut self, other: &Self) {
        self.desc_found = self.desc_found.saturating_add(other.desc_found);
        self.desc_total = self.desc_total.saturating_add(other.desc_total);
        self.body_found = self.body_found.saturating_add(other.body_found);
        self.body_total = self.body_total.saturating_add(other.body_total);
    }

    pub fn found(&self) -> usize {
        self.desc_found.saturating_add(self.body_found)
    }

    pub fn total(&self) -> usize {
        self.desc_total.saturating_add(self.body_total)
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SystemRun {
    pub system: String,
    pub local_ms: f64,
    pub retrieved_tokens: f64,
    /// Facts present in what retrieval itself returned.
    pub retrieval: Coverage,
    /// Facts present in everything the model had when it answered.
    pub context: Coverage,
    pub selection_hit: Option<bool>,
    pub answer: Option<Coverage>,
    pub llm_in_tokens: u64,
    /// Results saved before the cache split was recorded load these as zero.
    #[serde(default)]
    pub llm_cache_read_tokens: u64,
    #[serde(default)]
    pub llm_cache_write_tokens: u64,
    pub llm_out_tokens: u64,
    pub llm_ms: f64,
    pub cost_usd: f64,
}

impl SystemRun {
    pub fn named(system: &str) -> Self {
        Self {
            system: system.to_owned(),
            ..Self::default()
        }
    }

    /// Records the model calls made for this system and scores the last one's answer.
    pub fn finish(&mut self, facts: &[Fact], calls: &[ClaudeCall], context_text: &str) {
        self.context = Coverage::of(context_text, facts);
        self.llm_in_tokens = calls.iter().map(|c| c.input_tokens).sum();
        self.llm_cache_read_tokens = calls.iter().map(|c| c.cache_read_tokens).sum();
        self.llm_cache_write_tokens = calls.iter().map(|c| c.cache_write_tokens).sum();
        self.llm_out_tokens = calls.iter().map(|c| c.output_tokens).sum();
        self.llm_ms = calls.iter().map(|c| c.api_ms).sum();
        self.cost_usd = calls.iter().map(|c| c.cost_usd).sum();
        if let Some(last) = calls.last() {
            self.answer = Some(Coverage::of(&last.text, facts));
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueryRun {
    pub q: String,
    pub expect: String,
    pub systems: Vec<SystemRun>,
}

pub struct Llm {
    pub bin: PathBuf,
    pub model: String,
    pub workdir: PathBuf,
}

impl Llm {
    /// Deletes the transcript of a conversation started with `ask_first`, which
    /// Claude Code keeps under its config directory for the scratch workdir.
    pub fn forget(&self, call: &ClaudeCall) {
        let config = std::env::var_os("CLAUDE_CONFIG_DIR")
            .map(PathBuf::from)
            .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".claude")));
        if let Some(config) = config {
            forget_session(&config, &self.workdir, &call.session_id);
        }
    }
}

/// The folder name Claude Code uses for a project directory: every character
/// that is not a letter or digit becomes `-`.
fn project_dir_name(workdir: &Path) -> String {
    workdir
        .to_string_lossy()
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
        .collect()
}

/// Best effort: a transcript that is not there, or cannot be removed, is left alone.
fn forget_session(config_dir: &Path, workdir: &Path, session_id: &str) {
    if session_id.is_empty() {
        return;
    }
    let file = config_dir
        .join("projects")
        .join(project_dir_name(workdir))
        .join(format!("{session_id}.jsonl"));
    let _ = fs::remove_file(file);
}

#[derive(Debug, Error)]
pub enum AskError {
    #[error("write the system prompt in {path}: {source}")]
    SystemPrompt {
        path: PathBuf,
        source: std::io::Error,
    },
    #[error("claude -p failed after {attempts} attempts: {last}")]
    Failed { attempts: u32, last: String },
}

/// One isolated, tool-less, hook-less headless call. Settings sources are
/// limited to the (empty) working directory, so the user's hooks, including
/// cavemem's capture, never run; the system prompt carries MARKER so any leak
/// is searchable.
pub fn ask(llm: &Llm, system: &str, user: &str) -> Result<ClaudeCall, AskError> {
    run_claude(llm, system, user, Session::Throwaway)
}

/// Starts a conversation that `ask_next` can continue.
pub fn ask_first(llm: &Llm, system: &str, user: &str) -> Result<ClaudeCall, AskError> {
    run_claude(llm, system, user, Session::Keep)
}

/// A second turn in the conversation `first` started: the earlier turns come back
/// from the prompt cache, as they do when Claude Code continues after a tool result.
pub fn ask_next(
    llm: &Llm,
    system: &str,
    first: &ClaudeCall,
    user: &str,
) -> Result<ClaudeCall, AskError> {
    run_claude(llm, system, user, Session::Resume(&first.session_id))
}

enum Session<'a> {
    Throwaway,
    Keep,
    Resume(&'a str),
}

fn run_claude(
    llm: &Llm,
    system: &str,
    user: &str,
    session: Session<'_>,
) -> Result<ClaudeCall, AskError> {
    let file = tempfile::Builder::new()
        .prefix("recall-compare-system-")
        .tempfile_in(&llm.workdir)
        .map_err(|source| AskError::SystemPrompt {
            path: llm.workdir.clone(),
            source,
        })?;
    fs::write(file.path(), format!("{system}\n\n[{MARKER}]")).map_err(|source| {
        AskError::SystemPrompt {
            path: file.path().to_owned(),
            source,
        }
    })?;
    let mut last = String::new();
    for attempt in 0..CLAUDE_ATTEMPTS {
        let mut command = Command::new(&llm.bin);
        command
            .current_dir(&llm.workdir)
            .args(["-p", "--model", &llm.model, "--output-format", "json"])
            .args(["--tools", "", "--effort", "low"])
            .args(["--setting-sources", "project"])
            .args(["--strict-mcp-config", "--disable-slash-commands"]);
        match session {
            Session::Throwaway => {
                command.arg("--no-session-persistence");
            }
            Session::Keep => {}
            Session::Resume(id) => {
                command.args(["--resume", id]);
            }
        }
        let output = command
            .arg("--system-prompt-file")
            .arg(file.path())
            .arg(user)
            .output();
        match output {
            Ok(out) => match parse_claude_json(&String::from_utf8_lossy(&out.stdout)) {
                Ok(call) => return Ok(call),
                Err(error) => last = error.to_string(),
            },
            Err(error) => last = error.to_string(),
        }
        thread::sleep(Duration::from_secs(2_u64.saturating_pow(attempt)));
    }
    Err(AskError::Failed {
        attempts: CLAUDE_ATTEMPTS,
        last,
    })
}

pub fn read_files(dir: &Path, names: &[String]) -> String {
    names
        .iter()
        .filter_map(|n| {
            fs::read_to_string(dir.join(n))
                .ok()
                .map(|body| format!("## {n}\n{body}"))
        })
        .collect::<Vec<_>>()
        .join("\n\n")
}

pub fn mean(values: impl Iterator<Item = f64>) -> f64 {
    let (sum, n) = values.fold((0.0, 0.0), |(s, n), v| (s + v, n + 1.0));
    if n == 0.0 {
        0.0
    } else {
        sum / n
    }
}

pub fn pct(found: usize, total: usize) -> f64 {
    if total == 0 {
        0.0
    } else {
        found as f64 * 100.0 / total as f64
    }
}

/// Prints the retrieval-stage table and, with the model, the end-to-end table.
pub fn report(runs: &[QueryRun], systems: &[&str], with_llm: bool) {
    let rows = |name: &str| -> Vec<&SystemRun> {
        runs.iter()
            .flat_map(|q| q.systems.iter())
            .filter(|s| s.system == name)
            .collect()
    };
    let sum_cov = |name: &str, pick: &dyn Fn(&SystemRun) -> Coverage| -> Coverage {
        rows(name).iter().fold(Coverage::default(), |mut acc, s| {
            acc.add(&pick(s));
            acc
        })
    };

    println!("## Retrieval stage (deterministic)\n");
    println!("| system | local retrieval ms (median/query) | tokens put in context by retrieval | facts in retrieved text | …description facts | …body-only facts |");
    println!("|---|---|---|---|---|---|");
    for name in systems {
        let r = rows(name);
        let c = sum_cov(name, &|s| s.retrieval.clone());
        let tokens = mean(r.iter().map(|s| s.retrieved_tokens));
        let ms_median = {
            let mut v: Vec<f64> = r.iter().map(|s| s.local_ms).collect();
            v.sort_by(f64::total_cmp);
            percentile(&v, 50.0)
        };
        println!(
            "| {name} | {ms_median:.1} | {tokens:.0} | {:.0}% | {:.0}% | {:.0}% |",
            pct(c.found(), c.total()),
            pct(c.desc_found, c.desc_total),
            pct(c.body_found, c.body_total)
        );
    }

    if !with_llm {
        return;
    }
    println!("\n## End to end with the model (isolated `claude -p`)\n");
    println!("| system | right source chosen | facts in final context | facts in answer | answers with every fact | model input tokens | …read from cache | …written to cache | model output tokens | model API ms | cost $/query |");
    println!("|---|---|---|---|---|---|---|---|---|---|---|");
    for name in systems {
        let r = rows(name);
        let ctx = sum_cov(name, &|s| s.context.clone());
        let ans = sum_cov(name, &|s| s.answer.clone().unwrap_or_default());
        let full = r
            .iter()
            .filter(|s| {
                s.answer
                    .as_ref()
                    .is_some_and(|a| a.total() > 0 && a.found() == a.total())
            })
            .count();
        let sel: Vec<bool> = r.iter().filter_map(|s| s.selection_hit).collect();
        let sel_text = if sel.is_empty() {
            "-".to_owned()
        } else {
            format!("{:.0}%", pct(sel.iter().filter(|b| **b).count(), sel.len()))
        };
        if r.iter().all(|s| s.answer.is_none()) {
            println!(
                "| {name} | {sel_text} | {:.0}% | - | - | - | - | - | - | - | - |",
                pct(ctx.found(), ctx.total())
            );
            continue;
        }
        println!(
            "| {name} | {sel_text} | {:.0}% | {:.0}% | {:.0}% | {:.0} | {:.0} | {:.0} | {:.0} | {:.0} | {:.4} |",
            pct(ctx.found(), ctx.total()),
            pct(ans.found(), ans.total()),
            pct(full, r.len()),
            mean(r.iter().map(|s| s.llm_in_tokens as f64)),
            mean(r.iter().map(|s| s.llm_cache_read_tokens as f64)),
            mean(r.iter().map(|s| s.llm_cache_write_tokens as f64)),
            mean(r.iter().map(|s| s.llm_out_tokens as f64)),
            mean(r.iter().map(|s| s.llm_ms)),
            mean(r.iter().map(|s| s.cost_usd)),
        );
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]
mod tests {
    use super::*;

    #[test]
    fn project_dir_names_replace_every_non_alphanumeric_character() {
        assert_eq!(
            project_dir_name(Path::new("/tmp/nix-shell.dsbUBP/.tmpJuxLfO")),
            "-tmp-nix-shell-dsbUBP--tmpJuxLfO"
        );
    }

    #[test]
    fn forget_removes_the_session_transcript_and_tolerates_its_absence() {
        let config = tempfile::tempdir().unwrap();
        let workdir = Path::new("/tmp/work.dir");
        let dir = config
            .path()
            .join("projects")
            .join(project_dir_name(workdir));
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("abc.jsonl"), "{}").unwrap();
        fs::write(dir.join("other.jsonl"), "{}").unwrap();
        forget_session(config.path(), workdir, "abc");
        assert!(!dir.join("abc.jsonl").exists());
        assert!(dir.join("other.jsonl").exists());
        forget_session(config.path(), workdir, "abc");
        forget_session(config.path(), workdir, "");
        assert!(dir.join("other.jsonl").exists());
    }

    fn fact(text: &str, place: &str) -> Fact {
        Fact {
            text: text.to_owned(),
            r#where: place.to_owned(),
        }
    }

    #[test]
    fn coverage_splits_description_and_body_facts() {
        let facts = [
            fact("AllowListSetting", "description"),
            fact("::1", "body"),
            fact("zramSwap", "body"),
        ];
        let c = Coverage::of("add ::1 to the allowlistsetting", &facts);
        assert_eq!((c.desc_found, c.desc_total), (1, 1));
        assert_eq!((c.body_found, c.body_total), (1, 2));
        assert_eq!((c.found(), c.total()), (2, 3));
    }

    #[test]
    fn coverage_add_accumulates_every_field() {
        let mut a = Coverage {
            desc_found: 1,
            desc_total: 2,
            body_found: 3,
            body_total: 4,
        };
        a.add(&a.clone());
        assert_eq!(
            (a.desc_found, a.desc_total, a.body_found, a.body_total),
            (2, 4, 6, 8)
        );
    }

    #[test]
    fn finish_sums_calls_and_scores_only_the_last_answer() {
        let call = |text: &str, i: u64, o: u64| ClaudeCall {
            text: text.to_owned(),
            input_tokens: i,
            cache_read_tokens: i / 2,
            cache_write_tokens: i / 5,
            output_tokens: o,
            api_ms: 100.0,
            cost_usd: 0.01,
            session_id: String::new(),
        };
        let facts = [fact("alpha", "body"), fact("beta", "body")];
        let mut run = SystemRun::named("s");
        run.finish(
            &facts,
            &[call("alpha beta", 10, 1), call("alpha", 20, 2)],
            "ctx",
        );
        assert_eq!((run.llm_in_tokens, run.llm_out_tokens), (30, 3));
        assert_eq!(
            (run.llm_cache_read_tokens, run.llm_cache_write_tokens),
            (15, 6)
        );
        assert!((run.llm_ms - 200.0).abs() < 1e-9);
        assert_eq!(run.answer.unwrap().found(), 1);
    }

    #[test]
    fn mean_and_pct_of_nothing_are_zero() {
        assert!(mean(std::iter::empty()).abs() < 1e-9);
        assert!(pct(1, 0).abs() < 1e-9);
        assert!((pct(1, 4) - 25.0).abs() < 1e-9);
    }

    #[test]
    fn read_files_headers_each_file_and_skips_missing_ones() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("a.md"), "alpha").unwrap();
        let text = read_files(dir.path(), &["a.md".to_owned(), "gone.md".to_owned()]);
        assert_eq!(text, "## a.md\nalpha");
    }
}
