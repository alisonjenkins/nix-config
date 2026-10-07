use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command as Process, Stdio};
use std::str::FromStr;
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};
use clap::{Parser, Subcommand};
use retrieval_eval::bench::{
    approx_tokens, gate_row, proc_cpu_ticks, proc_status_kb, summarise, synthetic_vectors, Case,
    GateRow, Kind, Summary, CONTEXT_HEADER_TOKENS,
};
use retrieval_eval::corpus::{load_memories, Chunk};
use retrieval_eval::embed::{cosine_scores, Embedder, EmbedderSpec};
use retrieval_eval::queries;
use retrieval_eval::retriever::rank_scored;
use retrieval_eval::vector_cache::{fnv1a, VectorCache};
use serde::Serialize;

/// Linux USER_HZ: /proc reports CPU time in 1/100 s ticks.
const TICK_MS: f64 = 10.0;
const SERVER_TIMEOUT: Duration = Duration::from_secs(300);

#[derive(Parser)]
#[command(about = "Benchmarks for memory-recall: gate quality, latency, index cost, scaling")]
struct Cli {
    /// Directory of memory `*.md` files.
    #[arg(long)]
    memory_dir: PathBuf,
    /// NAME=PRESET@BASE_URL[#DIMS] of a `llama-server --embeddings` endpoint.
    #[arg(long)]
    embedder: String,
    /// Vector cache written by `memory-recall index`.
    #[arg(long)]
    cache: PathBuf,
    /// Also write the results as JSON here.
    #[arg(long)]
    json: Option<PathBuf>,
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Sweep the injection threshold: recall, false injections, precision, tokens.
    Gate {
        /// Query file whose `expect` lists name the right memories.
        #[arg(long)]
        relevant: PathBuf,
        /// JSON with `offtopic` and `adjacent` prompt lists.
        #[arg(long)]
        negatives: PathBuf,
        #[arg(long, default_value_t = 3)]
        top: usize,
        /// Threshold the hook ships with, marked in the table.
        #[arg(long, default_value_t = 0.74)]
        selected: f64,
    },
    /// Time the real hook process end to end, and sample the embedding server.
    Latency {
        /// The `memory-recall` binary to spawn.
        #[arg(long)]
        hook_bin: PathBuf,
        #[arg(long)]
        relevant: PathBuf,
        #[arg(long)]
        negatives: PathBuf,
        #[arg(long, default_value_t = 200)]
        runs: usize,
        #[arg(long, default_value_t = 10)]
        warmup: usize,
        /// PID of the llama-server, to report its memory and CPU.
        #[arg(long)]
        server_pid: Option<u32>,
    },
    /// Cold, no-op and one-file-changed indexing, on a temporary copy of the memories.
    Index,
    /// Search and cache-load time at synthetic corpus sizes.
    Scale {
        #[arg(long, value_delimiter = ',', default_value = "83,1000,10000,100000")]
        sizes: Vec<usize>,
        #[arg(long, default_value_t = 256)]
        dims: usize,
    },
}

#[derive(Serialize)]
struct GateReport {
    sweep: Vec<GateRow>,
    top1_score_relevant: Option<Summary>,
    top1_score_offtopic: Option<Summary>,
    top1_score_adjacent: Option<Summary>,
    index_tokens: f64,
    all_memory_tokens: f64,
    selected: Option<GateRow>,
    /// Prompts after which the hook has cost as many tokens as the index it replaces.
    break_even_prompts: Option<f64>,
}

#[derive(Serialize)]
struct LatencyReport {
    runs: usize,
    all_ms: Option<Summary>,
    injected_ms: Option<Summary>,
    not_injected_ms: Option<Summary>,
    relevant_ms: Option<Summary>,
    offtopic_ms: Option<Summary>,
    adjacent_ms: Option<Summary>,
    hook_peak_rss_kb: Option<u64>,
    server_rss_kb_before: Option<u64>,
    server_rss_kb_after: Option<u64>,
    server_peak_rss_kb: Option<u64>,
    server_cpu_ms_per_call: Option<f64>,
    server_idle_cpu_ms_per_s: Option<f64>,
}

#[derive(Serialize)]
struct IndexReport {
    chunks: usize,
    cold_secs: f64,
    cold_ms_per_chunk: f64,
    noop_secs: f64,
    incremental_secs: f64,
    incremental_embedded: usize,
    cache_bytes: u64,
    cache_load_ms: f64,
}

#[derive(Serialize)]
struct ScaleRow {
    n: usize,
    search_ms: f64,
    cache_bytes: Option<u64>,
    cache_load_ms: Option<f64>,
}

struct Prompt {
    kind: Kind,
    text: String,
    expect: Vec<String>,
}

fn ms(duration: Duration) -> f64 {
    duration.as_secs_f64() * 1000.0
}

fn open(cli: &Cli, timeout: Duration) -> Result<(Embedder, Vec<Chunk>, VectorCache)> {
    let spec = EmbedderSpec::from_str(&cli.embedder)?;
    let chunks = load_memories(&cli.memory_dir)?;
    let embedder = Embedder::with_timeout(spec, timeout);
    let identity = embedder
        .cache_identity()
        .context("ask the server for its model")?;
    let cache = VectorCache::load(&cli.cache, &identity)?;
    Ok((embedder, chunks, cache))
}

fn load_prompts(relevant: &Path, negatives: &Path) -> Result<Vec<Prompt>> {
    let mut prompts: Vec<Prompt> = queries::load(relevant)?
        .into_iter()
        .map(|q| Prompt {
            kind: Kind::Relevant,
            text: q.q,
            expect: q.expect,
        })
        .collect();
    let raw =
        fs::read_to_string(negatives).with_context(|| format!("read {}", negatives.display()))?;
    let parsed: serde_json::Value =
        serde_json::from_str(&raw).with_context(|| format!("parse {}", negatives.display()))?;
    for (key, kind) in [("offtopic", Kind::Offtopic), ("adjacent", Kind::Adjacent)] {
        let list = parsed
            .get(key)
            .and_then(serde_json::Value::as_array)
            .with_context(|| format!("{} has no `{key}` list", negatives.display()))?;
        for item in list {
            prompts.push(Prompt {
                kind,
                text: item.as_str().context("prompt is not a string")?.to_owned(),
                expect: Vec::new(),
            });
        }
    }
    Ok(prompts)
}

fn print_table_row(cells: &[String]) {
    println!("| {} |", cells.join(" | "));
}

fn pct(x: f64) -> String {
    format!("{:.0}%", x * 100.0)
}

fn run_gate(
    cli: &Cli,
    relevant: &Path,
    negatives: &Path,
    top: usize,
    selected: f64,
) -> Result<GateReport> {
    let (mut embedder, chunks, cache) = open(cli, Duration::from_secs(30))?;
    let stats = embedder.load_cached(&chunks, &cache);
    if stats.missing > 0 {
        bail!(
            "{} memories are not in the cache; run `memory-recall index` first",
            stats.missing
        );
    }

    let prompts = load_prompts(relevant, negatives)?;
    let mut cases = Vec::new();
    for prompt in &prompts {
        cases.push(Case {
            kind: prompt.kind,
            expect: prompt.expect.iter().cloned().collect(),
            scored: embedder.search(&prompt.text)?,
        });
    }

    let line_tokens = |id: &str| {
        let description_len = chunks
            .iter()
            .find(|c| c.id == id)
            .map_or(0, |c| c.text.lines().next().map_or(0, str::len));
        let path_len = cli.memory_dir.join(id).as_os_str().len();
        // "- " + path + " (0.00): " + description + newline
        approx_tokens(path_len.saturating_add(description_len).saturating_add(12))
    };

    let thresholds: Vec<f64> = (50..=90).step_by(2).map(|t| f64::from(t) / 100.0).collect();
    let sweep: Vec<GateRow> = thresholds
        .iter()
        .map(|t| gate_row(&cases, *t, top, &line_tokens))
        .collect();

    println!("| threshold | recall | top-1 right | false inj. off-topic | false inj. adjacent | precision | mean injected | mean tokens/prompt |");
    println!("|---|---|---|---|---|---|---|---|");
    for row in &sweep {
        let mark = if (row.threshold - selected).abs() < 1e-9 {
            " **←**"
        } else {
            ""
        };
        print_table_row(&[
            format!("{:.2}{mark}", row.threshold),
            pct(row.recall),
            pct(row.top1_correct),
            pct(row.false_injection_offtopic),
            pct(row.false_injection_adjacent),
            row.precision.map_or_else(|| "n/a".to_owned(), pct),
            format!("{:.2}", row.mean_injected),
            format!("{:.0}", row.mean_tokens),
        ]);
    }

    let top1 = |kind: Kind| {
        let scores: Vec<f64> = cases
            .iter()
            .filter(|c| c.kind == kind)
            .filter_map(|c| c.scored.first().map(|(_, s)| *s))
            .collect();
        summarise(&scores)
    };

    let index_bytes = fs::metadata(cli.memory_dir.join("MEMORY.md")).map_or(0, |m| m.len());
    let index_tokens = approx_tokens(usize::try_from(index_bytes).unwrap_or(0));
    let all_bytes: usize = chunks.iter().map(|c| c.document().len()).sum();
    let selected_row = sweep
        .iter()
        .find(|r| (r.threshold - selected).abs() < 1e-9)
        .cloned();
    let break_even = selected_row
        .as_ref()
        .filter(|r| r.mean_tokens > 0.0)
        .map(|r| index_tokens / r.mean_tokens);

    Ok(GateReport {
        sweep,
        top1_score_relevant: top1(Kind::Relevant),
        top1_score_offtopic: top1(Kind::Offtopic),
        top1_score_adjacent: top1(Kind::Adjacent),
        index_tokens,
        all_memory_tokens: approx_tokens(all_bytes),
        selected: selected_row,
        break_even_prompts: break_even,
    })
}

fn children_peak_rss_kb() -> Option<u64> {
    let mut usage = std::mem::MaybeUninit::<libc::rusage>::uninit();
    // SAFETY: getrusage fully initialises the struct when it returns 0.
    let rc = unsafe { libc::getrusage(libc::RUSAGE_CHILDREN, usage.as_mut_ptr()) };
    if rc != 0 {
        return None;
    }
    // SAFETY: initialised by the successful call above.
    let usage = unsafe { usage.assume_init() };
    u64::try_from(usage.ru_maxrss).ok()
}

struct ServerSample {
    rss_kb: Option<u64>,
    peak_kb: Option<u64>,
    cpu_ticks: Option<u64>,
}

fn sample_server(pid: u32) -> ServerSample {
    let status = fs::read_to_string(format!("/proc/{pid}/status")).unwrap_or_default();
    let stat = fs::read_to_string(format!("/proc/{pid}/stat")).unwrap_or_default();
    ServerSample {
        rss_kb: proc_status_kb(&status, "VmRSS"),
        peak_kb: proc_status_kb(&status, "VmHWM"),
        cpu_ticks: proc_cpu_ticks(&stat),
    }
}

fn call_hook(bin: &Path, cli: &Cli, prompt: &str) -> Result<(f64, bool)> {
    let payload = serde_json::json!({ "prompt": prompt }).to_string();
    let started = Instant::now();
    let mut child = Process::new(bin)
        .args(["--memory-dir"])
        .arg(&cli.memory_dir)
        .args(["--embedder", &cli.embedder, "--cache"])
        .arg(&cli.cache)
        .arg("hook")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .with_context(|| format!("spawn {}", bin.display()))?;
    child
        .stdin
        .take()
        .context("hook stdin")?
        .write_all(payload.as_bytes())
        .context("write hook payload")?;
    let output = child.wait_with_output().context("wait for hook")?;
    let elapsed = ms(started.elapsed());
    if !output.status.success() {
        bail!("hook exited with {}", output.status);
    }
    Ok((elapsed, !output.stdout.is_empty()))
}

fn run_latency(
    cli: &Cli,
    hook_bin: &Path,
    relevant: &Path,
    negatives: &Path,
    runs: usize,
    warmup: usize,
    server_pid: Option<u32>,
) -> Result<LatencyReport> {
    let prompts = load_prompts(relevant, negatives)?;
    if prompts.is_empty() {
        bail!("no prompts to run");
    }
    for prompt in prompts.iter().cycle().take(warmup) {
        call_hook(hook_bin, cli, &prompt.text)?;
    }

    let before = server_pid.map(sample_server);
    let mut samples: Vec<(Kind, f64, bool)> = Vec::new();
    for prompt in prompts.iter().cycle().take(runs) {
        let (elapsed, injected) = call_hook(hook_bin, cli, &prompt.text)?;
        samples.push((prompt.kind, elapsed, injected));
    }
    let after = server_pid.map(sample_server);

    let idle = server_pid.map(|pid| {
        let start = sample_server(pid).cpu_ticks;
        std::thread::sleep(Duration::from_secs(5));
        let end = sample_server(pid).cpu_ticks;
        match (start, end) {
            (Some(a), Some(b)) => Some(b.saturating_sub(a) as f64 * TICK_MS / 5.0),
            _ => None,
        }
    });

    let pick = |keep: &dyn Fn(&(Kind, f64, bool)) -> bool| {
        let values: Vec<f64> = samples.iter().filter(|s| keep(s)).map(|s| s.1).collect();
        summarise(&values)
    };
    let cpu_per_call = match (
        before.as_ref().and_then(|s| s.cpu_ticks),
        after.as_ref().and_then(|s| s.cpu_ticks),
    ) {
        (Some(a), Some(b)) if runs > 0 => Some(b.saturating_sub(a) as f64 * TICK_MS / runs as f64),
        _ => None,
    };

    Ok(LatencyReport {
        runs,
        all_ms: pick(&|_| true),
        injected_ms: pick(&|s| s.2),
        not_injected_ms: pick(&|s| !s.2),
        relevant_ms: pick(&|s| s.0 == Kind::Relevant),
        offtopic_ms: pick(&|s| s.0 == Kind::Offtopic),
        adjacent_ms: pick(&|s| s.0 == Kind::Adjacent),
        hook_peak_rss_kb: children_peak_rss_kb(),
        server_rss_kb_before: before.as_ref().and_then(|s| s.rss_kb),
        server_rss_kb_after: after.as_ref().and_then(|s| s.rss_kb),
        server_peak_rss_kb: after.as_ref().and_then(|s| s.peak_kb),
        server_cpu_ms_per_call: cpu_per_call,
        server_idle_cpu_ms_per_s: idle.flatten(),
    })
}

fn copy_memories(from: &Path, to: &Path) -> Result<()> {
    for entry in fs::read_dir(from).with_context(|| format!("read {}", from.display()))? {
        let path = entry?.path();
        if path.extension().is_some_and(|e| e == "md") {
            let name = path.file_name().context("file name")?;
            fs::copy(&path, to.join(name))?;
        }
    }
    Ok(())
}

fn run_index(cli: &Cli) -> Result<IndexReport> {
    let spec = EmbedderSpec::from_str(&cli.embedder)?;
    let scratch = tempfile::tempdir().context("create scratch dir")?;
    copy_memories(&cli.memory_dir, scratch.path())?;
    let cache_path = scratch.path().join("bench-cache.json");

    let mut embedder = Embedder::with_timeout(spec, SERVER_TIMEOUT);
    let identity = embedder.cache_identity()?;
    let mut cache = VectorCache::new(&identity);
    let chunks = load_memories(scratch.path())?;

    let started = Instant::now();
    let cold = embedder.index_cached(&chunks, &mut cache)?;
    let cold_secs = started.elapsed().as_secs_f64();
    cache.save(&cache_path)?;

    let started = Instant::now();
    embedder.index_cached(&chunks, &mut cache)?;
    let noop_secs = started.elapsed().as_secs_f64();

    let victim = chunks.first().context("no memories to edit")?;
    let victim_path = scratch.path().join(&victim.id);
    let mut text = fs::read_to_string(&victim_path)?;
    text.push_str("\nBenchmark edit.\n");
    fs::write(&victim_path, text)?;
    let edited = load_memories(scratch.path())?;
    let started = Instant::now();
    let incremental = embedder.index_cached(&edited, &mut cache)?;
    let incremental_secs = started.elapsed().as_secs_f64();

    let started = Instant::now();
    VectorCache::load(&cache_path, &identity)?;
    let cache_load_ms = ms(started.elapsed());

    Ok(IndexReport {
        chunks: chunks.len(),
        cold_secs,
        cold_ms_per_chunk: cold_secs * 1000.0 / cold.embedded.max(1) as f64,
        noop_secs,
        incremental_secs,
        incremental_embedded: incremental.embedded,
        cache_bytes: fs::metadata(&cache_path)?.len(),
        cache_load_ms,
    })
}

/// Median of five timed runs, to smooth scheduler noise on sub-millisecond work.
fn median_ms(mut work: impl FnMut()) -> f64 {
    let mut times: Vec<f64> = (0..5)
        .map(|_| {
            let started = Instant::now();
            work();
            ms(started.elapsed())
        })
        .collect();
    times.sort_by(f64::total_cmp);
    times.get(2).copied().unwrap_or(0.0)
}

/// Writing a 100k-entry JSON cache would take gigabytes; the load path is
/// measured only up to this many vectors.
const MAX_CACHE_BENCH: usize = 20_000;

fn run_scale(sizes: &[usize], dims: usize) -> Result<Vec<ScaleRow>> {
    let scratch = tempfile::tempdir().context("create scratch dir")?;
    let query = synthetic_vectors(1, dims, 9_999)
        .into_iter()
        .next()
        .context("query vector")?;
    let mut rows = Vec::new();
    for &n in sizes {
        let vectors = synthetic_vectors(n, dims, 1);
        let ids: Vec<String> = (0..n).map(|i| format!("doc{i}.md")).collect();
        let search_ms = median_ms(|| {
            let scores = cosine_scores(&vectors, &query);
            std::hint::black_box(rank_scored(&ids, &scores));
        });

        let (cache_bytes, cache_load_ms) = if n <= MAX_CACHE_BENCH {
            let mut cache = VectorCache::new("scale");
            for (id, vector) in ids.iter().zip(&vectors) {
                cache.put(id.clone(), fnv1a(id), vector.clone());
            }
            let path = scratch.path().join(format!("cache-{n}.json"));
            cache.save(&path)?;
            let bytes = fs::metadata(&path)?.len();
            let load = median_ms(|| {
                std::hint::black_box(VectorCache::load(&path, "scale").ok());
            });
            (Some(bytes), Some(load))
        } else {
            (None, None)
        };
        rows.push(ScaleRow {
            n,
            search_ms,
            cache_bytes,
            cache_load_ms,
        });
    }
    Ok(rows)
}

fn show(summary: &Option<Summary>, label: &str) {
    match summary {
        Some(s) => println!(
            "| {label} | {} | {:.1} | {:.1} | {:.1} | {:.1} | {:.1} |",
            s.n, s.mean, s.p50, s.p95, s.p99, s.max
        ),
        None => println!("| {label} | 0 | - | - | - | - | - |"),
    }
}

fn write_json<T: Serialize>(path: &Option<PathBuf>, value: &T) -> Result<()> {
    if let Some(path) = path {
        let json = serde_json::to_string_pretty(value).context("serialise results")?;
        fs::write(path, json).with_context(|| format!("write {}", path.display()))?;
    }
    Ok(())
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match &cli.command {
        Command::Gate {
            relevant,
            negatives,
            top,
            selected,
        } => {
            let report = run_gate(&cli, relevant, negatives, *top, *selected)?;
            println!();
            for (label, s) in [
                ("relevant", &report.top1_score_relevant),
                ("off-topic", &report.top1_score_offtopic),
                ("adjacent", &report.top1_score_adjacent),
            ] {
                if let Some(s) = s {
                    println!(
                        "top-1 score, {label}: n={} min={:.3} p50={:.3} max={:.3}",
                        s.n, s.min, s.p50, s.max
                    );
                }
            }
            println!(
                "\nMEMORY.md index ≈ {:.0} tokens; all memory text ≈ {:.0} tokens; header ≈ {CONTEXT_HEADER_TOKENS:.0} tokens per injection",
                report.index_tokens, report.all_memory_tokens
            );
            if let (Some(row), Some(break_even)) = (&report.selected, report.break_even_prompts) {
                println!(
                    "at {:.2}: {:.0} tokens/prompt on average; the index costs the same after {break_even:.0} prompts",
                    row.threshold, row.mean_tokens
                );
            }
            write_json(&cli.json, &report)
        }
        Command::Latency {
            hook_bin,
            relevant,
            negatives,
            runs,
            warmup,
            server_pid,
        } => {
            let report = run_latency(
                &cli,
                hook_bin,
                relevant,
                negatives,
                *runs,
                *warmup,
                *server_pid,
            )?;
            println!("| hook call (ms) | n | mean | p50 | p95 | p99 | max |\n|---|---|---|---|---|---|---|");
            show(&report.all_ms, "all");
            show(&report.injected_ms, "injected");
            show(&report.not_injected_ms, "nothing injected");
            show(&report.relevant_ms, "relevant prompts");
            show(&report.offtopic_ms, "off-topic prompts");
            show(&report.adjacent_ms, "adjacent prompts");
            println!("\nhook peak RSS: {:?} kB", report.hook_peak_rss_kb);
            println!(
                "server RSS: {:?} kB before, {:?} kB after, peak {:?} kB",
                report.server_rss_kb_before, report.server_rss_kb_after, report.server_peak_rss_kb
            );
            println!(
                "server CPU: {:?} ms per hook call, {:?} ms per second idle",
                report.server_cpu_ms_per_call, report.server_idle_cpu_ms_per_s
            );
            write_json(&cli.json, &report)
        }
        Command::Index => {
            let report = run_index(&cli)?;
            println!("| step | seconds | detail |\n|---|---|---|");
            println!(
                "| cold index | {:.2} | {} chunks, {:.0} ms each |",
                report.cold_secs, report.chunks, report.cold_ms_per_chunk
            );
            println!(
                "| re-index, nothing changed | {:.3} | 0 embedded |",
                report.noop_secs
            );
            println!(
                "| re-index, one file edited | {:.3} | {} embedded |",
                report.incremental_secs, report.incremental_embedded
            );
            println!(
                "\ncache file: {} bytes; JSON load {:.1} ms",
                report.cache_bytes, report.cache_load_ms
            );
            write_json(&cli.json, &report)
        }
        Command::Scale { sizes, dims } => {
            let rows = run_scale(sizes, *dims)?;
            println!("| memories | search ms ({dims}d) | cache file | cache load ms |\n|---|---|---|---|");
            for row in &rows {
                println!(
                    "| {} | {:.3} | {} | {} |",
                    row.n,
                    row.search_ms,
                    row.cache_bytes
                        .map_or_else(|| "-".to_owned(), |b| format!("{:.1} MB", b as f64 / 1e6)),
                    row.cache_load_ms
                        .map_or_else(|| "-".to_owned(), |m| format!("{m:.1}")),
                );
            }
            write_json(&cli.json, &rows)
        }
    }
}
