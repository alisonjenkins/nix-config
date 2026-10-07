use std::collections::{HashMap, HashSet};

/// 1-based rank of the first expected id, or `None` when none is ranked.
pub fn first_hit_rank(ranking: &[String], expected: &HashSet<String>) -> Option<usize> {
    ranking
        .iter()
        .position(|id| expected.contains(id))
        .map(|zero_based| zero_based.saturating_add(1))
}

fn mean(values: impl Iterator<Item = f64>, count: usize) -> f64 {
    if count == 0 {
        return 0.0;
    }
    values.sum::<f64>() / count as f64
}

pub fn recall_at(ranks: &[Option<usize>], k: usize) -> f64 {
    let hit = |r: &Option<usize>| f64::from(u8::from(r.is_some_and(|rank| rank <= k)));
    mean(ranks.iter().map(hit), ranks.len())
}

pub fn mrr(ranks: &[Option<usize>]) -> f64 {
    let reciprocal = |r: &Option<usize>| r.map_or(0.0, |rank| 1.0 / rank as f64);
    mean(ranks.iter().map(reciprocal), ranks.len())
}

/// Reciprocal rank fusion; `k` = 60 is the constant from the original RRF paper.
pub fn rrf_fuse(rankings: &[Vec<String>], k: f64) -> Vec<String> {
    let mut scores: HashMap<&str, f64> = HashMap::new();
    for ranking in rankings {
        for (zero_based, id) in ranking.iter().enumerate() {
            let position = zero_based.saturating_add(1) as f64;
            *scores.entry(id.as_str()).or_insert(0.0) += 1.0 / (k + position);
        }
    }
    let mut fused: Vec<(&str, f64)> = scores.into_iter().collect();
    fused.sort_by(|a, b| b.1.total_cmp(&a.1).then_with(|| a.0.cmp(b.0)));
    fused.into_iter().map(|(id, _)| id.to_owned()).collect()
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]
mod tests {
    use super::*;

    fn ids(items: &[&str]) -> Vec<String> {
        items.iter().map(|s| (*s).to_owned()).collect()
    }

    fn set(items: &[&str]) -> HashSet<String> {
        items.iter().map(|s| (*s).to_owned()).collect()
    }

    #[test]
    fn first_hit_rank_is_one_based() {
        let ranking = ids(&["a", "b", "c"]);
        assert_eq!(first_hit_rank(&ranking, &set(&["a"])), Some(1));
        assert_eq!(first_hit_rank(&ranking, &set(&["c"])), Some(3));
    }

    #[test]
    fn first_hit_rank_takes_best_of_several_expected() {
        let ranking = ids(&["a", "b", "c"]);
        assert_eq!(first_hit_rank(&ranking, &set(&["c", "b"])), Some(2));
    }

    #[test]
    fn first_hit_rank_none_when_absent() {
        assert_eq!(first_hit_rank(&ids(&["a"]), &set(&["z"])), None);
    }

    #[test]
    fn recall_counts_ranks_within_k_only() {
        let ranks = [Some(1), Some(3), Some(6), None];
        assert!((recall_at(&ranks, 1) - 0.25).abs() < 1e-9);
        assert!((recall_at(&ranks, 3) - 0.5).abs() < 1e-9);
        assert!((recall_at(&ranks, 5) - 0.5).abs() < 1e-9);
    }

    #[test]
    fn mrr_averages_reciprocal_ranks_with_miss_as_zero() {
        let ranks = [Some(1), Some(2), None, None];
        assert!((mrr(&ranks) - 0.375).abs() < 1e-9);
    }

    #[test]
    fn empty_ranks_score_zero_not_nan() {
        assert!(recall_at(&[], 3).abs() < 1e-9);
        assert!(mrr(&[]).abs() < 1e-9);
    }

    #[test]
    fn rrf_promotes_items_ranked_well_by_both_lists() {
        let fused = rrf_fuse(&[ids(&["b", "a", "c"]), ids(&["b", "c", "a"])], 60.0);
        assert_eq!(fused, ids(&["b", "a", "c"]));
    }

    #[test]
    fn rrf_breaks_ties_by_id_for_determinism() {
        let fused = rrf_fuse(&[ids(&["b"]), ids(&["a"])], 60.0);
        assert_eq!(fused, ids(&["a", "b"]));
    }

    #[test]
    fn rrf_keeps_items_present_in_only_one_list() {
        let fused = rrf_fuse(&[ids(&["a"]), ids(&["b"])], 60.0);
        assert_eq!(fused.len(), 2);
    }
}
