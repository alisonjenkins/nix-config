//! Which way of embedding a memory, which query prompt and which fusion finds
//! the right memory best? Tuned on the dev queries and half the negatives, judged
//! on the held-out queries and the other half.
use std::collections::HashSet;
use std::fs;
use std::path::PathBuf;
use std::str::FromStr;
use std::time::Duration;

use anyhow::{Context, Result};
use clap::Parser;
use retrieval_eval::bench::{gate_row, summarise, Case, GateRow, Kind, Summary};
use retrieval_eval::bm25::Bm25;
use retrieval_eval::corpus::{load_memories_view, MemoryView};
use retrieval_eval::embed::{Embedder, EmbedderSpec, Preset};
use retrieval_eval::experiment::{collapse_max, combine, pick_threshold, zscore, Combine};
use retrieval_eval::llm_run::FactsFile;
use retrieval_eval::metrics::{first_hit_rank, mrr, recall_at};
use retrieval_eval::queries;
use retrieval_eval::retriever::Retriever;
use retrieval_eval::vector_cache::VectorCache;
use serde::Serialize;

const EMBED_TIMEOUT: Duration = Duration::from_secs(300);
/// A missed memory costs more than a spurious injection: weight false
/// injections at half a miss when choosing a threshold.
const FALSE_INJECTION_WEIGHT: f64 = 0.5;
const TOP: usize = 3;

#[derive(Parser)]
#[command(about = "Compare ways of embedding memories, query prompts and score fusions")]
struct Cli {
    #[arg(long)]
    memory_dir: PathBuf,
    /// Base URL of the `llama-server --embeddings` endpoint.
    #[arg(long)]
    url: String,
    #[arg(long, default_value_t = 256)]
    dims: usize,
    /// Where document vectors are cached between runs.
    #[arg(long)]
    cache_dir: PathBuf,
    #[arg(long)]
    dev: PathBuf,
    /// Facts-format file (q, expect, facts) of held-out queries.
    #[arg(long)]
    heldout: PathBuf,
    #[arg(long)]
    negatives: PathBuf,
    #[arg(long, default_value_t = 600)]
    chunk_chars: usize,
    /// Embed and cache the documents, then stop. A server that has bulk-embedded
    /// hundreds of documents has been seen to answer single queries 200 times
    /// slower, so restart it before scoring.
    #[arg(long)]
    index_only: bool,
    #[arg(long)]
    json: Option<PathBuf>,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Set {
    Dev,
    Held,
}

struct Prompt {
    kind: Kind,
    set: Set,
    expect: HashSet<String>,
    /// File-level scores, one list per signal.
    signals: Vec<Vec<(String, f64)>>,
    bm25: Vec<(String, f64)>,
}

struct Signal {
    name: &'static str,
    tag: &'static str,
    view: MemoryView,
    preset: Preset,
}

#[derive(Clone, Copy)]
enum Member {
    Signal(usize),
    Bm25,
}

struct Strategy {
    name: String,
    members: Vec<Member>,
    how: Combine,
    zscored: bool,
}

#[derive(Debug, Serialize)]
struct Ranking {
    r1: f64,
    r3: f64,
    r5: f64,
    mrr: f64,
}

/// Top-1 scores, by whether the prompt has a right answer in memory.
#[derive(Debug, Serialize)]
struct Distribution {
    dev_relevant: Option<Summary>,
    held_relevant: Option<Summary>,
    dev_negative: Option<Summary>,
    held_negative: Option<Summary>,
}

#[derive(Debug, Serialize)]
struct Row {
    strategy: String,
    dev: Ranking,
    held: Ranking,
    threshold: f64,
    dev_gate: GateRow,
    held_gate: GateRow,
    top1: Distribution,
}

fn signals(chunk_chars: usize) -> Vec<Signal> {
    let mut out = Vec::new();
    for (view, tag, prefix) in [
        (MemoryView::Full, "full", "full"),
        (MemoryView::Description, "desc", "desc"),
        (MemoryView::Chunks(chunk_chars), "chunks", "chunk"),
    ] {
        for (preset, suffix) in [
            (Preset::Gemma, ""),
            (Preset::GemmaQa, "-qa"),
            (Preset::GemmaSim, "-sim"),
        ] {
            // Chunk sentence-similarity vectors add nothing the others lack; skip them.
            if prefix == "chunk" && preset == Preset::GemmaSim {
                continue;
            }
            let name: &'static str = Box::leak(format!("{prefix}{suffix}").into_boxed_str());
            out.push(Signal {
                name,
                tag,
                view,
                preset,
            });
        }
    }
    out
}

fn strategies(signals: &[Signal]) -> Vec<Strategy> {
    let find = |name: &str| {
        signals
            .iter()
            .position(|s| s.name == name)
            .map(Member::Signal)
    };
    let mut out = Vec::new();
    for (i, s) in signals.iter().enumerate() {
        out.push(Strategy {
            name: s.name.to_owned(),
            members: vec![Member::Signal(i)],
            how: Combine::Mean,
            zscored: false,
        });
    }
    out.push(Strategy {
        name: "bm25".to_owned(),
        members: vec![Member::Bm25],
        how: Combine::Mean,
        zscored: false,
    });
    let fuse = |name: &str, names: &[&str], how: Combine, bm25: bool| {
        let mut members: Vec<Member> = names.iter().filter_map(|n| find(n)).collect();
        if bm25 {
            members.push(Member::Bm25);
        }
        Strategy {
            name: name.to_owned(),
            members,
            how,
            zscored: true,
        }
    };
    out.extend([
        fuse("full+desc", &["full", "desc"], Combine::Mean, false),
        fuse("full+chunk", &["full", "chunk"], Combine::Mean, false),
        fuse("desc+chunk", &["desc", "chunk"], Combine::Mean, false),
        fuse(
            "full+desc+chunk",
            &["full", "desc", "chunk"],
            Combine::Mean,
            false,
        ),
        fuse(
            "qa: full+desc",
            &["full-qa", "desc-qa"],
            Combine::Mean,
            false,
        ),
        fuse(
            "qa: full+desc+chunk",
            &["full-qa", "desc-qa", "chunk-qa"],
            Combine::Mean,
            false,
        ),
        fuse(
            "full+desc+desc-sim",
            &["full", "desc", "desc-sim"],
            Combine::Mean,
            false,
        ),
        fuse(
            "max(full,desc,chunk)",
            &["full", "desc", "chunk"],
            Combine::Max,
            false,
        ),
        fuse(
            "full+desc+chunk+bm25(.5)",
            &["full", "desc", "chunk"],
            Combine::Weighted(vec![1.0, 1.0, 1.0, 0.5]),
            true,
        ),
        fuse(
            "full+desc+bm25(.5)",
            &["full", "desc"],
            Combine::Weighted(vec![1.0, 1.0, 0.5]),
            true,
        ),
        fuse(
            "full+desc+chunk+bm25(1)",
            &["full", "desc", "chunk"],
            Combine::Weighted(vec![1.0, 1.0, 1.0, 1.0]),
            true,
        ),
    ]);
    out
}

fn scores_of(strategy: &Strategy, prompt: &Prompt) -> Vec<(String, f64)> {
    let lists: Vec<Vec<(String, f64)>> = strategy
        .members
        .iter()
        .map(|member| {
            let list = match member {
                Member::Signal(i) => prompt.signals.get(*i).cloned().unwrap_or_default(),
                Member::Bm25 => prompt.bm25.clone(),
            };
            if strategy.zscored {
                zscore(&list)
            } else {
                list
            }
        })
        .collect();
    combine(&lists, &strategy.how)
}

fn ranking(strategy: &Strategy, prompts: &[Prompt], set: Set) -> Ranking {
    let ranks: Vec<Option<usize>> = prompts
        .iter()
        .filter(|p| p.set == set && p.kind == Kind::Relevant)
        .map(|p| {
            let ids: Vec<String> = scores_of(strategy, p)
                .into_iter()
                .map(|(id, _)| id)
                .collect();
            first_hit_rank(&ids, &p.expect)
        })
        .collect();
    Ranking {
        r1: recall_at(&ranks, 1),
        r3: recall_at(&ranks, 3),
        r5: recall_at(&ranks, 5),
        mrr: mrr(&ranks),
    }
}

fn cases(strategy: &Strategy, prompts: &[Prompt], set: Set) -> Vec<Case> {
    prompts
        .iter()
        .filter(|p| p.set == set)
        .map(|p| Case {
            kind: p.kind,
            expect: p.expect.clone(),
            scored: scores_of(strategy, p),
        })
        .collect()
}

fn top1_summary(cases: &[Case], relevant: bool) -> Option<Summary> {
    let scores: Vec<f64> = cases
        .iter()
        .filter(|c| (c.kind == Kind::Relevant) == relevant)
        .filter_map(|c| c.scored.first().map(|(_, s)| *s))
        .collect();
    summarise(&scores)
}

fn evaluate(strategy: &Strategy, prompts: &[Prompt]) -> Row {
    let dev_cases = cases(strategy, prompts, Set::Dev);
    let held_cases = cases(strategy, prompts, Set::Held);
    let threshold = pick_threshold(&dev_cases, TOP, FALSE_INJECTION_WEIGHT);
    Row {
        strategy: strategy.name.clone(),
        dev: ranking(strategy, prompts, Set::Dev),
        held: ranking(strategy, prompts, Set::Held),
        threshold,
        dev_gate: gate_row(&dev_cases, threshold, TOP, &|_| 0.0),
        held_gate: gate_row(&held_cases, threshold, TOP, &|_| 0.0),
        top1: Distribution {
            dev_relevant: top1_summary(&dev_cases, true),
            held_relevant: top1_summary(&held_cases, true),
            dev_negative: top1_summary(&dev_cases, false),
            held_negative: top1_summary(&held_cases, false),
        },
    }
}

/// Fixed thresholds on the raw-score strategies, dev and held-out side by side.
fn print_sweep(strategies: &[Strategy], prompts: &[Prompt]) {
    println!("\n| strategy | threshold | dev: right memory injected, false inj. off/adj | held: right memory injected, false inj. off/adj | held mean memories injected |");
    println!("|---|---|---|---|---|");
    for name in ["full", "chunk", "chunk-qa", "desc-qa"] {
        let Some(strategy) = strategies.iter().find(|s| s.name == name) else {
            continue;
        };
        let dev = cases(strategy, prompts, Set::Dev);
        let held = cases(strategy, prompts, Set::Held);
        for step in 33..=42_u32 {
            let threshold = f64::from(step) * 0.02;
            let d = gate_row(&dev, threshold, TOP, &|_| 0.0);
            let h = gate_row(&held, threshold, TOP, &|_| 0.0);
            println!(
                "| {name} | {threshold:.2} | {}, {}/{} | {}, {}/{} | {:.2} |",
                pct(d.recall),
                pct(d.false_injection_offtopic),
                pct(d.false_injection_adjacent),
                pct(h.recall),
                pct(h.false_injection_offtopic),
                pct(h.false_injection_adjacent),
                h.mean_injected,
            );
        }
    }
}

fn print_distributions(rows: &[Row]) {
    println!("\n| strategy | right memory, dev: min / median | right memory, held: min / median | no memory, dev: median / p95 / max | no memory, held: median / p95 / max |");
    println!("|---|---|---|---|---|");
    let low_med = |s: &Option<Summary>| {
        s.as_ref().map_or_else(
            || "-".to_owned(),
            |s| format!("{:.2} / {:.2}", s.min, s.p50),
        )
    };
    let med_hi = |s: &Option<Summary>| {
        s.as_ref().map_or_else(
            || "-".to_owned(),
            |s| format!("{:.2} / {:.2} / {:.2}", s.p50, s.p95, s.max),
        )
    };
    for r in rows {
        println!(
            "| {} | {} | {} | {} | {} |",
            r.strategy,
            low_med(&r.top1.dev_relevant),
            low_med(&r.top1.held_relevant),
            med_hi(&r.top1.dev_negative),
            med_hi(&r.top1.held_negative),
        );
    }
}

fn pct(x: f64) -> String {
    format!("{:.0}", x * 100.0)
}

fn print_rows(rows: &[Row]) {
    println!("| strategy | dev R@1/3/5 | dev MRR | held R@1/3/5 | held MRR | threshold | dev gate: recall, false inj. off/adj | held gate: recall, false inj. off/adj, precision |");
    println!("|---|---|---|---|---|---|---|---|");
    for r in rows {
        println!(
            "| {} | {}/{}/{} | {:.3} | {}/{}/{} | {:.3} | {:.2} | {}, {}/{} | {}, {}/{}, {} |",
            r.strategy,
            pct(r.dev.r1),
            pct(r.dev.r3),
            pct(r.dev.r5),
            r.dev.mrr,
            pct(r.held.r1),
            pct(r.held.r3),
            pct(r.held.r5),
            r.held.mrr,
            r.threshold,
            pct(r.dev_gate.recall),
            pct(r.dev_gate.false_injection_offtopic),
            pct(r.dev_gate.false_injection_adjacent),
            pct(r.held_gate.recall),
            pct(r.held_gate.false_injection_offtopic),
            pct(r.held_gate.false_injection_adjacent),
            r.held_gate.precision.map_or_else(|| "n/a".to_owned(), pct),
        );
    }
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    fs::create_dir_all(&cli.cache_dir)?;
    let signals = signals(cli.chunk_chars);

    // Embed every view once; presets that wrap documents alike share a cache file.
    let mut embedders = Vec::new();
    for signal in &signals {
        let chunks = load_memories_view(&cli.memory_dir, signal.view)?;
        let spec = EmbedderSpec::from_str(&format!("x=none@{}", cli.url))?;
        let mut embedder = Embedder::with_timeout(
            EmbedderSpec {
                preset: signal.preset,
                dims: Some(cli.dims),
                ..spec
            },
            EMBED_TIMEOUT,
        );
        let identity = embedder
            .cache_identity()
            .context("ask the server for its model")?;
        let cache_path = cli.cache_dir.join(format!(
            "{}-{}-{}.json",
            signal.tag,
            signal.preset.doc_format(),
            cli.dims
        ));
        let mut cache = VectorCache::load(&cache_path, &identity)?;
        let stats = embedder.index_cached(&chunks, &mut cache)?;
        cache.save(&cache_path)?;
        eprintln!(
            "{:<10} {} chunks, embedded {}, reused {}",
            signal.name,
            chunks.len(),
            stats.embedded,
            stats.reused
        );
        embedders.push(embedder);
    }
    if cli.index_only {
        return Ok(());
    }
    let mut bm25 = Bm25::new();
    bm25.index(&load_memories_view(&cli.memory_dir, MemoryView::Full)?)?;

    // Prompts: dev and held-out relevant queries, negatives split by parity.
    let mut prompts: Vec<Prompt> = Vec::new();
    let held_raw = fs::read_to_string(&cli.heldout).context("read held-out queries")?;
    let held: FactsFile = serde_json::from_str(&held_raw).context("parse held-out queries")?;
    let mut raw: Vec<(Kind, Set, String, Vec<String>)> = Vec::new();
    for q in queries::load(&cli.dev)? {
        raw.push((Kind::Relevant, Set::Dev, q.q, q.expect));
    }
    for item in held.queries {
        raw.push((Kind::Relevant, Set::Held, item.q, item.expect));
    }
    let negatives = queries::load_negatives(&cli.negatives)?;
    for (kind, list) in [
        (Kind::Offtopic, negatives.offtopic),
        (Kind::Adjacent, negatives.adjacent),
    ] {
        for (i, text) in list.into_iter().enumerate() {
            let set = if i % 2 == 0 { Set::Dev } else { Set::Held };
            raw.push((kind, set, text, Vec::new()));
        }
    }
    eprintln!("scoring {} prompts", raw.len());
    for (kind, set, text, expect) in raw {
        let mut per_signal = Vec::new();
        for embedder in &embedders {
            per_signal.push(collapse_max(&embedder.search(&text)?));
        }
        prompts.push(Prompt {
            kind,
            set,
            expect: expect.into_iter().collect(),
            bm25: bm25.score_all(&text)?,
            signals: per_signal,
        });
    }

    let rows: Vec<Row> = strategies(&signals)
        .iter()
        .map(|s| evaluate(s, &prompts))
        .collect();
    print_rows(&rows);
    print_distributions(&rows);
    print_sweep(&strategies(&signals), &prompts);
    if let Some(path) = &cli.json {
        fs::write(path, serde_json::to_string_pretty(&rows)?)
            .with_context(|| format!("write {}", path.display()))?;
    }
    Ok(())
}
