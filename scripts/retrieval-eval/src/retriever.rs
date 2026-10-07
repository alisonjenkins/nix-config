use thiserror::Error;

use crate::corpus::Chunk;

#[derive(Debug, Error)]
pub enum RetrieveError {
    #[error("rank() called before index()")]
    NotIndexed,
    #[error("embedding request to {url} failed: {source}")]
    Http {
        url: String,
        source: Box<ureq::Error>,
    },
    #[error("embedding server {url} sent a bad response: {detail}")]
    BadResponse { url: String, detail: String },
}

pub trait Retriever {
    fn name(&self) -> &str;

    fn index(&mut self, chunks: &[Chunk]) -> Result<(), RetrieveError>;

    /// All chunk ids, best first.
    fn rank(&self, query: &str) -> Result<Vec<String>, RetrieveError>;
}

/// Ids with their scores, descending, ties broken by id so runs are reproducible.
pub fn rank_scored(ids: &[String], scores: &[f64]) -> Vec<(String, f64)> {
    let mut scored: Vec<(String, f64)> = ids.iter().cloned().zip(scores.iter().copied()).collect();
    scored.sort_by(|a, b| b.1.total_cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
    scored
}

pub fn rank_by_score(ids: &[String], scores: &[f64]) -> Vec<String> {
    rank_scored(ids, scores)
        .into_iter()
        .map(|(id, _)| id)
        .collect()
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]
mod tests {
    use super::*;

    #[test]
    fn rank_by_score_orders_descending_and_breaks_ties_by_id() {
        let ids = ["b", "a", "c"].map(str::to_owned);
        let ranked = rank_by_score(&ids, &[1.0, 1.0, 2.0]);
        assert_eq!(ranked, ["c", "a", "b"].map(str::to_owned));
    }
}
