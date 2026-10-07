use std::fmt::Write;

use crate::eval::Scores;
use crate::queries::Query;

pub fn markdown_table(scores: &[Scores]) -> String {
    let mut out = String::from(
        "| retriever | R@1 | R@3 | R@5 | MRR | top-3 tokens | index s | ms/query |\n\
         |---|---|---|---|---|---|---|---|\n",
    );
    for s in scores {
        let _ = writeln!(
            out,
            "| {} | {:.2} | {:.2} | {:.2} | {:.3} | {:.0} | {:.1} | {:.1} |",
            s.name,
            s.recall_at_1,
            s.recall_at_3,
            s.recall_at_5,
            s.mrr,
            s.mean_top3_tokens,
            s.index_secs,
            s.query_ms
        );
    }
    out
}

/// Queries a retriever ranked worse than 3rd, so its failures can be read.
pub fn misses(scores: &Scores, queries: &[Query]) -> String {
    let mut out = format!("misses for {} (rank > 3 or absent):\n", scores.name);
    for (query, rank) in queries.iter().zip(&scores.ranks) {
        if rank.is_none_or(|r| r > 3) {
            let shown = rank.map_or_else(|| "absent".to_owned(), |r| r.to_string());
            let _ = writeln!(
                out,
                "  [{shown}] {} -> {}",
                query.q,
                query.expect.join(" | ")
            );
        }
    }
    out
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]
mod tests {
    use super::*;

    fn scores(name: &str, ranks: Vec<Option<usize>>) -> Scores {
        Scores {
            name: name.to_owned(),
            recall_at_1: 0.5,
            recall_at_3: 0.75,
            recall_at_5: 1.0,
            mrr: 0.6,
            mean_top3_tokens: 900.0,
            corpus_tokens: 9000.0,
            index_secs: 1.25,
            query_ms: 3.5,
            ranks,
        }
    }

    #[test]
    fn table_has_header_and_one_row_per_retriever() {
        let table = markdown_table(&[scores("bm25", vec![]), scores("g2", vec![])]);
        assert_eq!(table.lines().count(), 4);
        assert!(table.contains("| bm25 | 0.50 | 0.75 | 1.00 | 0.600 | 900 | 1.2 | 3.5 |"));
    }

    #[test]
    fn misses_lists_only_rank_over_three_or_absent() {
        let queries = [
            Query {
                q: "good".to_owned(),
                expect: vec!["a".to_owned()],
            },
            Query {
                q: "late".to_owned(),
                expect: vec!["b".to_owned()],
            },
            Query {
                q: "lost".to_owned(),
                expect: vec!["c".to_owned(), "d".to_owned()],
            },
        ];
        let text = misses(&scores("x", vec![Some(2), Some(4), None]), &queries);
        assert!(!text.contains("good"));
        assert!(text.contains("[4] late -> b"));
        assert!(text.contains("[absent] lost -> c | d"));
    }
}
