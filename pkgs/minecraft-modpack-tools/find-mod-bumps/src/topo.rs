// Leaves-first toposort: a mod with no dependents in the remaining set
// is emitted before mods that depend on it. Cycles fall through in
// arbitrary order with a stable tie-break.
use std::collections::{BTreeSet, HashMap, HashSet};

pub fn toposort_leaves_first(
    modids: &HashSet<String>,
    dependents: &HashMap<String, HashSet<String>>,
) -> Vec<String> {
    let mut remaining: BTreeSet<String> = modids.iter().cloned().collect();
    let mut ordered: Vec<String> = Vec::with_capacity(remaining.len());
    while !remaining.is_empty() {
        let mut leaves: Vec<String> = remaining
            .iter()
            .filter(|m| {
                let deps_of_m = dependents.get(*m);
                match deps_of_m {
                    None => true,
                    Some(set) => set.iter().all(|d| !remaining.contains(d)),
                }
            })
            .cloned()
            .collect();
        if leaves.is_empty() {
            // Cycle — flush whatever's left in sorted order.
            ordered.extend(remaining.iter().cloned());
            break;
        }
        leaves.sort();
        for m in &leaves {
            remaining.remove(m);
        }
        ordered.extend(leaves);
    }
    ordered
}

#[cfg(test)]
mod tests {
    use super::*;

    fn set<I: IntoIterator<Item = &'static str>>(iter: I) -> HashSet<String> {
        iter.into_iter().map(String::from).collect()
    }

    #[test]
    fn pure_leaf_emits_first() {
        // a depends on b => dependents[b] = {a}. Leaf b has zero deps,
        // a has dependents{} -> a is the leaf. b lists a as dependent.
        let modids = set(["a", "b"]);
        let mut dependents: HashMap<String, HashSet<String>> = HashMap::new();
        dependents.insert("b".into(), set(["a"]));
        let ord = toposort_leaves_first(&modids, &dependents);
        // Leaves first = `a` (nothing depends on it) before `b`.
        assert_eq!(ord, vec!["a".to_string(), "b".to_string()]);
    }

    #[test]
    fn cycle_falls_through() {
        // a<->b cycle.
        let modids = set(["a", "b"]);
        let mut dependents: HashMap<String, HashSet<String>> = HashMap::new();
        dependents.insert("a".into(), set(["b"]));
        dependents.insert("b".into(), set(["a"]));
        let ord = toposort_leaves_first(&modids, &dependents);
        assert_eq!(ord.len(), 2);
        assert!(ord.contains(&"a".to_string()));
        assert!(ord.contains(&"b".to_string()));
    }

    #[test]
    fn diamond_structure() {
        // top depends on left + right, left + right depend on bottom.
        //   bottom <- left <- top
        //   bottom <- right <- top
        // dependents[bottom] = {left, right}
        // dependents[left]   = {top}
        // dependents[right]  = {top}
        // Leaves-first => top first, then left+right, then bottom.
        let modids = set(["top", "left", "right", "bottom"]);
        let mut dependents: HashMap<String, HashSet<String>> = HashMap::new();
        dependents.insert("bottom".into(), set(["left", "right"]));
        dependents.insert("left".into(), set(["top"]));
        dependents.insert("right".into(), set(["top"]));
        let ord = toposort_leaves_first(&modids, &dependents);
        assert_eq!(ord[0], "top");
        assert_eq!(ord[3], "bottom");
        // middle two in sorted order.
        assert_eq!(&ord[1..3], &["left".to_string(), "right".to_string()]);
    }
}
