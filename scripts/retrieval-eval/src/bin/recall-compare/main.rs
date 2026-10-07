//! Compares memory-recall's embedding retrieval with the defaults it would
//! replace, on retrieval time, detail kept, tokens and answer quality:
//! `memory` against Claude's MEMORY.md index and cavemem, `skills` against
//! Claude's skill listing plus whole-file loading.
mod memory;
mod skills;

use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;
use std::thread;

use anyhow::{Context, Result};
use clap::{Args, Parser, Subcommand};
use retrieval_eval::llm_run::{report, FactsFile, Item, Llm, QueryRun};

#[derive(Parser)]
#[command(about = "Compare embedding retrieval with the default memory and skill loading")]
struct Cli {
    #[command(flatten)]
    common: Common,
    #[command(subcommand)]
    command: Command,
}

#[derive(Args)]
pub struct Common {
    /// Key facts per query (not needed by `render`).
    #[arg(long)]
    pub facts: Option<PathBuf>,
    /// Skip the model calls and report only the retrieval stage.
    #[arg(long)]
    pub no_llm: bool,
    #[arg(long, default_value = "claude")]
    pub claude_bin: PathBuf,
    #[arg(long, default_value = "sonnet")]
    pub model: String,
    #[arg(long, default_value_t = 6)]
    pub jobs: usize,
    /// Only the first N queries, for a smoke test.
    #[arg(long)]
    pub limit_queries: Option<usize>,
    #[arg(long)]
    pub json: Option<PathBuf>,
}

#[derive(Subcommand)]
enum Command {
    /// memory-recall vs the MEMORY.md index vs cavemem.
    Memory(memory::Args),
    /// Section retrieval vs the skill listing plus whole-file loading.
    Skills(skills::Args),
    /// Re-print the tables from a saved `--json` file, without any model calls.
    Render { input: PathBuf },
}

/// System names in the order the first query lists them.
fn systems_of(runs: &[QueryRun]) -> Vec<String> {
    runs.first()
        .map(|q| q.systems.iter().map(|s| s.system.clone()).collect())
        .unwrap_or_default()
}

fn render(input: &std::path::Path) -> Result<()> {
    let raw = fs::read_to_string(input).with_context(|| format!("read {}", input.display()))?;
    let runs: Vec<QueryRun> =
        serde_json::from_str(&raw).with_context(|| format!("parse {}", input.display()))?;
    let names = systems_of(&runs);
    let systems: Vec<&str> = names.iter().map(String::as_str).collect();
    let with_llm = runs
        .iter()
        .flat_map(|q| q.systems.iter())
        .any(|s| s.answer.is_some());
    report(&runs, &systems, with_llm);
    Ok(())
}

impl Common {
    pub fn load_items(&self) -> Result<Vec<Item>> {
        let facts = self.facts.as_ref().context("--facts is required")?;
        let raw = fs::read_to_string(facts).context("read facts")?;
        let mut items = serde_json::from_str::<FactsFile>(&raw)
            .context("parse facts")?
            .queries;
        if let Some(n) = self.limit_queries {
            items.truncate(n);
        }
        Ok(items)
    }

    /// A scratch working directory for `claude -p`, so no project settings or
    /// CLAUDE.md are found there.
    pub fn llm(&self, workdir: &std::path::Path) -> Llm {
        Llm {
            bin: self.claude_bin.clone(),
            model: self.model.clone(),
            workdir: workdir.to_owned(),
        }
    }
}

/// Runs `work` for every index in `0..count` on `jobs` threads; results come
/// back in index order.
pub fn parallel<T: Send>(
    count: usize,
    jobs: usize,
    work: impl Fn(usize) -> Result<T> + Sync,
) -> Result<Vec<T>> {
    let next = AtomicUsize::new(0);
    let results = Mutex::new(Vec::new());
    thread::scope(|scope| {
        for _ in 0..jobs.max(1) {
            scope.spawn(|| loop {
                let i = next.fetch_add(1, Ordering::SeqCst);
                if i >= count {
                    break;
                }
                let outcome = work(i);
                if let Ok(mut guard) = results.lock() {
                    guard.push((i, outcome));
                }
                eprintln!("  done query {}", i.saturating_add(1));
            });
        }
    });
    let mut done = results
        .into_inner()
        .map_err(|_| anyhow::anyhow!("a worker panicked"))?;
    done.sort_by_key(|(i, _)| *i);
    done.into_iter()
        .map(|(i, outcome)| {
            outcome.with_context(|| format!("query {} failed", i.saturating_add(1)))
        })
        .collect()
}

pub fn emit(common: &Common, runs: &[QueryRun], systems: &[&str]) -> Result<()> {
    report(runs, systems, !common.no_llm);
    if let Some(path) = &common.json {
        fs::write(path, serde_json::to_string_pretty(runs)?)
            .with_context(|| format!("write {}", path.display()))?;
    }
    Ok(())
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match &cli.command {
        Command::Memory(args) => memory::run(&cli.common, args),
        Command::Skills(args) => skills::run(&cli.common, args),
        Command::Render { input } => render(input),
    }
}
