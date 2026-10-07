use std::io::Read;
use std::path::PathBuf;
use std::process::ExitCode;
use std::time::Duration;

use anyhow::{Context, Result};
use clap::{Args, Parser, Subcommand, ValueEnum};
use retrieval_eval::corpus::{load_memories, Chunk};
use retrieval_eval::embed::{Embedder, EmbedderSpec};
use retrieval_eval::recall::{
    full_count, hit, hook_output, prompt_from_hook_input, render_catalogue, render_context_with,
    select, write_if_changed, Inject,
};
use retrieval_eval::recall_log::{
    append, append_failure, now_iso8601, parse_log, render_summary, summarise, Entry,
};
use retrieval_eval::vector_cache::VectorCache;
use tracing::{info, warn};

/// The hook runs on every prompt: a recall that takes longer than this costs
/// more than it gives, so give up and inject nothing.
const HOOK_TIMEOUT: Duration = Duration::from_secs(3);
const QUERY_TIMEOUT: Duration = Duration::from_secs(30);
const INDEX_TIMEOUT: Duration = Duration::from_secs(300);
const DEFAULT_TOP: usize = 3;
/// Rough sizing of the injected text for the log, as elsewhere in this crate.
const BYTES_PER_TOKEN: usize = 4;
/// About 1.2k tokens: most memories fit whole, and the rest say where to read on.
const DEFAULT_BODY_CHARS: usize = 3500;
/// Measured 2026-10-07 with EmbeddingGemma 2 at 256 dims over the 83 memories:
/// the right memory's top-1 score ran 0.70-0.87 (median 0.79) over 58 queries, and
/// unrelated prompts reached 0.81. A match at or above this floor is worth at
/// least a one-line snippet (about 35 tokens), so the floor leans to recall.
/// Scores are model- and dims-specific; re-measure before changing either.
const DEFAULT_MIN_SCORE: f64 = 0.70;
/// From here a match is injected in full (about 1,000 tokens), which a wrong match
/// makes expensive: only 10% of in-domain, memory-less prompts reach it.
const DEFAULT_BODY_SCORE: f64 = 0.76;

#[derive(Parser)]
#[command(about = "Semantic recall over Claude memory files, as a UserPromptSubmit hook")]
struct Cli {
    /// Directory of memory `*.md` files (every command but `log-summary`).
    #[arg(long)]
    memory_dir: Option<PathBuf>,
    /// NAME=PRESET@BASE_URL[#DIMS] of a `llama-server --embeddings` endpoint
    /// (every command but `catalogue`).
    #[arg(long)]
    embedder: Option<EmbedderSpec>,
    /// Where document vectors are cached between runs (every command but `catalogue`).
    #[arg(long)]
    cache: Option<PathBuf>,
    #[command(subcommand)]
    command: Command,
}

#[derive(Args, Clone, Copy)]
struct Selection {
    #[arg(long, default_value_t = DEFAULT_TOP)]
    top: usize,
    /// Drop matches scoring below this cosine similarity.
    #[arg(long, default_value_t = DEFAULT_MIN_SCORE)]
    min_score: f64,
    /// How much of each match to put in front of the model.
    #[arg(long, value_enum, default_value_t = InjectArg::Auto)]
    inject: InjectArg,
    /// With --inject auto: the score from which a match is injected in full.
    #[arg(long, default_value_t = DEFAULT_BODY_SCORE)]
    body_score: f64,
    /// Longest body injected in full, in characters.
    #[arg(long, default_value_t = DEFAULT_BODY_CHARS)]
    body_chars: usize,
}

#[derive(Clone, Copy, ValueEnum)]
enum InjectArg {
    /// Path, score and description; the model reads the file.
    Snippets,
    /// The best match in full, the others as snippets.
    Top,
    /// Every match in full.
    All,
    /// Matches scoring at least --body-score in full, the others as snippets.
    Auto,
}

impl InjectArg {
    fn into_inject(self, body_score: f64) -> Inject {
        match self {
            Self::Snippets => Inject::Snippets,
            Self::Top => Inject::TopBody,
            Self::All => Inject::Bodies,
            Self::Auto => Inject::Tiered { body_score },
        }
    }
}

#[derive(Subcommand)]
enum Command {
    /// Embed new or edited memories into the cache (slow the first time).
    Index,
    /// Print the best matches for TEXT with their scores.
    Query {
        text: String,
        #[command(flatten)]
        selection: Selection,
    },
    /// Read a UserPromptSubmit payload on stdin, write hook JSON on stdout.
    /// Never fails the prompt: any problem injects nothing.
    Hook {
        #[command(flatten)]
        selection: Selection,
        /// Append one line per prompt (score and sizes, never the prompt) to this file.
        #[arg(long)]
        log: Option<PathBuf>,
    },
    /// Summarise a hook log: how often a memory matched and what it added.
    LogSummary { path: PathBuf },
    /// Print a names-only index of the memories, to use in place of a full
    /// MEMORY.md now that matching memories are injected.
    Catalogue {
        /// Write it to this file instead of printing it, only if it changed.
        #[arg(long)]
        write: Option<PathBuf>,
    },
}

struct Session {
    embedder: Embedder,
    chunks: Vec<Chunk>,
    cache: VectorCache,
}

fn memory_dir(cli: &Cli) -> Result<&PathBuf> {
    cli.memory_dir.as_ref().context("--memory-dir is required")
}

fn cache_path(cli: &Cli) -> Result<&PathBuf> {
    cli.cache.as_ref().context("--cache is required")
}

fn open(cli: &Cli, timeout: Duration) -> Result<Session> {
    let chunks = load_memories(memory_dir(cli)?)?;
    let spec = cli.embedder.clone().context("--embedder is required")?;
    let embedder = Embedder::with_timeout(spec, timeout);
    let identity = embedder
        .cache_identity()
        .context("ask the server for its model")?;
    let cache = VectorCache::load(cache_path(cli)?, &identity)?;
    Ok(Session {
        embedder,
        chunks,
        cache,
    })
}

struct Recalled {
    context: String,
    entry: Entry,
}

fn recall(cli: &Cli, query: &str, selection: Selection, timeout: Duration) -> Result<Recalled> {
    let mut session = open(cli, timeout)?;
    let stats = session
        .embedder
        .load_cached(&session.chunks, &session.cache);
    if stats.missing > 0 {
        warn!(
            missing = stats.missing,
            "memories not in the vector cache; run the `index` subcommand"
        );
    }
    let scored = session.embedder.search(query)?;
    let hits: Vec<_> = select(&scored, selection.min_score, selection.top)
        .into_iter()
        .filter_map(|(id, score)| {
            let chunk = session.chunks.iter().find(|c| c.id == id)?;
            Some(hit(chunk, score))
        })
        .collect();
    let inject = selection.inject.into_inject(selection.body_score);
    let context = render_context_with(memory_dir(cli)?, &hits, inject, selection.body_chars);
    let entry = Entry {
        at: now_iso8601(),
        kind: "memory".to_owned(),
        best_score: scored.first().map(|(_, score)| *score),
        matches: hits.len(),
        full: full_count(&hits, inject),
        tokens: context.len() / BYTES_PER_TOKEN,
        failed: false,
    };
    Ok(Recalled { context, entry })
}

fn run(cli: &Cli) -> Result<()> {
    match &cli.command {
        Command::Index => {
            let mut session = open(cli, INDEX_TIMEOUT)?;
            let stats = session
                .embedder
                .index_cached(&session.chunks, &mut session.cache)?;
            session.cache.save(cache_path(cli)?)?;
            info!(
                embedded = stats.embedded,
                reused = stats.reused,
                total = session.cache.len(),
                "index updated"
            );
        }
        Command::Query { text, selection } => {
            let mut session = open(cli, QUERY_TIMEOUT)?;
            session
                .embedder
                .load_cached(&session.chunks, &session.cache);
            for (id, score) in select(
                &session.embedder.search(text)?,
                selection.min_score,
                selection.top,
            ) {
                println!("{score:.3}  {id}");
            }
        }
        Command::Catalogue { write } => {
            let names: Vec<String> = load_memories(memory_dir(cli)?)?
                .into_iter()
                .map(|chunk| chunk.id)
                .collect();
            let text = render_catalogue(&names);
            match write {
                Some(path) => {
                    let wrote = write_if_changed(path, &text)
                        .with_context(|| format!("write {}", path.display()))?;
                    info!(path = %path.display(), wrote, memories = names.len(), "catalogue");
                }
                None => print!("{text}"),
            }
        }
        Command::Hook { selection, log } => {
            let mut stdin = String::new();
            std::io::stdin()
                .read_to_string(&mut stdin)
                .context("read hook payload from stdin")?;
            let Some(prompt) = prompt_from_hook_input(&stdin) else {
                return Ok(());
            };
            let recalled = match recall(cli, &prompt, *selection, HOOK_TIMEOUT) {
                Ok(recalled) => recalled,
                Err(error) => {
                    if let Some(path) = log {
                        append_failure(path, "memory");
                    }
                    return Err(error);
                }
            };
            if let Some(path) = log {
                if let Err(error) = append(path, &recalled.entry) {
                    warn!(path = %path.display(), %error, "could not write the recall log");
                }
            }
            if let Some(output) = hook_output(&recalled.context) {
                println!("{output}");
            }
        }
        Command::LogSummary { path } => {
            let text = std::fs::read_to_string(path)
                .with_context(|| format!("read {}", path.display()))?;
            print!("{}", render_summary(&summarise(&parse_log(&text))));
        }
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
        .with_ansi(false)
        .init();
    let cli = Cli::parse();
    match run(&cli) {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) if matches!(cli.command, Command::Hook { .. }) => {
            warn!(error = %format!("{error:#}"), "memory recall skipped");
            ExitCode::SUCCESS
        }
        Err(error) => {
            eprintln!("error: {error:#}");
            ExitCode::FAILURE
        }
    }
}
