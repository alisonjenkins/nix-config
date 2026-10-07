//! Section retrieval against Claude's skill listing plus whole-file loading.
//!
//! Default flow, as Claude Code does it: the listing of every skill's name and
//! description sits in context; the model names a skill, whose whole SKILL.md
//! loads; the model may then open reference files named in it, whole.
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::str::FromStr;
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};
use clap::Args as ClapArgs;
use retrieval_eval::bench::{approx_tokens, percentile};
use retrieval_eval::bm25::Bm25;
use retrieval_eval::compare::extract_files;
use retrieval_eval::corpus::{frontmatter_field, load_skill_sections, strip_frontmatter, Chunk};
use retrieval_eval::embed::{Embedder, EmbedderSpec};
use retrieval_eval::llm_run::{ask, Coverage, Item, Llm, QueryRun, SystemRun};
use retrieval_eval::retriever::Retriever;
use retrieval_eval::vector_cache::VectorCache;
use walkdir::WalkDir;

use crate::{emit, parallel, user_turn, Common};

const SYSTEM_PREAMBLE: &str = "You are helping the user with their NixOS homelab and workstation \
configuration. Answer the user's question directly, in at most 6 sentences, and be specific: \
name the rule, the exact setting, command, path or value. Use any skill text provided; if it \
lacks the detail needed, say exactly what is missing rather than guessing.";
const PICK_SKILL_TASK: &str = "Name the skills from the list above that you would load to answer \
the user's question: at most 2, exactly as named, one per line, or NONE.";
const PICK_FILES_TASK: &str = "Above is the text of the skill(s) you loaded. Name up to 2 of its \
reference files you would open to answer the user's question, using the file names exactly as \
listed, one per line, or NONE.";
/// Claude Code caps a skill's description in the listing at this many characters.
const LISTING_DESCRIPTION_CHARS: usize = 1536;
/// A section is injected whole up to this size; a hook would cap it to bound the cost.
const SECTION_INJECT_CHARS: usize = 3000;
const TIMING_RUNS: usize = 5;
const EMBED_TIMEOUT: Duration = Duration::from_secs(300);
const SYSTEMS: [&str; 6] = [
    "none",
    "default_skill_only",
    "default_load",
    "sections_bm25",
    "sections_embed",
    "oracle",
];

#[derive(ClapArgs)]
pub struct Args {
    /// Directory holding one folder per skill, e.g. ~/.claude/skills.
    #[arg(long)]
    skills_root: PathBuf,
    /// Skill folders to use; all of them when omitted.
    #[arg(long, value_delimiter = ',')]
    skills: Vec<String>,
    /// NAME=PRESET@URL[#DIMS] of the embedding server.
    #[arg(long)]
    embedder: String,
    /// Vector cache for the section embeddings.
    #[arg(long)]
    cache: PathBuf,
    /// Sections injected per query.
    #[arg(long, default_value_t = 3)]
    top: usize,
}

struct Skill {
    name: String,
    description: String,
    /// SKILL.md without its frontmatter.
    body: String,
    /// Reference files as `<skill>/<relative path>`.
    refs: Vec<String>,
}

fn load_skills(root: &Path, only: &[String]) -> Result<Vec<Skill>> {
    let mut dirs: Vec<PathBuf> = fs::read_dir(root)
        .with_context(|| format!("read {}", root.display()))?
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.join("SKILL.md").is_file())
        .collect();
    dirs.sort();
    let mut skills = Vec::new();
    for dir in dirs {
        let Some(folder) = dir.file_name().and_then(|n| n.to_str()).map(str::to_owned) else {
            continue;
        };
        if !only.is_empty() && !only.contains(&folder) {
            continue;
        }
        let raw = fs::read_to_string(dir.join("SKILL.md"))?;
        let (_, body) = strip_frontmatter(&raw);
        let mut refs = Vec::new();
        for entry in WalkDir::new(&dir).sort_by_file_name() {
            let path = entry?.into_path();
            let is_ref = path.extension().is_some_and(|e| e == "md")
                && path.file_name().is_some_and(|n| n != "SKILL.md");
            if is_ref {
                if let Ok(rel) = path.strip_prefix(root) {
                    refs.push(rel.to_string_lossy().into_owned());
                }
            }
        }
        skills.push(Skill {
            name: folder,
            description: frontmatter_field(&raw, "description").unwrap_or_default(),
            body: body.to_owned(),
            refs,
        });
    }
    Ok(skills)
}

fn listing_line(skill: &Skill) -> String {
    let description: String = skill
        .description
        .chars()
        .take(LISTING_DESCRIPTION_CHARS)
        .collect();
    format!("- {}: {description}", skill.name)
}

fn tokens_of(parts: &[&str]) -> f64 {
    approx_tokens(parts.iter().map(|p| p.len()).sum())
}

fn median_ms(mut work: impl FnMut()) -> f64 {
    let mut times: Vec<f64> = (0..TIMING_RUNS)
        .map(|_| {
            let started = Instant::now();
            work();
            started.elapsed().as_secs_f64() * 1000.0
        })
        .collect();
    times.sort_by(f64::total_cmp);
    percentile(&times, 50.0)
}

fn injected(chunks: &[Chunk], ids: &[String]) -> String {
    ids.iter()
        .filter_map(|id| chunks.iter().find(|c| &c.id == id))
        .map(|c| {
            let text: String = c.text.chars().take(SECTION_INJECT_CHARS).collect();
            format!("## {}\n{text}", c.id)
        })
        .collect::<Vec<_>>()
        .join("\n\n")
}

fn expected_skill(item: &Item) -> &str {
    item.expect
        .first()
        .and_then(|id| id.split('/').next())
        .unwrap_or_default()
}

/// Whole-file ids the expected sections come from.
fn expected_files(item: &Item) -> HashSet<&str> {
    item.expect
        .iter()
        .filter_map(|id| id.split('#').next())
        .collect()
}

struct Shared<'a> {
    skills: &'a [Skill],
    listing: String,
    root: &'a Path,
}

fn default_flow(shared: &Shared, llm: &Llm, item: &Item) -> Result<(SystemRun, SystemRun)> {
    let base = format!("{SYSTEM_PREAMBLE}\n\n");
    let names: HashSet<String> = shared.skills.iter().map(|s| s.name.clone()).collect();
    let wanted = expected_files(item);

    // The listing is in context on every turn, so it is the stable system block;
    // loaded skills and opened files arrive in the user turn, as tool results do.
    let stable = format!("{base}# Available skills\n{}", shared.listing);
    let pick = ask(llm, &stable, &user_turn(&[PICK_SKILL_TASK], &item.q))?;
    let chosen: Vec<&Skill> = extract_files(&pick.text, &names, 2)
        .iter()
        .filter_map(|n| shared.skills.iter().find(|s| &s.name == n))
        .collect();
    let bodies = chosen
        .iter()
        .map(|s| format!("# Skill: {}\n{}", s.name, s.body))
        .collect::<Vec<_>>()
        .join("\n\n");
    let skill_md_hit = chosen
        .iter()
        .any(|s| wanted.contains(format!("{}/SKILL.md", s.name).as_str()));

    // Skill text only: the model never opens a reference file.
    let mut only = SystemRun::named("default_skill_only");
    let answer = ask(llm, &stable, &user_turn(&[&bodies], &item.q))?;
    only.selection_hit = Some(skill_md_hit);
    only.retrieved_tokens = tokens_of(&[&shared.listing, &bodies]);
    only.finish(
        &item.facts,
        &[pick.clone(), answer],
        &format!("{}\n{bodies}", shared.listing),
    );

    // The full flow: the model also opens reference files named in the skill.
    let mut full = SystemRun::named("default_load");
    let by_name: HashMap<String, String> = chosen
        .iter()
        .flat_map(|s| s.refs.iter())
        .filter_map(|rel| {
            Path::new(rel)
                .file_name()
                .and_then(|n| n.to_str())
                .map(|n| (n.to_owned(), rel.clone()))
        })
        .collect();
    let mut calls = vec![pick];
    let mut opened = String::new();
    let mut files_hit = false;
    if !by_name.is_empty() {
        let listing: String = by_name.keys().cloned().collect::<Vec<_>>().join("\n");
        let known: HashSet<String> = by_name.keys().cloned().collect();
        let pick_files = ask(
            llm,
            &stable,
            &user_turn(
                &[
                    &bodies,
                    &format!("Reference files:\n{listing}"),
                    PICK_FILES_TASK,
                ],
                &item.q,
            ),
        )?;
        for name in extract_files(&pick_files.text, &known, 2) {
            if let Some(rel) = by_name.get(&name) {
                files_hit |= wanted.contains(rel.as_str());
                if let Ok(text) = fs::read_to_string(shared.root.join(rel)) {
                    opened.push_str(&format!("## {rel}\n{text}\n\n"));
                }
            }
        }
        calls.push(pick_files);
    }
    let files = format!("# Reference files you opened\n{opened}");
    calls.push(ask(llm, &stable, &user_turn(&[&bodies, &files], &item.q))?);
    full.selection_hit = Some(skill_md_hit || files_hit);
    full.retrieved_tokens = tokens_of(&[&shared.listing, &bodies, &opened]);
    full.finish(
        &item.facts,
        &calls,
        &format!("{}\n{bodies}\n{opened}", shared.listing),
    );
    Ok((only, full))
}

struct Phase1 {
    runs: Vec<SystemRun>,
    bm25_text: String,
    embed_text: String,
}

pub fn run(common: &Common, args: &Args) -> Result<()> {
    let items = common.load_items()?;
    let skills = load_skills(&args.skills_root, &args.skills)?;
    let names: Vec<String> = skills.iter().map(|s| s.name.clone()).collect();
    let chunks = load_skill_sections(&args.skills_root, &names)?;
    let listing = skills
        .iter()
        .map(listing_line)
        .collect::<Vec<_>>()
        .join("\n");
    eprintln!(
        "{} skills, {} sections, listing ≈ {:.0} tokens",
        skills.len(),
        chunks.len(),
        approx_tokens(listing.len())
    );

    let spec = EmbedderSpec::from_str(&args.embedder)?;
    let mut embedder = Embedder::with_timeout(spec, EMBED_TIMEOUT);
    let identity = embedder
        .cache_identity()
        .context("ask the server for its model")?;
    let mut cache = VectorCache::load(&args.cache, &identity)?;
    eprintln!("indexing sections (only changed ones are embedded)");
    let stats = embedder.index_cached(&chunks, &mut cache)?;
    cache.save(&args.cache)?;
    eprintln!("  embedded {}, reused {}", stats.embedded, stats.reused);
    let mut bm25 = Bm25::new();
    bm25.index(&chunks)?;

    // Phase 1: quiet and sequential, so the timings are not disturbed.
    let mut phase1: Vec<Phase1> = Vec::new();
    let mut ungrounded = Vec::new();
    for item in &items {
        let wanted: HashSet<&str> = item.expect.iter().map(String::as_str).collect();
        let expected_text = injected(&chunks, &item.expect);
        let oracle = Coverage::of(&expected_text, &item.facts);
        if oracle.found() != oracle.total() {
            ungrounded.push(item.q.clone());
        }

        let mut embed_ids = Vec::new();
        let embed_ms = median_ms(|| {
            embed_ids = embedder
                .search(&item.q)
                .map(|hits| hits.into_iter().map(|(id, _)| id).take(args.top).collect())
                .unwrap_or_default();
        });
        let mut bm25_ids = Vec::new();
        let bm25_ms = median_ms(|| {
            bm25_ids = bm25
                .rank(&item.q)
                .map(|ids| ids.into_iter().take(args.top).collect())
                .unwrap_or_default();
        });
        let embed_text = injected(&chunks, &embed_ids);
        let bm25_text = injected(&chunks, &bm25_ids);

        let line = skills
            .iter()
            .find(|s| s.name == expected_skill(item))
            .map(listing_line)
            .unwrap_or_default();
        let mut runs = Vec::new();
        for name in SYSTEMS {
            let mut run = SystemRun::named(name);
            match name {
                "default_skill_only" | "default_load" => {
                    run.retrieved_tokens = approx_tokens(listing.len());
                    run.retrieval = Coverage::of(&line, &item.facts);
                    run.context = Coverage::of(&listing, &item.facts);
                }
                "sections_bm25" => {
                    run.local_ms = bm25_ms;
                    run.retrieved_tokens = approx_tokens(bm25_text.len());
                    run.retrieval = Coverage::of(&bm25_text, &item.facts);
                    run.context = run.retrieval.clone();
                    run.selection_hit =
                        Some(bm25_ids.iter().any(|id| wanted.contains(id.as_str())));
                }
                "sections_embed" => {
                    run.local_ms = embed_ms;
                    run.retrieved_tokens = approx_tokens(embed_text.len());
                    run.retrieval = Coverage::of(&embed_text, &item.facts);
                    run.context = run.retrieval.clone();
                    run.selection_hit =
                        Some(embed_ids.iter().any(|id| wanted.contains(id.as_str())));
                }
                "oracle" => {
                    run.retrieved_tokens = approx_tokens(expected_text.len());
                    run.retrieval = oracle.clone();
                    run.context = oracle.clone();
                    run.selection_hit = Some(true);
                }
                _ => {}
            }
            runs.push(run);
        }
        phase1.push(Phase1 {
            runs,
            bm25_text,
            embed_text,
        });
    }
    if !ungrounded.is_empty() {
        bail!(
            "{} queries have facts that are not in their expected sections (bad ground truth): {:?}",
            ungrounded.len(),
            ungrounded
        );
    }

    let mut query_runs: Vec<QueryRun> = items
        .iter()
        .zip(&phase1)
        .map(|(item, p)| QueryRun {
            q: item.q.clone(),
            expect: item.expect.first().cloned().unwrap_or_default(),
            systems: p.runs.clone(),
        })
        .collect();

    // Phase 2: model calls, in parallel across queries.
    if !common.no_llm {
        let workdir = tempfile::tempdir().context("scratch dir for claude")?;
        let llm = common.llm(workdir.path());
        let shared = Shared {
            skills: &skills,
            listing: listing.clone(),
            root: &args.skills_root,
        };
        eprintln!(
            "model phase: {} queries, {} jobs, model {}",
            items.len(),
            common.jobs,
            common.model
        );
        let done = parallel(items.len(), common.jobs, |i| {
            let (Some(item), Some(p)) = (items.get(i), phase1.get(i)) else {
                bail!("query {i} out of range");
            };
            let base = format!("{SYSTEM_PREAMBLE}\n\n");
            let mut out: Vec<SystemRun> = Vec::new();

            let mut none = SystemRun::named("none");
            none.finish(&item.facts, &[ask(&llm, &base, &item.q)?], "");
            out.push(none);

            let (only, full) = default_flow(&shared, &llm, item)?;
            out.push(only);
            out.push(full);

            for (name, text) in [
                ("sections_bm25", &p.bm25_text),
                ("sections_embed", &p.embed_text),
            ] {
                let mut run = SystemRun::named(name);
                let sections = if text.is_empty() {
                    String::new()
                } else {
                    format!("# Skill sections that may be relevant\n{text}")
                };
                let call = ask(&llm, &base, &user_turn(&[&sections], &item.q))?;
                run.finish(&item.facts, &[call], text);
                out.push(run);
            }
            Ok(out)
        })?;
        for (target, llm_runs) in query_runs.iter_mut().zip(done) {
            for fresh in llm_runs {
                let Some(slot) = target.systems.iter_mut().find(|s| s.system == fresh.system)
                else {
                    continue;
                };
                if fresh.selection_hit.is_some() {
                    slot.selection_hit = fresh.selection_hit;
                }
                slot.answer = fresh.answer;
                slot.llm_in_tokens = fresh.llm_in_tokens;
                slot.llm_cache_read_tokens = fresh.llm_cache_read_tokens;
                slot.llm_cache_write_tokens = fresh.llm_cache_write_tokens;
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

    emit(common, &query_runs, &SYSTEMS)
}
