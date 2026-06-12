// Rust orchestrator for find-mod-bumps. Walks the dep graph leaves-first,
// pre-fetches listings + jars in parallel, then chooses the newest
// compatible bump per mod under the existing pack's version-range
// constraints. After the initial pass, iterates to a fixpoint so that
// consumers whose forward-check failed only because the lib they depend
// on hadn't been bump-committed yet get re-evaluated against the
// updated planned-version map.
use anyhow::Result;
use clap::Parser;
use rayon::prelude::*;
use std::collections::{BTreeMap, HashMap, HashSet};
use std::io::Write;
use std::path::PathBuf;
use std::sync::Mutex;

use find_mod_bumps::checks::{forward_check, reverse_check};
use find_mod_bumps::jar::{parse_jar_mods, Dep, ModInfo};
use find_mod_bumps::output::{
    format_extras_replacement, format_overlays_curseforge, format_overlays_modrinth, BumpRecord,
};
use find_mod_bumps::sources::{current_id_of, enumerate_candidates, Candidate};
use find_mod_bumps::state::{load_pack_state, DestFile, Source, StateEntry};
use find_mod_bumps::topo::toposort_leaves_first;
use find_mod_bumps::version::{cmp_versions, version_key};

#[derive(Parser, Debug)]
#[command(
    about = "Find newer compatible mod versions for a NeoForge modpack",
    long_about = None
)]
struct Cli {
    /// Path to the built server tree (mods/ inside).
    server_tree: PathBuf,

    #[arg(
        long,
        default_value = "pkgs/create-arkana-aeronautics-server/arkana-mods.nix"
    )]
    mods_nix: PathBuf,

    #[arg(
        long,
        default_value = "pkgs/create-arkana-aeronautics-server/arkana-mods-extras.nix"
    )]
    extras_nix: PathBuf,

    #[arg(
        long,
        default_value = "pkgs/create-arkana-aeronautics-server/overlays.nix"
    )]
    overlays_nix: PathBuf,

    /// Comma-separated modIds — process these only.
    #[arg(long, value_delimiter = ',')]
    only: Vec<String>,

    /// Comma-separated modIds to skip (e.g. known-incompat bumps).
    #[arg(long, value_delimiter = ',')]
    skip: Vec<String>,

    #[arg(long)]
    report_json: Option<PathBuf>,

    /// Parallel HTTP workers for listing + jar fetch.
    #[arg(long, default_value_t = 16)]
    concurrency: usize,

    /// Per-mod, pre-download top N candidate jars in parallel.
    #[arg(long, default_value_t = 5)]
    prefetch: usize,

    /// Max fixpoint iterations after the initial leaves-first walk.
    /// Each pass re-evaluates mods previously skipped as incompatible,
    /// using bump decisions committed in earlier passes.
    #[arg(long, default_value_t = 8)]
    max_passes: usize,
}

/// Sentinel skip reason emitted when forward+reverse checks could not
/// pick a candidate. The fixpoint loop re-evaluates only mods carrying
/// this reason — "already at latest" and "no versions returned" are
/// terminal.
const REASON_INCOMPAT: &str = "no compatible newer version found";

fn main() -> Result<()> {
    let args = Cli::parse();

    rayon::ThreadPoolBuilder::new()
        .num_threads(args.concurrency)
        .build_global()
        .ok();

    let mods_dir = args.server_tree.join("mods");
    if !mods_dir.is_dir() {
        eprintln!("no mods/ in {}", args.server_tree.display());
        std::process::exit(2);
    }

    let overlays_path = args.overlays_nix.exists().then_some(args.overlays_nix.as_path());
    let extras_path = args.extras_nix.exists().then_some(args.extras_nix.as_path());
    let state = load_pack_state(&args.mods_nix, extras_path, overlays_path)?;
    eprintln!("Loaded pack state: {} entries from nix sources.", state.len());

    // Parallel scan of the jars dir.
    eprintln!("Scanning {}…", mods_dir.display());
    let jar_paths: Vec<PathBuf> = std::fs::read_dir(&mods_dir)?
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|ext| ext == "jar"))
        .collect();
    let scanned: Vec<(String, HashMap<String, ModInfo>)> = jar_paths
        .par_iter()
        .map(|p| (p.file_name().unwrap().to_string_lossy().into_owned(), parse_jar_mods(p)))
        .collect();

    let mut current_version: HashMap<String, String> = HashMap::new();
    let mut deps_map: HashMap<String, Vec<Dep>> = HashMap::new();
    let mut modid_to_entry: HashMap<String, StateEntry> = HashMap::new();
    for (fname, info) in scanned {
        for (mid, meta) in info {
            current_version.insert(mid.clone(), meta.version);
            deps_map.insert(mid.clone(), meta.deps);
            if let Some(entry) = state.get(&fname) {
                modid_to_entry.insert(mid.clone(), entry.clone());
            }
        }
    }

    // Reverse-edge.
    let mut dependents: HashMap<String, HashSet<String>> = HashMap::new();
    for (mid, dlist) in &deps_map {
        for d in dlist {
            if d.dep_type == "required" {
                dependents.entry(d.mod_id.clone()).or_default().insert(mid.clone());
            }
        }
    }

    let only: HashSet<String> = args.only.into_iter().collect();
    let skip: HashSet<String> = args.skip.into_iter().collect();
    let mut bumpable: HashSet<String> = modid_to_entry.keys().cloned().collect();
    if !only.is_empty() {
        bumpable = bumpable.intersection(&only).cloned().collect();
    }
    for s in &skip {
        bumpable.remove(s);
    }
    // Persistent hand-pins: replacements marked `noBump = true` in
    // arkana-mods-extras.nix are never advanced. Unlike --skip (per-run),
    // this travels with the data so a later fixpoint round can't re-suggest
    // a known-bad ABI bump and clobber the pin (e.g. lionfishapi 2.6).
    let pinned: Vec<String> = modid_to_entry
        .iter()
        .filter(|(_, e)| e.no_bump)
        .map(|(mid, _)| mid.clone())
        .collect();
    for mid in &pinned {
        bumpable.remove(mid);
    }
    if !pinned.is_empty() {
        let mut names = pinned.clone();
        names.sort();
        eprintln!("Honoring {} noBump pin(s): {}", names.len(), names.join(", "));
    }

    let order = toposort_leaves_first(&bumpable, &dependents);
    let (cf_n, mr_n) = bumpable.iter().fold((0usize, 0usize), |(c, m), mid| {
        match modid_to_entry.get(mid).map(|e| e.source_kind()) {
            Some("curseforge") => (c + 1, m),
            Some("modrinth") => (c, m + 1),
            _ => (c, m),
        }
    });
    eprintln!(
        "Bumpable mod count: {} (curseforge={}, modrinth={}); processing leaves first.",
        bumpable.len(),
        cf_n,
        mr_n
    );

    // Phase 1: parallel pre-fetch of every bumpable mod's listing.
    eprintln!("Pre-fetching {} candidate listings in parallel…", order.len());
    let progress = Mutex::new(0usize);
    let total = order.len();
    let candidates_by_mid: HashMap<String, Vec<Candidate>> = order
        .par_iter()
        .map(|mid| {
            let entry = modid_to_entry.get(mid).unwrap();
            let cands = enumerate_candidates(entry).unwrap_or_default();
            let mut g = progress.lock().unwrap();
            *g += 1;
            if *g % 10 == 0 || *g == total {
                eprintln!("  listings: {}/{}", *g, total);
            }
            (mid.clone(), cands)
        })
        .collect();

    let mut bumps: BTreeMap<String, BumpRecord> = BTreeMap::new();
    let mut skipped_reasons: BTreeMap<String, String> = BTreeMap::new();

    // Pass 1: leaves-first walk. Records bumps + reasons.
    eprintln!("Pass 1: leaves-first walk over {} mods…", order.len());
    for (i, mid) in order.iter().enumerate() {
        match try_bump_mod(
            mid,
            &modid_to_entry,
            &candidates_by_mid,
            &current_version,
            &deps_map,
            &dependents,
            &bumps,
            args.prefetch,
            None,
        ) {
            Ok(Some(record)) => {
                eprintln!(
                    "  [{}/{}] {}: {} -> {} ({})",
                    i + 1,
                    order.len(),
                    mid,
                    record.current_version,
                    record.version,
                    record.source
                );
                bumps.insert(mid.clone(), record);
            }
            Ok(None) => { /* unreachable today, kept for future shapes */ }
            Err(reason) => {
                skipped_reasons.insert(mid.clone(), reason);
            }
        }
    }

    // Fixpoint: re-evaluate every bumpable mod against the updated
    // planned-version map until no changes land. Two distinct cases
    // each pass picks up:
    //   1. A mod skipped as REASON_INCOMPAT because forward-check
    //      failed against an un-bumped lib (which a later mod's pass
    //      then bumped).
    //   2. A mod already in `bumps` but on an older candidate than
    //      ideal — when find-mod-bumps walked it leaves-first before a
    //      lib it depends on got bumped, the newest candidate that
    //      DECLARED a tight range on the new lib version was rejected;
    //      the tool fell back to an older candidate with a looser range.
    //      Once the lib is bumped, the newer candidate now passes.
    //      (This is the cataclysm_spellbooks 1.1.10 vs 1.1.11 case that
    //      shipped broken in v57.)
    //
    // For case (1) we pass `floor = None` so the candidate walk uses
    // the pack pin. For case (2) we pass the just-chosen bump's id +
    // version as the floor, so re-evaluation can ONLY land on a
    // strictly-newer candidate — never downgrade. Mods unchanged by
    // the previous pass naturally re-emerge with the same record;
    // the loop terminates when no record changed this pass.
    let mut pass = 2;
    loop {
        if pass > args.max_passes + 1 {
            eprintln!("Reached --max-passes={}; stopping fixpoint.", args.max_passes);
            break;
        }
        eprintln!(
            "Pass {}: re-evaluating {} bumpable mods against updated planned versions…",
            pass,
            order.len()
        );
        let mut new_bumps = 0usize;
        let mut promoted_bumps = 0usize;
        for mid in order.iter() {
            let floor = bumps.get(mid).map(|b| {
                let id = match modid_to_entry.get(mid).map(|e| &e.source) {
                    Some(Source::Curseforge { .. }) => b.file_id.to_string(),
                    Some(Source::Modrinth { .. }) => b.version_id.clone(),
                    None => String::new(),
                };
                (id, b.version.clone())
            });
            match try_bump_mod(
                mid,
                &modid_to_entry,
                &candidates_by_mid,
                &current_version,
                &deps_map,
                &dependents,
                &bumps,
                args.prefetch,
                floor.clone(),
            ) {
                Ok(Some(record)) => {
                    if let Some(existing) = bumps.get(mid) {
                        // Already had a bump — only count as a change
                        // if the chosen candidate is different (i.e. a
                        // promotion to a newer version).
                        if existing.version != record.version {
                            eprintln!(
                                "  ^promote {}: {} -> {} ({})",
                                mid, existing.version, record.version, record.source
                            );
                            bumps.insert(mid.clone(), record);
                            promoted_bumps += 1;
                        }
                    } else {
                        eprintln!(
                            "  +bump {}: {} -> {} ({})",
                            mid, record.current_version, record.version, record.source
                        );
                        skipped_reasons.remove(mid);
                        bumps.insert(mid.clone(), record);
                        new_bumps += 1;
                    }
                }
                Err(reason) => {
                    // If this mod had a bump and we passed floor=Some,
                    // a returned Err means "no newer candidate passes" —
                    // existing bump stays. Don't overwrite skipped_reason
                    // in that case.
                    if floor.is_none() {
                        skipped_reasons.insert(mid.clone(), reason);
                    }
                }
                Ok(None) => {}
            }
        }
        eprintln!(
            "  pass {} added {} new bumps, promoted {} existing.",
            pass, new_bumps, promoted_bumps
        );
        if new_bumps == 0 && promoted_bumps == 0 {
            break;
        }
        pass += 1;
    }

    // -------- report --------
    let mut stdout = std::io::stdout().lock();
    writeln!(stdout)?;
    writeln!(stdout, "=== {} bumps available ===", bumps.len())?;
    for (mid, b) in &bumps {
        let tag = if b.source == "modrinth" { "[mr]" } else { "[cf]" };
        writeln!(
            stdout,
            "  {} {:30}  {:20} -> {}",
            tag, mid, b.current_version, b.version
        )?;
    }
    writeln!(stdout)?;
    writeln!(stdout, "=== Skipped: {} ===", skipped_reasons.len())?;
    for (mid, reason) in &skipped_reasons {
        writeln!(stdout, "  {:30}  {}", mid, reason)?;
    }

    let extras_bumps: Vec<&BumpRecord> = bumps.values().filter(|b| b.dest_file == "extras.nix").collect();
    let overlays_cf: Vec<&BumpRecord> = bumps
        .values()
        .filter(|b| b.dest_file == "overlays.nix" && b.source == "curseforge")
        .collect();
    let overlays_mr: Vec<&BumpRecord> = bumps
        .values()
        .filter(|b| b.dest_file == "overlays.nix" && b.source == "modrinth")
        .collect();

    if !extras_bumps.is_empty() {
        writeln!(stdout)?;
        writeln!(
            stdout,
            "=== extras.nix replacement entries (paste into `replacements = [ ... ]`) ==="
        )?;
        let mut sorted = extras_bumps.clone();
        sorted.sort_by(|a, b| a.name.cmp(&b.name));
        for b in sorted {
            writeln!(stdout, "{}", format_extras_replacement(b))?;
        }
    }
    if !overlays_cf.is_empty() {
        writeln!(stdout)?;
        writeln!(stdout, "=== overlays.nix CurseForge entries (replace in-place) ===")?;
        let mut sorted = overlays_cf.clone();
        sorted.sort_by(|a, b| a.name.cmp(&b.name));
        for b in sorted {
            writeln!(stdout, "{}", format_overlays_curseforge(b))?;
        }
    }
    if !overlays_mr.is_empty() {
        writeln!(stdout)?;
        writeln!(stdout, "=== overlays.nix Modrinth entries (replace in-place) ===")?;
        let mut sorted = overlays_mr.clone();
        sorted.sort_by(|a, b| a.name.cmp(&b.name));
        for b in sorted {
            writeln!(stdout, "{}", format_overlays_modrinth(b))?;
        }
    }

    if let Some(path) = args.report_json {
        let json = serde_json::json!({
            "bumps": bumps.iter().map(|(k, v)| (k.clone(), bump_record_to_json(v))).collect::<serde_json::Map<_,_>>(),
            "skipped": skipped_reasons.iter().map(|(k, v)| (k.clone(), serde_json::Value::String(v.clone()))).collect::<serde_json::Map<_,_>>(),
        });
        std::fs::write(&path, serde_json::to_vec_pretty(&json)?)?;
    }

    Ok(())
}

/// One mod's bump decision. Returns:
///   Ok(Some(rec))  — bump picked
///   Err(reason)    — skipped with explanation; caller stores reason.
///
/// `floor_id`/`floor_ver` is the lower bound the candidate walk stops at
/// (exclusive). Pass `None` for fresh evaluation — defaults to the pack's
/// current pinned id+version (i.e. the arkana base or whatever extras
/// already pinned). In the fixpoint loop, callers pass the just-chosen
/// bump's id+version here so re-evaluation can only pick STRICTLY-NEWER
/// candidates — never downgrade.
fn try_bump_mod(
    mid: &str,
    modid_to_entry: &HashMap<String, StateEntry>,
    candidates_by_mid: &HashMap<String, Vec<Candidate>>,
    current_version: &HashMap<String, String>,
    deps_map: &HashMap<String, Vec<Dep>>,
    dependents: &HashMap<String, HashSet<String>>,
    bumps: &BTreeMap<String, BumpRecord>,
    prefetch: usize,
    floor: Option<(String, String)>,
) -> std::result::Result<Option<BumpRecord>, String> {
    let entry = modid_to_entry.get(mid).ok_or_else(|| "unknown mod".to_string())?;
    let cur_ver = current_version.get(mid).cloned().unwrap_or_default();
    let candidates = match candidates_by_mid.get(mid) {
        Some(c) if !c.is_empty() => c,
        _ => {
            return Err(format!(
                "no {} versions returned (project deleted? or rate-limited)",
                entry.source_kind()
            ));
        }
    };

    // floor_id = anything we already chose this round (no downgrade);
    // floor_ver = its version (for the strict-semver guard).
    let (floor_id, floor_ver) = floor.unwrap_or_else(|| (current_id_of(entry), cur_ver.clone()));
    if candidates[0].id == floor_id {
        return Err(format!("already at latest ({})", floor_ver));
    }

    let prefetch_n = prefetch.min(candidates.len());
    candidates[..prefetch_n].par_iter().for_each(|c| {
        let _ = (c.fetch)();
    });

    let planned = |dep_mid: &str| -> String {
        if let Some(b) = bumps.get(dep_mid) {
            return b.version.clone();
        }
        current_version.get(dep_mid).cloned().unwrap_or_default()
    };

    for cand in candidates.iter() {
        if cand.id == floor_id {
            // Reached floor (either pack pin or the version we already
            // chose in this round). Anything older isn't a valid bump.
            break;
        }
        let jar = match (cand.fetch)() {
            Ok(p) => p,
            Err(_) => continue,
        };
        if !jar.exists() || std::fs::metadata(&jar).map(|m| m.len()).unwrap_or(0) == 0 {
            continue;
        }
        let cand_info = parse_jar_mods(&jar);
        let Some(meta) = cand_info.get(mid).cloned() else { continue; };
        let cand_version = if !meta.version.is_empty() {
            meta.version.clone()
        } else {
            cand.version_hint.clone().unwrap_or_default()
        };

        // Strict semver guard: must be strictly newer than the floor
        // version. Catches CurseForge re-uploads where a newer fileID
        // points at a semantically-older version, AND catches the case
        // where the fixpoint already chose X and someone tries to
        // re-evaluate against a candidate listed with a higher fileID
        // but a lower version_key.
        if !floor_ver.is_empty()
            && cmp_versions(&version_key(&cand_version), &version_key(&floor_ver))
                != std::cmp::Ordering::Greater
        {
            continue;
        }

        if !forward_check(&meta, &planned) {
            continue;
        }
        if !reverse_check(mid, &cand_version, deps_map, dependents.get(mid)) {
            continue;
        }

        return Ok(Some(build_bump_record(entry, cand, &cand_version, &cur_ver, mid)));
    }

    Err(REASON_INCOMPAT.to_string())
}

fn build_bump_record(
    entry: &StateEntry,
    cand: &Candidate,
    cand_version: &str,
    cur_ver: &str,
    mid: &str,
) -> BumpRecord {
    let mut rec = BumpRecord {
        mod_id: mid.to_string(),
        name: cand.name.clone(),
        version: cand_version.to_string(),
        current_version: cur_ver.to_string(),
        source: entry.source_kind().to_string(),
        dest_file: match entry.dest_file {
            DestFile::Extras => "extras.nix".to_string(),
            DestFile::Overlays => "overlays.nix".to_string(),
        },
        project_id_num: 0,
        project_id_str: String::new(),
        file_id: 0,
        current_file_id: 0,
        version_id: String::new(),
        current_version_id: String::new(),
    };
    match &entry.source {
        Source::Curseforge { project_id, file_id } => {
            rec.project_id_num = *project_id;
            rec.current_file_id = *file_id;
            rec.file_id = cand.id.parse().unwrap_or(0);
        }
        Source::Modrinth { project_id, version_id } => {
            rec.project_id_str = project_id.clone();
            rec.current_version_id = version_id.clone();
            rec.version_id = cand.id.clone();
        }
    }
    rec
}

fn bump_record_to_json(b: &BumpRecord) -> serde_json::Value {
    let mut m = serde_json::Map::new();
    m.insert("name".into(), b.name.clone().into());
    m.insert("version".into(), b.version.clone().into());
    m.insert("current_version".into(), b.current_version.clone().into());
    m.insert("source".into(), b.source.clone().into());
    m.insert("dest_file".into(), b.dest_file.clone().into());
    if b.source == "curseforge" {
        m.insert("project_id".into(), b.project_id_num.into());
        m.insert("file_id".into(), b.file_id.into());
        m.insert("current_file_id".into(), b.current_file_id.into());
    } else {
        m.insert("project_id".into(), b.project_id_str.clone().into());
        m.insert("version_id".into(), b.version_id.clone().into());
        m.insert("current_version_id".into(), b.current_version_id.clone().into());
    }
    serde_json::Value::Object(m)
}
