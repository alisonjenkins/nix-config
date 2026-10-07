use std::collections::HashSet;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::time::{Duration, Instant};

use anyhow::{Context, Result};
use clap::{Args, Parser, Subcommand};
use retrieval_eval::bench::{gate_row, Case, Kind};
use retrieval_eval::corpus::{load_skill_sections, skill_names, Chunk};
use retrieval_eval::embed::{Embedder, EmbedderSpec};
use retrieval_eval::queries;
use retrieval_eval::recall::{
    blocked_message, hook_output, keyword_fallback, prompt_from_hook_input, render_sections,
    retry_until, select, Blocked, Hit, OnUnavailable,
};
use retrieval_eval::recall_log::{
    append_failure, append_rotating, now_iso8601, Entry, DEFAULT_ROTATION,
};
use retrieval_eval::vector_cache::VectorCache;
use tracing::{info, warn};

/// The hook runs on every prompt: a recall that takes longer than this costs
/// more than it gives, so give up and inject nothing.
const HOOK_TIMEOUT: Duration = Duration::from_secs(3);
/// Claude Code treats exit code 2 from a UserPromptSubmit hook as "block this
/// prompt" and shows stderr to the user.
const BLOCK_EXIT_CODE: u8 = 2;
/// The reindex restarts the server, which refuses connections for about a second;
/// waiting this long rides that out before falling back to keyword matches.
const HOOK_RETRY_BUDGET: Duration = Duration::from_millis(1500);
const HOOK_RETRY_PAUSE: Duration = Duration::from_millis(150);
const QUERY_TIMEOUT: Duration = Duration::from_secs(30);
const INDEX_TIMEOUT: Duration = Duration::from_secs(300);
const DEFAULT_TOP: usize = 3;
/// About 750 tokens per section: most sections fit whole.
const DEFAULT_SECTION_CHARS: usize = 3000;
/// Measured 2026-10-07 with EmbeddingGemma 2 at 256 dims over 656 sections and
/// the 20 skills queries (bench/results/skill-calibrate-top3.md): at 0.74 the
/// right section is among the top 3 for 70% of queries, 20% of off-topic prompts
/// get an injection, and a prompt gets 240 tokens on average. Lower floors buy
/// recall at 40 to 90% false injections; skill scores sit higher and overlap more
/// than memory scores do. Scores are model- and dims-specific.
const DEFAULT_MIN_SCORE: f64 = 0.74;
const BYTES_PER_TOKEN: usize = 4;

#[derive(Parser)]
#[command(about = "Semantic recall over Claude skill sections, as a UserPromptSubmit hook")]
struct Cli {
    /// Directory holding one folder per skill, e.g. ~/.claude/skills.
    #[arg(long)]
    skills_root: PathBuf,
    /// NAME=PRESET@BASE_URL[#DIMS] of a `llama-server --embeddings` endpoint.
    #[arg(long)]
    embedder: EmbedderSpec,
    /// Where section vectors are cached between runs.
    #[arg(long)]
    cache: PathBuf,
    #[command(subcommand)]
    command: Command,
}

#[derive(Args, Clone, Copy)]
struct Selection {
    /// Most sections injected per prompt.
    #[arg(long, default_value_t = DEFAULT_TOP)]
    top: usize,
    /// Drop sections scoring below this cosine similarity.
    #[arg(long, default_value_t = DEFAULT_MIN_SCORE)]
    min_score: f64,
    /// Longest section injected, in characters.
    #[arg(long, default_value_t = DEFAULT_SECTION_CHARS)]
    section_chars: usize,
}

#[derive(Subcommand)]
enum Command {
    /// Embed new or edited skill sections into the cache (slow the first time).
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
        /// What to do when the skill sections cannot be retrieved.
        #[arg(long, value_enum, default_value_t = OnUnavailable::Block)]
        on_unavailable: OnUnavailable,
    },
    /// Sweep the score threshold over a query set: recall and false injections.
    Calibrate {
        /// Query file whose `expect` lists name the right sections.
        #[arg(long)]
        relevant: PathBuf,
        /// JSON with an `offtopic` list; prompts no skill should answer.
        #[arg(long)]
        negatives: PathBuf,
        #[arg(long, default_value_t = DEFAULT_TOP)]
        top: usize,
    },
}

struct Session {
    embedder: Embedder,
    chunks: Vec<Chunk>,
    cache: VectorCache,
}

fn open(cli: &Cli, timeout: Duration) -> Result<Session> {
    let names = skill_names(&cli.skills_root)?;
    let chunks = load_skill_sections(&cli.skills_root, &names)?;
    let embedder = Embedder::with_timeout(cli.embedder.clone(), timeout);
    let identity = embedder
        .cache_identity()
        .context("ask the server for its model")?;
    let cache = VectorCache::load(&cli.cache, &identity)?;
    Ok(Session {
        embedder,
        chunks,
        cache,
    })
}

fn load_vectors(session: &mut Session) {
    let stats = session
        .embedder
        .load_cached(&session.chunks, &session.cache);
    if stats.missing > 0 {
        warn!(
            missing = stats.missing,
            "skill sections not in the vector cache; run the `index` subcommand"
        );
    }
}

struct Recalled {
    context: String,
    entry: Entry,
}

/// Every skill section scored against `query` by the embedding server, best first.
fn semantic_scores(
    cli: &Cli,
    chunks: &[Chunk],
    query: &str,
    timeout: Duration,
) -> Result<Vec<(String, f64)>> {
    let mut embedder = Embedder::with_timeout(cli.embedder.clone(), timeout);
    let identity = embedder
        .cache_identity()
        .context("ask the server for its model")?;
    let cache = VectorCache::load(&cli.cache, &identity)?;
    let stats = embedder.load_cached(chunks, &cache);
    if stats.missing > 0 {
        warn!(
            missing = stats.missing,
            "skill sections not in the vector cache; run the `index` subcommand"
        );
    }
    Ok(embedder.search(query)?)
}

/// A hook that cannot reach the server (restarting, crashed, not started yet) still
/// gives the prompt the sections that share words with it, so it is not left
/// without the skills' guard rails. In that case it over-injects rather than under.
fn recall(
    cli: &Cli,
    query: &str,
    selection: Selection,
    on_unavailable: OnUnavailable,
    timeout: Duration,
) -> Result<Recalled> {
    let names = skill_names(&cli.skills_root)?;
    let chunks = load_skill_sections(&cli.skills_root, &names)?;
    let mut embed_ms = None;
    let semantic = retry_until(HOOK_RETRY_BUDGET, HOOK_RETRY_PAUSE, || {
        let started = Instant::now();
        let scored = semantic_scores(cli, &chunks, query, timeout);
        if scored.is_ok() {
            embed_ms = Some(started.elapsed().as_secs_f64() * 1000.0);
        }
        scored
    });
    let (scored, selected, fallback) = match semantic {
        Ok(scored) => {
            let selected = select(&scored, selection.min_score, selection.top);
            (scored, selected, false)
        }
        Err(error) => match on_unavailable {
            OnUnavailable::Block => return Err(error.context("embedding server unavailable")),
            OnUnavailable::Allow => {
                warn!(error = %format!("{error:#}"), "embedding server unavailable; injecting nothing");
                return Ok(Recalled {
                    context: String::new(),
                    entry: Entry::failure("skills", &now_iso8601()),
                });
            }
            OnUnavailable::Keyword => {
                warn!(error = %format!("{error:#}"), "embedding server unavailable; using keyword matches");
                let keyword = keyword_fallback(&chunks, query, selection.top);
                (keyword.clone(), keyword, true)
            }
        },
    };
    let hits: Vec<Hit> = selected
        .into_iter()
        .filter_map(|(id, score)| {
            let chunk = chunks.iter().find(|c| c.id == id)?;
            Some(Hit {
                id: chunk.id.clone(),
                description: String::new(),
                body: chunk.text.clone(),
                score,
            })
        })
        .collect();
    let context = render_sections(&cli.skills_root, &hits, selection.section_chars);
    let entry = Entry {
        at: now_iso8601(),
        kind: "skills".to_owned(),
        best_score: scored.first().map(|(_, score)| *score),
        matches: hits.len(),
        // Sections are always injected as text, never as a pointer to read.
        full: hits.len(),
        tokens: context.len() / BYTES_PER_TOKEN,
        failed: false,
        fallback,
        duration_ms: None,
        embed_ms,
    };
    Ok(Recalled { context, entry })
}

fn tokens_of(chunks: &[Chunk], id: &str, section_chars: usize) -> f64 {
    let chars = chunks
        .iter()
        .find(|c| c.id == id)
        .map_or(0, |c| c.text.chars().count().min(section_chars));
    chars as f64 / BYTES_PER_TOKEN as f64
}

fn pct(x: f64) -> String {
    format!("{:.0}%", x * 100.0)
}

fn calibrate(cli: &Cli, relevant: &Path, negatives: &Path, top: usize) -> Result<()> {
    let mut session = open(cli, QUERY_TIMEOUT)?;
    load_vectors(&mut session);
    let mut cases = Vec::new();
    for query in queries::load(relevant)? {
        cases.push(Case {
            kind: Kind::Relevant,
            expect: query.expect.iter().cloned().collect::<HashSet<_>>(),
            scored: session.embedder.search(&query.q)?,
        });
    }
    for text in queries::load_negatives(negatives)?.offtopic {
        cases.push(Case {
            kind: Kind::Offtopic,
            expect: HashSet::new(),
            scored: session.embedder.search(&text)?,
        });
    }
    let tokens = |id: &str| tokens_of(&session.chunks, id, DEFAULT_SECTION_CHARS);
    println!("| threshold | recall | top-1 right | false inj. off-topic | precision | mean injected | mean tokens/prompt |");
    println!("|---|---|---|---|---|---|---|");
    for step in (60..=90).step_by(2) {
        let row = gate_row(&cases, f64::from(step) / 100.0, top, &tokens);
        println!(
            "| {:.2} | {} | {} | {} | {} | {:.2} | {:.0} |",
            row.threshold,
            pct(row.recall),
            pct(row.top1_correct),
            pct(row.false_injection_offtopic),
            row.precision.map_or_else(|| "n/a".to_owned(), pct),
            row.mean_injected,
            row.mean_tokens
        );
    }
    Ok(())
}

fn run(cli: &Cli) -> Result<()> {
    match &cli.command {
        Command::Index => {
            let mut session = open(cli, INDEX_TIMEOUT)?;
            let stats = session
                .embedder
                .index_cached(&session.chunks, &mut session.cache)?;
            session.cache.save(&cli.cache)?;
            info!(
                embedded = stats.embedded,
                reused = stats.reused,
                total = session.cache.len(),
                "index updated"
            );
        }
        Command::Query { text, selection } => {
            let mut session = open(cli, QUERY_TIMEOUT)?;
            load_vectors(&mut session);
            for (id, score) in select(
                &session.embedder.search(text)?,
                selection.min_score,
                selection.top,
            ) {
                println!("{score:.3}  {id}");
            }
        }
        Command::Hook {
            selection,
            log,
            on_unavailable,
        } => {
            let mut stdin = String::new();
            std::io::stdin()
                .read_to_string(&mut stdin)
                .context("read hook payload from stdin")?;
            let Some(prompt) = prompt_from_hook_input(&stdin) else {
                return Ok(());
            };
            let started = Instant::now();
            let mut recalled = match recall(cli, &prompt, *selection, *on_unavailable, HOOK_TIMEOUT)
            {
                Ok(recalled) => recalled,
                Err(error) => {
                    if let Some(path) = log {
                        append_failure(path, "skills");
                    }
                    if *on_unavailable == OnUnavailable::Block {
                        return Err(Blocked(blocked_message(
                            "skill-recall",
                            &format!("{error:#}"),
                        ))
                        .into());
                    }
                    return Err(error);
                }
            };
            recalled.entry.duration_ms = Some(started.elapsed().as_secs_f64() * 1000.0);
            if let Some(path) = log {
                if let Err(error) = append_rotating(path, &recalled.entry, DEFAULT_ROTATION) {
                    warn!(path = %path.display(), %error, "could not write the recall log");
                }
            }
            if let Some(output) = hook_output(&recalled.context) {
                println!("{output}");
            }
        }
        Command::Calibrate {
            relevant,
            negatives,
            top,
        } => calibrate(cli, relevant, negatives, *top)?,
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
        Err(error) if error.downcast_ref::<Blocked>().is_some() => {
            eprintln!("{error}");
            ExitCode::from(BLOCK_EXIT_CODE)
        }
        Err(error) if matches!(cli.command, Command::Hook { .. }) => {
            warn!(error = %format!("{error:#}"), "skill recall skipped");
            ExitCode::SUCCESS
        }
        Err(error) => {
            eprintln!("error: {error:#}");
            ExitCode::FAILURE
        }
    }
}
