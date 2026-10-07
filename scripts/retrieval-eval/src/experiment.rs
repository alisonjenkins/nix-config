//! Scoring strategies for the retrieval experiments: combining the scores of
//! several views of the same memories, and choosing an injection threshold per
//! strategy so strategies with different score scales can be compared fairly.
use std::collections::HashMap;

use crate::bench::{gate_row, Case};
use crate::corpus::memory_file_of;

/// File-level score: the best score among a file's chunks, best file first.
pub fn collapse_max(scored: &[(String, f64)]) -> Vec<(String, f64)> {
    let mut best: HashMap<&str, f64> = HashMap::new();
    for (id, score) in scored {
        let entry = best.entry(memory_file_of(id)).or_insert(f64::NEG_INFINITY);
        if *score > *entry {
            *entry = *score;
        }
    }
    let mut files: Vec<(String, f64)> = best
        .into_iter()
        .map(|(file, score)| (file.to_owned(), score))
        .collect();
    sort_best_first(&mut files);
    files
}

fn sort_best_first(scored: &mut [(String, f64)]) {
    scored.sort_by(|a, b| b.1.total_cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
}

/// Standard scores within one query's list, so lists from different signals
/// are comparable. A list with no spread becomes all zeros.
pub fn zscore(scored: &[(String, f64)]) -> Vec<(String, f64)> {
    let n = scored.len() as f64;
    if scored.is_empty() {
        return Vec::new();
    }
    let mean = scored.iter().map(|(_, s)| s).sum::<f64>() / n;
    let variance = scored.iter().map(|(_, s)| (s - mean).powi(2)).sum::<f64>() / n;
    let sd = variance.sqrt();
    scored
        .iter()
        .map(|(id, s)| {
            let z = if sd < 1e-12 { 0.0 } else { (s - mean) / sd };
            (id.clone(), z)
        })
        .collect()
}

#[derive(Debug, Clone, PartialEq)]
pub enum Combine {
    Mean,
    Max,
    /// One weight per list, summed.
    Weighted(Vec<f64>),
}

/// Combines per-file scores from several lists. A file missing from a list takes
/// that list's lowest score. Best first, ties by id.
pub fn combine(lists: &[Vec<(String, f64)>], how: &Combine) -> Vec<(String, f64)> {
    let maps: Vec<HashMap<&str, f64>> = lists
        .iter()
        .map(|l| l.iter().map(|(id, s)| (id.as_str(), *s)).collect())
        .collect();
    let floors: Vec<f64> = lists
        .iter()
        .map(|l| l.iter().map(|(_, s)| *s).fold(f64::INFINITY, f64::min))
        .collect();
    let mut ids: Vec<&str> = lists
        .iter()
        .flat_map(|l| l.iter().map(|(id, _)| id.as_str()))
        .collect();
    ids.sort_unstable();
    ids.dedup();
    let mut out: Vec<(String, f64)> = ids
        .into_iter()
        .map(|id| {
            let values: Vec<f64> = maps
                .iter()
                .zip(&floors)
                .map(|(m, floor)| m.get(id).copied().unwrap_or(*floor))
                .collect();
            let score = match how {
                Combine::Mean => values.iter().sum::<f64>() / values.len().max(1) as f64,
                Combine::Max => values.iter().copied().fold(f64::NEG_INFINITY, f64::max),
                Combine::Weighted(weights) => values.iter().zip(weights).map(|(v, w)| v * w).sum(),
            };
            (id.to_owned(), score)
        })
        .collect();
    sort_best_first(&mut out);
    out
}

/// The injection threshold that maximises `recall - fp_weight * mean false
/// injection rate` over `cases`, preferring the higher threshold on a tie.
pub fn pick_threshold(cases: &[Case], top: usize, fp_weight: f64) -> f64 {
    let mut candidates: Vec<f64> = cases
        .iter()
        .filter_map(|c| c.scored.first().map(|(_, s)| *s))
        .collect();
    candidates.sort_by(f64::total_cmp);
    candidates.dedup();
    let mut best: Option<(f64, f64)> = None;
    for threshold in candidates {
        let row = gate_row(cases, threshold, top, &|_| 0.0);
        let false_rate = (row.false_injection_offtopic + row.false_injection_adjacent) / 2.0;
        let utility = row.recall - fp_weight * false_rate;
        if best.is_none_or(|(u, _)| utility >= u - 1e-12) {
            best = Some((utility, threshold));
        }
    }
    best.map_or(0.0, |(_, threshold)| threshold)
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]
mod tests {
    use super::*;
    use crate::bench::Kind;

    fn list(items: &[(&str, f64)]) -> Vec<(String, f64)> {
        items.iter().map(|(i, s)| ((*i).to_owned(), *s)).collect()
    }

    fn ids(scored: &[(String, f64)]) -> Vec<&str> {
        scored.iter().map(|(i, _)| i.as_str()).collect()
    }

    #[test]
    fn collapse_keeps_each_files_best_chunk_and_sorts() {
        let scored = list(&[
            ("a.md#1", 0.5),
            ("b.md#d", 0.9),
            ("a.md#d", 0.7),
            ("b.md#2", 0.2),
        ]);
        let files = collapse_max(&scored);
        assert_eq!(files, list(&[("b.md", 0.9), ("a.md", 0.7)]));
    }

    #[test]
    fn collapse_leaves_plain_file_ids_alone() {
        assert_eq!(
            collapse_max(&list(&[("a.md", 1.0)])),
            list(&[("a.md", 1.0)])
        );
    }

    #[test]
    fn zscore_centres_and_scales_and_keeps_order() {
        let z = zscore(&list(&[("a", 1.0), ("b", 2.0), ("c", 3.0)]));
        assert_eq!(ids(&z), ["a", "b", "c"]);
        assert!(z[1].1.abs() < 1e-9);
        assert!((z[0].1 + z[2].1).abs() < 1e-9);
        assert!((z[2].1 - 1.224_744_871_4).abs() < 1e-6);
    }

    #[test]
    fn zscore_of_a_flat_list_is_zero_not_nan() {
        let z = zscore(&list(&[("a", 0.5), ("b", 0.5)]));
        assert!(z.iter().all(|(_, s)| *s == 0.0));
    }

    #[test]
    fn combine_mean_max_and_weighted() {
        let a = list(&[("x", 1.0), ("y", 0.0)]);
        let b = list(&[("x", 0.0), ("y", 1.0)]);
        let mean = combine(&[a.clone(), b.clone()], &Combine::Mean);
        assert!((mean[0].1 - 0.5).abs() < 1e-9 && (mean[1].1 - 0.5).abs() < 1e-9);
        let max = combine(&[a.clone(), b.clone()], &Combine::Max);
        assert!((max[0].1 - 1.0).abs() < 1e-9);
        let weighted = combine(&[a, b], &Combine::Weighted(vec![3.0, 1.0]));
        assert_eq!(ids(&weighted), ["x", "y"]);
        assert!((weighted[0].1 - 3.0).abs() < 1e-9);
    }

    #[test]
    fn combine_fills_a_missing_file_with_that_lists_minimum() {
        let a = list(&[("x", 0.9), ("y", 0.1)]);
        let b = list(&[("x", 0.5)]);
        let mean = combine(&[a, b], &Combine::Mean);
        let y = mean.iter().find(|(i, _)| i == "y").unwrap().1;
        assert!((y - (0.1 + 0.5) / 2.0).abs() < 1e-9);
    }

    #[test]
    fn combine_breaks_ties_by_id() {
        let l = list(&[("b", 1.0), ("a", 1.0)]);
        assert_eq!(ids(&combine(&[l], &Combine::Max)), ["a", "b"]);
    }

    fn case(kind: Kind, expect: &[&str], scored: &[(&str, f64)]) -> Case {
        Case {
            kind,
            expect: expect.iter().map(|s| (*s).to_owned()).collect(),
            scored: list(scored),
        }
    }

    #[test]
    fn pick_threshold_separates_relevant_from_noise() {
        let cases = [
            case(Kind::Relevant, &["a"], &[("a", 0.9)]),
            case(Kind::Relevant, &["b"], &[("b", 0.8)]),
            case(Kind::Offtopic, &[], &[("x", 0.5)]),
            case(Kind::Adjacent, &[], &[("y", 0.4)]),
        ];
        let t = pick_threshold(&cases, 3, 0.5);
        assert!(t > 0.5 && t <= 0.8, "threshold {t}");
    }

    #[test]
    fn pick_threshold_prefers_the_higher_value_on_a_tie() {
        let cases = [
            case(Kind::Relevant, &["a"], &[("a", 0.9)]),
            case(Kind::Offtopic, &[], &[("x", 0.1)]),
        ];
        // Any threshold in (0.1, 0.9] scores the same; the higher is chosen.
        assert!((pick_threshold(&cases, 3, 0.5) - 0.9).abs() < 1e-9);
    }

    #[test]
    fn pick_threshold_of_no_cases_is_zero() {
        assert!(pick_threshold(&[], 3, 0.5).abs() < 1e-9);
    }
}
