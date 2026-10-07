use std::collections::{HashMap, HashSet};
use std::time::Instant;

use serde::Serialize;

use crate::corpus::Chunk;
use crate::metrics::{first_hit_rank, mrr, recall_at, rrf_fuse};
use crate::queries::Query;
use crate::retriever::{RetrieveError, Retriever};

/// Constant from the original RRF paper.
const RRF_K: f64 = 60.0;
/// Rough bytes per token for English prose and code; only used to size injected context.
const BYTES_PER_TOKEN: f64 = 4.0;
const TOP_FOR_CONTEXT: usize = 3;

/// One retriever's full ranking per query, plus what it cost to produce.
#[derive(Debug, Clone)]
pub struct Run {
    pub name: String,
    pub rankings: Vec<Vec<String>>,
    pub index_secs: f64,
    pub query_ms: f64,
}

#[derive(Debug, Clone, Serialize)]
pub struct Scores {
    pub name: String,
    pub recall_at_1: f64,
    pub recall_at_3: f64,
    pub recall_at_5: f64,
    pub mrr: f64,
    /// Mean tokens injected if the top 3 chunks are loaded, vs. `corpus_tokens` for everything.
    pub mean_top3_tokens: f64,
    pub corpus_tokens: f64,
    pub index_secs: f64,
    pub query_ms: f64,
    /// 1-based rank of the first expected chunk per query; `None` = not found.
    pub ranks: Vec<Option<usize>>,
}

pub fn run(
    retriever: &mut dyn Retriever,
    chunks: &[Chunk],
    queries: &[Query],
) -> Result<Run, RetrieveError> {
    let started = Instant::now();
    retriever.index(chunks)?;
    let index_secs = started.elapsed().as_secs_f64();

    let started = Instant::now();
    let rankings = queries
        .iter()
        .map(|query| retriever.rank(&query.q))
        .collect::<Result<Vec<_>, _>>()?;
    let query_ms = if queries.is_empty() {
        0.0
    } else {
        started.elapsed().as_secs_f64() * 1000.0 / queries.len() as f64
    };
    Ok(Run {
        name: retriever.name().to_owned(),
        rankings,
        index_secs,
        query_ms,
    })
}

/// Fuse several runs offline from their stored rankings, with no re-embedding.
pub fn fuse(runs: &[&Run]) -> Option<Run> {
    let first = runs.first()?;
    let rankings = (0..first.rankings.len())
        .map(|i| {
            let per_run: Vec<Vec<String>> = runs
                .iter()
                .filter_map(|r| r.rankings.get(i).cloned())
                .collect();
            rrf_fuse(&per_run, RRF_K)
        })
        .collect();
    let names: Vec<&str> = runs.iter().map(|r| r.name.as_str()).collect();
    Some(Run {
        name: format!("rrf({})", names.join("+")),
        rankings,
        index_secs: runs.iter().map(|r| r.index_secs).sum(),
        query_ms: runs.iter().map(|r| r.query_ms).sum(),
    })
}

pub fn score(run: &Run, chunks: &[Chunk], queries: &[Query]) -> Scores {
    let bytes: HashMap<&str, usize> = chunks
        .iter()
        .map(|c| (c.id.as_str(), c.document().len()))
        .collect();
    let to_tokens = |total_bytes: f64| total_bytes / BYTES_PER_TOKEN;

    let ranks: Vec<Option<usize>> = run
        .rankings
        .iter()
        .zip(queries)
        .map(|(ranking, query)| {
            let expected: HashSet<String> = query.expect.iter().cloned().collect();
            first_hit_rank(ranking, &expected)
        })
        .collect();

    let top_bytes: Vec<f64> = run
        .rankings
        .iter()
        .map(|ranking| {
            ranking
                .iter()
                .take(TOP_FOR_CONTEXT)
                .filter_map(|id| bytes.get(id.as_str()))
                .map(|b| *b as f64)
                .sum()
        })
        .collect();
    let mean_top_bytes = if top_bytes.is_empty() {
        0.0
    } else {
        top_bytes.iter().sum::<f64>() / top_bytes.len() as f64
    };
    let corpus_bytes: f64 = bytes.values().map(|b| *b as f64).sum();

    Scores {
        name: run.name.clone(),
        recall_at_1: recall_at(&ranks, 1),
        recall_at_3: recall_at(&ranks, 3),
        recall_at_5: recall_at(&ranks, 5),
        mrr: mrr(&ranks),
        mean_top3_tokens: to_tokens(mean_top_bytes),
        corpus_tokens: to_tokens(corpus_bytes),
        index_secs: run.index_secs,
        query_ms: run.query_ms,
        ranks,
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]
mod tests {
    use super::*;
    use crate::bm25::Bm25;

    fn chunk(id: &str, text: &str) -> Chunk {
        Chunk {
            id: id.to_owned(),
            title: String::new(),
            text: text.to_owned(),
        }
    }

    fn query(q: &str, expect: &[&str]) -> Query {
        Query {
            q: q.to_owned(),
            expect: expect.iter().map(|s| (*s).to_owned()).collect(),
        }
    }

    fn corpus() -> Vec<Chunk> {
        vec![
            chunk("cats", "cats purr softly"),
            chunk("dogs", "dogs bark loudly"),
            chunk("birds", "birds sing songs"),
        ]
    }

    #[test]
    fn bm25_run_scores_hits_and_misses() {
        let chunks = corpus();
        let queries = [query("bark", &["dogs"]), query("purr", &["birds"])];
        let result = run(&mut Bm25::new(), &chunks, &queries).unwrap();
        let scores = score(&result, &chunks, &queries);
        assert_eq!(scores.ranks[0], Some(1));
        assert!(scores.ranks[1].is_some_and(|r| r > 1));
        assert!((scores.recall_at_1 - 0.5).abs() < 1e-9);
        assert!((scores.recall_at_5 - 1.0).abs() < 1e-9);
    }

    #[test]
    fn fuse_combines_stored_rankings_and_names_the_parts() {
        let a = Run {
            name: "a".to_owned(),
            rankings: vec![vec!["x".to_owned(), "y".to_owned()]],
            index_secs: 1.0,
            query_ms: 2.0,
        };
        let b = Run {
            name: "b".to_owned(),
            rankings: vec![vec!["x".to_owned(), "y".to_owned()]],
            index_secs: 3.0,
            query_ms: 4.0,
        };
        let fused = fuse(&[&a, &b]).unwrap();
        assert_eq!(fused.name, "rrf(a+b)");
        assert_eq!(fused.rankings, [["x", "y"].map(str::to_owned).to_vec()]);
        assert!((fused.index_secs - 4.0).abs() < 1e-9);
    }

    #[test]
    fn fuse_of_nothing_is_none() {
        assert!(fuse(&[]).is_none());
    }

    #[test]
    fn top3_tokens_are_far_below_corpus_tokens() {
        let chunks: Vec<Chunk> = (0..10)
            .map(|i| chunk(&format!("c{i}"), &"word ".repeat(100)))
            .collect();
        let queries = [query("word", &["c0"])];
        let result = run(&mut Bm25::new(), &chunks, &queries).unwrap();
        let scores = score(&result, &chunks, &queries);
        assert!((scores.mean_top3_tokens * 10.0 - scores.corpus_tokens * 3.0).abs() < 1e-6);
    }
}
