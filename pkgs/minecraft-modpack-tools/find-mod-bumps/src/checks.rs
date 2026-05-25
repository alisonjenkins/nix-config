// Pure compatibility checks: candidate-vs-planned (forward) and
// candidate-vs-existing-dependents (reverse), plus the orchestrator
// that walks a candidate list and returns the first one passing both.
// Lifted out of main.rs so the fixpoint loop and unit tests can both
// call them.
use std::collections::HashMap;

use crate::jar::{Dep, ModInfo};
use crate::version::{cmp_versions, in_range, version_key};

/// Loader / runtime modIds we never resolve against the planned-version
/// map — they're satisfied by the runtime, not by our bump graph.
pub const RUNTIME_MODIDS: &[&str] = &["minecraft", "neoforge", "forge", "java"];

/// Forward check: every required dep of `candidate_meta` must be either
/// a runtime modId or planned to a version satisfying the dep's
/// declared range. `planned` returns the planned version for a depId
/// (already-bumped version if any, else current pinned version, else "").
pub fn forward_check(candidate_meta: &ModInfo, planned: &dyn Fn(&str) -> String) -> bool {
    for d in &candidate_meta.deps {
        if d.dep_type != "required" {
            continue;
        }
        if RUNTIME_MODIDS.contains(&d.mod_id.as_str()) {
            continue;
        }
        let p = planned(&d.mod_id);
        if p.is_empty() {
            return false;
        }
        if !in_range(&p, &d.version_range) {
            return false;
        }
    }
    true
}

/// Reverse check: for every existing dependent of `mid`, the candidate's
/// version must satisfy the dependent's declared range for `mid`.
pub fn reverse_check(
    mid: &str,
    candidate_version: &str,
    deps_map: &HashMap<String, Vec<Dep>>,
    dependents_of_mid: Option<&std::collections::HashSet<String>>,
) -> bool {
    let Some(users) = dependents_of_mid else {
        return true;
    };
    for user in users {
        let Some(udeps) = deps_map.get(user) else {
            continue;
        };
        for d in udeps {
            if d.mod_id != mid || d.dep_type != "required" {
                continue;
            }
            if !in_range(candidate_version, &d.version_range) {
                return false;
            }
        }
    }
    true
}

/// One candidate already-fetched + parsed. `id` is the source-specific
/// identifier (CurseForge fileID as a string, Modrinth versionID).
/// `version` is the version string extracted from the candidate's
/// mods.toml (falls back to whatever upstream provided when blank).
/// `info` is the parsed mod info for `mid` from this candidate.
#[derive(Debug, Clone)]
pub struct CandidateMeta {
    pub id: String,
    pub version: String,
    pub info: ModInfo,
}

/// Walk a candidate list newest-first and return the first candidate
/// satisfying:
///   1. Strictly newer than `floor_version` (by semver key — guards
///      against CurseForge re-uploads with higher fileIDs but older
///      semantic versions).
///   2. Forward check: every required dep is satisfied by the planned
///      version map.
///   3. Reverse check: every existing dependent of `mid` accepts the
///      candidate version.
///
/// Stops at the first candidate whose `id` equals `floor_id` (the pack
/// pin or the version already chosen this round); anything older isn't
/// a valid bump.
///
/// Returns `None` when no candidate passes — caller treats as
/// "incompat" / keep current.
pub fn pick_candidate<'a, F>(
    mid: &str,
    candidates: &'a [CandidateMeta],
    floor_id: &str,
    floor_version: &str,
    planned: &F,
    deps_map: &HashMap<String, Vec<Dep>>,
    dependents_of_mid: Option<&std::collections::HashSet<String>>,
) -> Option<&'a CandidateMeta>
where
    F: Fn(&str) -> String,
{
    for cand in candidates {
        if cand.id == floor_id {
            return None;
        }
        if !floor_version.is_empty()
            && cmp_versions(&version_key(&cand.version), &version_key(floor_version))
                != std::cmp::Ordering::Greater
        {
            continue;
        }
        if !forward_check(&cand.info, planned) {
            continue;
        }
        if !reverse_check(mid, &cand.version, deps_map, dependents_of_mid) {
            continue;
        }
        return Some(cand);
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    fn dep(mod_id: &str, range: &str) -> Dep {
        Dep {
            mod_id: mod_id.into(),
            version_range: range.into(),
            dep_type: "required".into(),
        }
    }

    #[test]
    fn forward_check_runtime_ids_ignored() {
        let meta = ModInfo {
            version: "1.0".into(),
            deps: vec![
                dep("neoforge", "[999,)"),
                dep("minecraft", "[999,)"),
                dep("java", "[999,)"),
            ],
        };
        // Runtime ids never resolved against planned map -> pass.
        assert!(forward_check(&meta, &|_| String::new()));
    }

    #[test]
    fn forward_check_satisfied_when_planned_in_range() {
        let meta = ModInfo {
            version: "1.0".into(),
            deps: vec![dep("lib", "[3.1,)")],
        };
        assert!(forward_check(&meta, &|m| {
            if m == "lib" { "3.1.8".into() } else { String::new() }
        }));
    }

    #[test]
    fn forward_check_fails_when_planned_below_range() {
        let meta = ModInfo {
            version: "1.0".into(),
            deps: vec![dep("lib", "[3.1,)")],
        };
        assert!(!forward_check(&meta, &|m| {
            if m == "lib" { "3.0.27".into() } else { String::new() }
        }));
    }

    #[test]
    fn forward_check_fails_when_dep_unplanned() {
        let meta = ModInfo {
            version: "1.0".into(),
            deps: vec![dep("missing_lib", "[1,)")],
        };
        assert!(!forward_check(&meta, &|_| String::new()));
    }

    #[test]
    fn forward_check_skips_optional_deps() {
        let mut meta = ModInfo {
            version: "1.0".into(),
            deps: vec![Dep {
                mod_id: "lib".into(),
                version_range: "[99,)".into(),
                dep_type: "optional".into(),
            }],
        };
        // Optional deps don't block a bump.
        assert!(forward_check(&meta, &|_| String::new()));
        // But required + unmet does.
        meta.deps[0].dep_type = "required".into();
        assert!(!forward_check(&meta, &|_| String::new()));
    }

    #[test]
    fn reverse_check_no_dependents_passes() {
        let deps_map: HashMap<String, Vec<Dep>> = HashMap::new();
        assert!(reverse_check("lib", "3.1.8", &deps_map, None));
    }

    #[test]
    fn reverse_check_passes_when_all_dependents_accept() {
        let mut deps_map: HashMap<String, Vec<Dep>> = HashMap::new();
        deps_map.insert("consumer".into(), vec![dep("lib", "[2.0,)")]);
        let mut dependents = HashSet::new();
        dependents.insert("consumer".into());
        assert!(reverse_check("lib", "3.1.8", &deps_map, Some(&dependents)));
    }

    #[test]
    fn reverse_check_fails_when_dependent_excludes_candidate() {
        let mut deps_map: HashMap<String, Vec<Dep>> = HashMap::new();
        deps_map.insert("consumer".into(), vec![dep("lib", "[2.0,3.0)")]);
        let mut dependents = HashSet::new();
        dependents.insert("consumer".into());
        // 3.1.8 not in [2.0,3.0).
        assert!(!reverse_check("lib", "3.1.8", &deps_map, Some(&dependents)));
    }

    #[test]
    fn reverse_check_ignores_non_required_dependent() {
        let mut deps_map: HashMap<String, Vec<Dep>> = HashMap::new();
        deps_map.insert(
            "consumer".into(),
            vec![Dep {
                mod_id: "lib".into(),
                version_range: "[2.0,3.0)".into(),
                dep_type: "optional".into(),
            }],
        );
        let mut dependents = HashSet::new();
        dependents.insert("consumer".into());
        assert!(reverse_check("lib", "3.1.8", &deps_map, Some(&dependents)));
    }

    /// Regression for the leaves-first false-negative: a consumer that
    /// requires the bumped lib version should pass forward_check ONLY
    /// when `planned(lib)` returns the bumped version. This is the
    /// invariant the fixpoint loop relies on — once the lib's bump is
    /// committed into the planned map, the consumer becomes acceptable.
    #[test]
    fn fixpoint_invariant_consumer_passes_after_lib_planned_bumped() {
        let consumer_meta = ModInfo {
            version: "0.0.9".into(),
            deps: vec![dep("azurelib", "[3.1,)")],
        };
        // Before lib bump committed: planned returns current 3.0.27 -> fail.
        let before = |m: &str| if m == "azurelib" { "3.0.27".into() } else { String::new() };
        assert!(!forward_check(&consumer_meta, &before));
        // After fixpoint commits lib bump: planned returns 3.1.8 -> pass.
        let after = |m: &str| if m == "azurelib" { "3.1.8".into() } else { String::new() };
        assert!(forward_check(&consumer_meta, &after));
    }

    // -------- pick_candidate -----------------------------------------

    fn cand(id: &str, version: &str, deps: Vec<Dep>) -> CandidateMeta {
        CandidateMeta {
            id: id.into(),
            version: version.into(),
            info: ModInfo { version: version.into(), deps },
        }
    }

    #[test]
    fn pick_candidate_picks_newest_passing() {
        // Two candidates, both forward-pass; pick the first (newest).
        let cands = vec![
            cand("200", "2.0", vec![]),
            cand("100", "1.5", vec![]),
        ];
        let chosen = pick_candidate(
            "foo",
            &cands,
            "10",   // floor_id (pack pin)
            "1.0",  // floor_version
            &|_| String::new(),
            &HashMap::new(),
            None,
        );
        assert_eq!(chosen.map(|c| c.id.as_str()), Some("200"));
    }

    #[test]
    fn pick_candidate_skips_failing_forward_check() {
        // Newest candidate requires lib >= 3.1, planned says 3.0 → skip.
        // Next candidate has no deps → pick that.
        let cands = vec![
            cand("200", "2.0", vec![dep("lib", "[3.1,)")]),
            cand("100", "1.5", vec![]),
        ];
        let chosen = pick_candidate(
            "foo",
            &cands,
            "10",
            "1.0",
            &|m: &str| if m == "lib" { "3.0".into() } else { String::new() },
            &HashMap::new(),
            None,
        );
        assert_eq!(chosen.map(|c| c.id.as_str()), Some("100"));
    }

    /// REGRESSION: cataclysm_spellbooks 1.1.10 vs 1.1.11 from v57.
    /// The fixpoint MUST re-evaluate already-bumped mods after a lib
    /// they depend on flips its planned-version. Demonstrates the
    /// pick_candidate floor-id semantics: pass the previously-chosen
    /// id as floor; with the new planned-version, the newer candidate
    /// now passes and gets picked.
    #[test]
    fn pick_candidate_promotes_when_planned_dep_bumps() {
        // Mirrors the real cataclysm_spellbooks / azurelib scenario:
        // pack ships lib at 3.0.27. 1.1.10 declares the open-lower
        // range [2.3.28,) which 3.0.27 satisfies; 1.1.11 declares the
        // tighter [3.1.0,) which 3.0.27 does NOT satisfy.
        let cands = vec![
            cand("1100", "1.1.11", vec![dep("lib", "[3.1.0,)")]),
            cand("1010", "1.1.10", vec![dep("lib", "[2.3.28,)")]),
        ];
        let planned_pass1 = |m: &str| if m == "lib" { "3.0.27".into() } else { String::new() };
        let chosen1 = pick_candidate(
            "consumer",
            &cands,
            "1000", // floor_id (pack pin)
            "1.0",  // floor_version (pack pin's version)
            &planned_pass1,
            &HashMap::new(),
            None,
        );
        assert_eq!(chosen1.map(|c| c.id.as_str()), Some("1010"),
                   "pass 1: should fall back to 1.1.10 because lib at 1.0 doesn't satisfy 1.1.11's [3.1.0,)");

        // pass 2: lib bumped to 3.1.8 in the planned map. Re-run with
        // the just-chosen id ("1010") as the floor — pick_candidate
        // should now pick 1.1.11 (it's newer than the floor + its
        // forward-check passes against the updated planned map).
        let planned_pass2 = |m: &str| if m == "lib" { "3.1.8".into() } else { String::new() };
        let chosen2 = pick_candidate(
            "consumer",
            &cands,
            "1010",  // floor_id = the v1.1.10 we picked in pass 1
            "1.1.10",
            &planned_pass2,
            &HashMap::new(),
            None,
        );
        assert_eq!(chosen2.map(|c| c.id.as_str()), Some("1100"),
                   "pass 2: should promote to 1.1.11 once lib is planned-bumped to 3.1.8");
    }

    #[test]
    fn pick_candidate_stops_at_floor_id_no_downgrade() {
        // Floor is the middle candidate; only the newer one should be
        // considered, and the older one (below floor) must be ignored
        // entirely (even if everything else about it is fine).
        let cands = vec![
            cand("200", "2.0", vec![]),
            cand("150", "1.5", vec![]),  // floor — stop here
            cand("100", "1.0", vec![]),
        ];
        let chosen = pick_candidate(
            "foo",
            &cands,
            "150",
            "1.5",
            &|_| String::new(),
            &HashMap::new(),
            None,
        );
        assert_eq!(chosen.map(|c| c.id.as_str()), Some("200"));
    }

    #[test]
    fn pick_candidate_returns_none_when_nothing_passes() {
        let cands = vec![
            cand("200", "2.0", vec![dep("lib", "[99,)")]),
            cand("150", "1.5", vec![dep("lib", "[99,)")]),
        ];
        let chosen = pick_candidate(
            "foo",
            &cands,
            "100",
            "1.0",
            &|_| String::new(),
            &HashMap::new(),
            None,
        );
        assert!(chosen.is_none());
    }

    #[test]
    fn pick_candidate_rejects_lower_semver_with_higher_id() {
        // CurseForge re-upload case: fileID 200 has SEMVER 0.5
        // (re-upload of an older patch series with a higher upload-id).
        // The walk sees id=200 first, but version_key check rejects it
        // because 0.5 < floor 1.0. Falls back to id=150.
        let cands = vec![
            cand("200", "0.5", vec![]),
            cand("150", "1.5", vec![]),
        ];
        let chosen = pick_candidate(
            "foo",
            &cands,
            "100",
            "1.0",
            &|_| String::new(),
            &HashMap::new(),
            None,
        );
        assert_eq!(chosen.map(|c| c.id.as_str()), Some("150"));
    }
}
