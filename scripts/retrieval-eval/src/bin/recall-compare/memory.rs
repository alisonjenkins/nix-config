//! memory-recall against Claude's default memory and cavemem.
use std::collections::HashSet;
use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::Instant;

use anyhow::{Context, Result};
use clap::Args as ClapArgs;
use retrieval_eval::bench::{approx_tokens, percentile};
use retrieval_eval::compare::{
    before_cutoff, extract_files, parse_cavemem_search, CavememHit, ClaudeCall,
};
use retrieval_eval::llm_run::{ask, read_files, Coverage, Item, Llm, QueryRun, SystemRun};

use crate::{emit, parallel, Common};

const SYSTEM_PREAMBLE: &str = "You are helping the user with their NixOS homelab and workstation \
configuration. Answer the user's question directly, in at most 6 sentences, and be specific: \
name the cause, the exact setting, command, path or value. Use any memory context provided; if \
it lacks the detail needed, say exactly what is missing rather than guessing.";
const SELECT_TASK: &str = "From the memory listed above, name up to 3 files you would open to \
answer the user's question. Reply with ONLY the file names, one per line, or NONE.";
/// cavemem needs every query word in one note, so a raw prompt matches nothing;
/// in real use the model forms the keywords, which `cavemem_kw*` reproduces.
const KEYWORD_TASK: &str = "Give 2 to 5 distinctive single-word keywords to search a full-text \
index of the user's past coding sessions for the answer to their question. Every keyword must \
appear in the same note to match, so pick words likely to appear verbatim (names, tools, error \
terms). Reply with ONLY the keywords separated by spaces.";
const CAVEMEM_TOP: usize = 5;
const CAVEMEM_FULL_TOP: usize = 3;
/// Over-fetch so that, after dropping today's own observations, enough remain.
const CAVEMEM_OVERFETCH: usize = 100;
const CAVEMEM_TIMING_RUNS: usize = 3;
const SYSTEMS: [&str; 10] = [
    "none",
    "default_index",
    "default_read",
    "recall_snippet",
    "recall_read",
    "recall_top",
    "recall_all",
    "cavemem_raw",
    "cavemem_kw",
    "cavemem_kw_full",
];

#[derive(ClapArgs)]
pub struct Args {
    #[arg(long)]
    memory_dir: PathBuf,
    /// The `memory-recall` binary, run as the real hook.
    #[arg(long)]
    hook_bin: PathBuf,
    /// NAME=PRESET@URL[#DIMS], as the hook was indexed with.
    #[arg(long)]
    embedder: String,
    #[arg(long)]
    cache: PathBuf,
    #[arg(long, default_value_t = 3)]
    top: usize,
    #[arg(long, default_value_t = 0.74)]
    min_score: f64,
    #[arg(long)]
    cavemem_bin: PathBuf,
    #[arg(long)]
    cavemem_db: PathBuf,
    #[arg(long)]
    sqlite_bin: PathBuf,
    /// Observation id of the first row from the benchmark day; later rows are ignored.
    #[arg(long)]
    cavemem_cutoff_id: u64,
    /// Only these systems (comma separated); all of them when omitted.
    #[arg(long, value_delimiter = ',')]
    systems: Vec<String>,
}

impl Args {
    fn selected(&self) -> Vec<&'static str> {
        SYSTEMS
            .iter()
            .copied()
            .filter(|s| self.systems.is_empty() || self.systems.iter().any(|w| w == s))
            .collect()
    }
}

/// What a system hands the model before any follow-up step.
#[derive(Debug, Clone, Default)]
struct Retrieved {
    /// Text placed in the model's context by the retrieval itself.
    text: String,
    /// What the model is shown about the expected memory in that text.
    focus: String,
    local_ms: f64,
}

fn ms(duration: std::time::Duration) -> f64 {
    duration.as_secs_f64() * 1000.0
}

fn run_hook(args: &Args, prompt: &str, inject: &str) -> Result<(String, f64)> {
    let payload = serde_json::json!({ "prompt": prompt }).to_string();
    let started = Instant::now();
    let mut child = Command::new(&args.hook_bin)
        .args(["--memory-dir"])
        .arg(&args.memory_dir)
        .args(["--embedder", &args.embedder, "--cache"])
        .arg(&args.cache)
        .args([
            "hook",
            "--top",
            &args.top.to_string(),
            "--min-score",
            &args.min_score.to_string(),
            "--inject",
            inject,
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .context("spawn the hook")?;
    child
        .stdin
        .take()
        .context("hook stdin")?
        .write_all(payload.as_bytes())?;
    let output = child.wait_with_output()?;
    let elapsed = ms(started.elapsed());
    let text = if output.stdout.is_empty() {
        String::new()
    } else {
        let v: serde_json::Value = serde_json::from_slice(&output.stdout).context("hook JSON")?;
        v.get("hookSpecificOutput")
            .and_then(|o| o.get("additionalContext"))
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default()
            .to_owned()
    };
    Ok((text, elapsed))
}

fn cavemem_search(args: &Args, query: &str, limit: usize) -> Result<(Vec<CavememHit>, f64)> {
    let started = Instant::now();
    let output = Command::new(&args.cavemem_bin)
        .env("CAVEMEM_NO_AUTOSTART", "1")
        .args(["search", query, "--limit", &limit.to_string()])
        .stderr(Stdio::null())
        .output()
        .context("run cavemem search")?;
    let elapsed = ms(started.elapsed());
    Ok((
        parse_cavemem_search(&String::from_utf8_lossy(&output.stdout)),
        elapsed,
    ))
}

/// What cavemem's `get_observations` MCP tool returns: the stored text of each id.
fn cavemem_full(args: &Args, ids: &[u64]) -> Result<Vec<String>> {
    if ids.is_empty() {
        return Ok(Vec::new());
    }
    let list = ids.iter().map(u64::to_string).collect::<Vec<_>>().join(",");
    let output = Command::new(&args.sqlite_bin)
        .args(["-readonly", "-json"])
        .arg(&args.cavemem_db)
        .arg(format!(
            "select id, content from observations where id in ({list})"
        ))
        .output()
        .context("run sqlite3")?;
    let rows: Vec<serde_json::Value> =
        serde_json::from_slice(&output.stdout).context("sqlite3 JSON")?;
    Ok(ids
        .iter()
        .filter_map(|id| {
            rows.iter()
                .find(|r| r.get("id").and_then(serde_json::Value::as_u64) == Some(*id))
                .and_then(|r| r.get("content"))
                .and_then(serde_json::Value::as_str)
                .map(str::to_owned)
        })
        .collect())
}

/// Median time of a real `--limit 5` search, plus the top hits that predate the cutoff.
fn cavemem_top(args: &Args, query: &str) -> Result<(Vec<CavememHit>, f64)> {
    let mut timings = Vec::new();
    for _ in 0..CAVEMEM_TIMING_RUNS {
        timings.push(cavemem_search(args, query, CAVEMEM_TOP)?.1);
    }
    timings.sort_by(f64::total_cmp);
    let (wide, _) = cavemem_search(args, query, CAVEMEM_OVERFETCH)?;
    let hits = before_cutoff(wide, args.cavemem_cutoff_id)
        .into_iter()
        .take(CAVEMEM_TOP)
        .collect();
    Ok((hits, percentile(&timings, 50.0)))
}

fn snippets_text(hits: &[CavememHit]) -> String {
    hits.iter()
        .map(|h| format!("[obs {} score {:.1}] {}", h.id, h.score, h.snippet))
        .collect::<Vec<_>>()
        .join("\n")
}

/// Runs the real hook once and files its output under the systems that share it.
fn hook_rows(
    args: &Args,
    item: &Item,
    inject: &str,
    systems: &[&str],
    wanted: &[&str],
    out: &mut Vec<(String, Retrieved)>,
) -> Result<()> {
    if !systems.iter().any(|s| wanted.contains(s)) {
        return Ok(());
    }
    let (injected, hook_ms) = run_hook(args, &item.q, inject)?;
    let row = Retrieved {
        text: injected.clone(),
        focus: injected,
        local_ms: hook_ms,
    };
    for system in systems {
        out.push(((*system).to_owned(), row.clone()));
    }
    Ok(())
}

fn retrieve_all(
    args: &Args,
    item: &Item,
    index: &str,
    wanted: &[&str],
) -> Result<Vec<(String, Retrieved)>> {
    let expected = item.expect.first().context("query without expect")?;
    let mut out = vec![("none".to_owned(), Retrieved::default())];

    let focus = index
        .lines()
        .filter(|line| line.contains(expected.as_str()))
        .collect::<Vec<_>>()
        .join("\n");
    let index_row = Retrieved {
        text: index.to_owned(),
        focus,
        local_ms: 0.0,
    };
    out.push(("default_index".to_owned(), index_row.clone()));
    out.push(("default_read".to_owned(), index_row));

    hook_rows(
        args,
        item,
        "snippets",
        &["recall_snippet", "recall_read"],
        wanted,
        &mut out,
    )?;
    hook_rows(args, item, "top", &["recall_top"], wanted, &mut out)?;
    hook_rows(args, item, "all", &["recall_all"], wanted, &mut out)?;

    if wanted.iter().any(|s| s.starts_with("cavemem")) {
        let (hits, search_ms) = cavemem_top(args, &item.q)?;
        let snippets = snippets_text(&hits);
        out.push((
            "cavemem_raw".to_owned(),
            Retrieved {
                text: snippets.clone(),
                focus: snippets,
                local_ms: search_ms,
            },
        ));
    }
    Ok(out)
}

struct KeywordSearch {
    hits: Vec<CavememHit>,
    calls: Vec<ClaudeCall>,
    search_ms: f64,
}

/// The model forms keywords; if they match nothing, retry with the first two.
fn keyword_search(args: &Args, llm: &Llm, item: &Item, base: &str) -> Result<KeywordSearch> {
    let call = ask(llm, &format!("{base}{KEYWORD_TASK}"), &item.q)?;
    let keywords: Vec<String> = call
        .text
        .split(|c: char| !(c.is_alphanumeric() || c == '_' || c == '-'))
        .filter(|w| !w.is_empty())
        .take(5)
        .map(str::to_owned)
        .collect();
    let (mut hits, mut search_ms) = cavemem_top(args, &keywords.join(" "))?;
    if hits.is_empty() && keywords.len() > 2 {
        let first_two = keywords.iter().take(2).cloned().collect::<Vec<_>>();
        let (retry, retry_ms) = cavemem_top(args, &first_two.join(" "))?;
        hits = retry;
        search_ms += retry_ms;
    }
    Ok(KeywordSearch {
        hits,
        calls: vec![call],
        search_ms,
    })
}

fn llm_phase(
    args: &Args,
    llm: &Llm,
    item: &Item,
    retrieved: &[(String, Retrieved)],
    known: &HashSet<String>,
    systems: &[&str],
) -> Result<Vec<SystemRun>> {
    let expected = item.expect.first().context("expect")?;
    let nothing = Retrieved::default();
    let mut keyword: Option<KeywordSearch> = None;
    let mut runs = Vec::new();
    for system in systems.iter().copied() {
        let mut run = SystemRun::named(system);
        let got = retrieved
            .iter()
            .find(|(name, _)| name == system)
            .map_or(&nothing, |(_, r)| r);
        let base = format!("{SYSTEM_PREAMBLE}\n\n");
        match system {
            "none" => {
                let call = ask(llm, &base, &item.q)?;
                run.finish(&item.facts, &[call], "");
            }
            "cavemem_raw" => {}
            "cavemem_kw" | "cavemem_kw_full" => {
                if keyword.is_none() {
                    keyword = Some(keyword_search(args, llm, item, &base)?);
                }
                let Some(found) = keyword.as_ref() else {
                    continue;
                };
                let (label, text) = if system == "cavemem_kw" {
                    (
                        "# Past-session search results (cavemem)",
                        snippets_text(&found.hits),
                    )
                } else {
                    let ids: Vec<u64> = found
                        .hits
                        .iter()
                        .take(CAVEMEM_FULL_TOP)
                        .map(|h| h.id)
                        .collect();
                    (
                        "# Past-session observations (cavemem)",
                        cavemem_full(args, &ids)?.join("\n---\n"),
                    )
                };
                let answer = ask(llm, &format!("{base}{label}\n{text}"), &item.q)?;
                let mut calls = found.calls.clone();
                calls.push(answer);
                run.local_ms = found.search_ms;
                run.retrieved_tokens = approx_tokens(text.len());
                run.retrieval = Coverage::of(&text, &item.facts);
                run.finish(&item.facts, &calls, &text);
            }
            "default_index" | "recall_snippet" | "recall_top" | "recall_all" => {
                let label = if system == "default_index" {
                    "# Memory index (MEMORY.md)"
                } else {
                    "# Memories possibly relevant to the user's message"
                };
                let call = ask(llm, &format!("{base}{label}\n{}", got.text), &item.q)?;
                run.finish(&item.facts, &[call], &got.text);
            }
            "default_read" | "recall_read" => {
                let listing = format!("{base}{}\n\n{SELECT_TASK}", got.text);
                let pick = ask(llm, &listing, &item.q)?;
                let chosen = extract_files(&pick.text, known, 3);
                run.selection_hit = Some(chosen.iter().any(|c| c == expected));
                let opened = read_files(&args.memory_dir, &chosen);
                let system_prompt = if opened.is_empty() {
                    base.clone()
                } else {
                    format!("{base}# Memory files you opened\n{opened}")
                };
                let call = ask(llm, &system_prompt, &item.q)?;
                let context = format!("{}\n{opened}", got.text);
                run.finish(&item.facts, &[pick, call], &context);
                run.retrieved_tokens = approx_tokens(context.len());
            }
            other => anyhow::bail!("unknown system {other}"),
        }
        runs.push(run);
    }
    Ok(runs)
}

pub fn run(common: &Common, args: &Args) -> Result<()> {
    let items = common.load_items()?;
    let index = fs::read_to_string(args.memory_dir.join("MEMORY.md")).context("read MEMORY.md")?;
    let known: HashSet<String> = fs::read_dir(&args.memory_dir)?
        .filter_map(|e| e.ok())
        .filter_map(|e| e.file_name().into_string().ok())
        .filter(|n| n.ends_with(".md") && n != "MEMORY.md")
        .collect();

    // Phase 1: quiet and sequential, so the timings are not disturbed.
    eprintln!("retrieval phase: {} queries", items.len());
    let selected = args.selected();
    let mut retrieved_all = Vec::new();
    for item in &items {
        retrieved_all.push(retrieve_all(args, item, &index, &selected)?);
    }

    let mut query_runs: Vec<QueryRun> = items
        .iter()
        .zip(&retrieved_all)
        .map(|(item, retrieved)| {
            let systems = selected
                .iter()
                .map(|name| {
                    let mut run = SystemRun::named(name);
                    if let Some((_, got)) = retrieved.iter().find(|(n, _)| n == name) {
                        run.local_ms = got.local_ms;
                        run.retrieved_tokens = approx_tokens(got.text.len());
                        run.retrieval = Coverage::of(&got.focus, &item.facts);
                        run.context = Coverage::of(&got.text, &item.facts);
                    }
                    run
                })
                .collect();
            QueryRun {
                q: item.q.clone(),
                expect: item.expect.first().cloned().unwrap_or_default(),
                systems,
            }
        })
        .collect();

    // Phase 2: model calls, in parallel across queries.
    if !common.no_llm {
        let workdir = tempfile::tempdir().context("scratch dir for claude")?;
        let llm = common.llm(workdir.path());
        eprintln!(
            "model phase: {} queries, {} jobs, model {}",
            items.len(),
            common.jobs,
            common.model
        );
        let done = parallel(items.len(), common.jobs, |i| {
            let (Some(item), Some(retrieved)) = (items.get(i), retrieved_all.get(i)) else {
                anyhow::bail!("query {i} out of range");
            };
            llm_phase(args, &llm, item, retrieved, &known, &selected)
        })?;
        for (target, llm_runs) in query_runs.iter_mut().zip(done) {
            for fresh in llm_runs {
                let Some(slot) = target.systems.iter_mut().find(|s| s.system == fresh.system)
                else {
                    continue;
                };
                if fresh.answer.is_none() {
                    continue;
                }
                if fresh.local_ms > 0.0 {
                    slot.local_ms = fresh.local_ms;
                    slot.retrieval = fresh.retrieval.clone();
                }
                slot.selection_hit = fresh.selection_hit;
                slot.answer = fresh.answer;
                slot.llm_in_tokens = fresh.llm_in_tokens;
                slot.llm_out_tokens = fresh.llm_out_tokens;
                slot.llm_ms = fresh.llm_ms;
                slot.cost_usd = fresh.cost_usd;
                slot.context = fresh.context;
                if fresh.retrieved_tokens > 0.0 {
                    slot.retrieved_tokens = fresh.retrieved_tokens;
                }
            }
        }
    }

    emit(common, &query_runs, &selected)
}
