use std::fs;
use std::path::PathBuf;
use std::process::ExitCode;

use anyhow::{bail, Context, Result};
use clap::{Parser, ValueEnum};
use retrieval_eval::bm25::Bm25;
use retrieval_eval::corpus::{load_memories, load_skill_sections, Chunk};
use retrieval_eval::embed::{Embedder, EmbedderSpec};
use retrieval_eval::eval::{fuse, run, score, Run};
use retrieval_eval::queries::{self, unknown_expectations};
use retrieval_eval::report::{markdown_table, misses};
use retrieval_eval::retriever::Retriever;
use tracing::{info, warn};

#[derive(Clone, Copy, ValueEnum)]
enum CorpusKind {
    /// One chunk per memory file.
    Memory,
    /// One chunk per `##` section of the named skills' markdown files.
    Skills,
}

#[derive(Parser)]
#[command(about = "Score BM25 and embedding retrievers on query -> expected-chunk pairs")]
struct Cli {
    #[arg(long, value_enum)]
    corpus: CorpusKind,
    /// Directory of memory `*.md` files (corpus=memory).
    #[arg(long)]
    memory_dir: Option<PathBuf>,
    /// Skills root, e.g. ~/.claude/skills (corpus=skills).
    #[arg(long)]
    skills_root: Option<PathBuf>,
    /// Skill dir names under --skills-root (corpus=skills).
    #[arg(long, value_delimiter = ',')]
    skills: Vec<String>,
    /// JSON file: {"queries":[{"q":"...","expect":["chunk id"]}]}.
    #[arg(long)]
    queries: PathBuf,
    /// Skip the BM25 baseline.
    #[arg(long)]
    no_bm25: bool,
    /// NAME=PRESET@BASE_URL[#DIMS] for an OpenAI-compatible embeddings server
    /// (llama-server --embeddings); PRESET is `none` or `gemma`. Repeatable.
    #[arg(long = "embedder")]
    embedders: Vec<EmbedderSpec>,
    /// Add a reciprocal-rank-fusion row of BM25 plus each embedder.
    #[arg(long)]
    rrf: bool,
    /// Print each retriever's queries ranked worse than 3rd.
    #[arg(long)]
    misses: bool,
    /// Only check that every expected id exists in the corpus.
    #[arg(long)]
    validate_only: bool,
    /// Also write the scores as JSON here.
    #[arg(long)]
    json: Option<PathBuf>,
}

fn load_corpus(cli: &Cli) -> Result<Vec<Chunk>> {
    match cli.corpus {
        CorpusKind::Memory => {
            let dir = cli
                .memory_dir
                .as_ref()
                .context("--memory-dir is required for --corpus memory")?;
            Ok(load_memories(dir)?)
        }
        CorpusKind::Skills => {
            let root = cli
                .skills_root
                .as_ref()
                .context("--skills-root is required for --corpus skills")?;
            if cli.skills.is_empty() {
                bail!("--skills is required for --corpus skills");
            }
            Ok(load_skill_sections(root, &cli.skills)?)
        }
    }
}

fn real_main() -> Result<()> {
    let cli = Cli::parse();
    let chunks = load_corpus(&cli)?;
    let queries = queries::load(&cli.queries)?;
    info!(chunks = chunks.len(), queries = queries.len(), "loaded");

    let stale = unknown_expectations(&queries, &chunks);
    for (query, id) in &stale {
        warn!(%query, %id, "expected id is not in the corpus");
    }
    if !stale.is_empty() {
        bail!("{} expected ids are not in the corpus", stale.len());
    }
    if cli.validate_only {
        println!("ok: {} queries, {} chunks", queries.len(), chunks.len());
        return Ok(());
    }

    let mut retrievers: Vec<Box<dyn Retriever>> = Vec::new();
    if !cli.no_bm25 {
        retrievers.push(Box::new(Bm25::new()));
    }
    for spec in &cli.embedders {
        retrievers.push(Box::new(Embedder::new(spec.clone())));
    }

    let mut runs: Vec<Run> = Vec::new();
    for retriever in &mut retrievers {
        info!(retriever = retriever.name(), "running");
        match run(retriever.as_mut(), &chunks, &queries) {
            Ok(finished) => runs.push(finished),
            Err(error) => warn!(retriever = retriever.name(), %error, "retriever failed; skipped"),
        }
    }
    if cli.rrf {
        let parts: Vec<&Run> = runs.iter().collect();
        match fuse(&parts).filter(|_| parts.len() > 1) {
            Some(fused) => runs.push(fused),
            None => warn!("--rrf needs at least two successful retrievers; skipped"),
        }
    }
    if runs.is_empty() {
        bail!("no retriever produced a result");
    }

    let scores: Vec<_> = runs.iter().map(|r| score(r, &chunks, &queries)).collect();
    println!(
        "{} chunks, {} queries, whole corpus = {:.0} tokens\n",
        chunks.len(),
        queries.len(),
        scores.first().map_or(0.0, |s| s.corpus_tokens)
    );
    println!("{}", markdown_table(&scores));
    if cli.misses {
        for s in &scores {
            println!("{}", misses(s, &queries));
        }
    }
    if let Some(path) = &cli.json {
        let json = serde_json::to_string_pretty(&scores).context("serialise scores")?;
        fs::write(path, json).with_context(|| format!("write {}", path.display()))?;
    }
    Ok(())
}

fn main() -> ExitCode {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
        )
        .with_writer(std::io::stderr)
        .init();
    match real_main() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("error: {error:#}");
            ExitCode::FAILURE
        }
    }
}
