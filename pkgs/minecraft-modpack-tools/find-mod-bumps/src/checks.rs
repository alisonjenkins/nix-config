// Pure compatibility checks: candidate-vs-planned (forward) and
// candidate-vs-existing-dependents (reverse). Lifted out of main.rs so
// the fixpoint loop and unit tests can both call them.
use std::collections::HashMap;

use crate::jar::{Dep, ModInfo};
use crate::version::in_range;

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
}
