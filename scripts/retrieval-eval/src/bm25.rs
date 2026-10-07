use std::collections::HashMap;

use crate::corpus::Chunk;
use crate::retriever::{rank_by_score, RetrieveError, Retriever};

const K1: f64 = 1.5;
const B: f64 = 0.75;

pub fn tokenize(text: &str) -> Vec<String> {
    text.split(|c: char| !(c.is_alphanumeric() || c == '_'))
        .filter(|term| !term.is_empty())
        .map(str::to_lowercase)
        .collect()
}

#[derive(Default)]
pub struct Bm25 {
    ids: Vec<String>,
    term_freqs: Vec<HashMap<String, f64>>,
    lengths: Vec<f64>,
    avg_len: f64,
    doc_freq: HashMap<String, f64>,
    indexed: bool,
}

impl Bm25 {
    pub fn new() -> Self {
        Self::default()
    }

    fn score_doc(&self, terms: &[String], freqs: &HashMap<String, f64>, len: f64, n: f64) -> f64 {
        terms
            .iter()
            .map(|term| {
                let tf = freqs.get(term).copied().unwrap_or(0.0);
                if tf == 0.0 {
                    return 0.0;
                }
                let df = self.doc_freq.get(term).copied().unwrap_or(0.0);
                let idf = (1.0 + (n - df + 0.5) / (df + 0.5)).ln();
                let norm = 1.0 - B + B * len / self.avg_len;
                idf * tf * (K1 + 1.0) / (tf + K1 * norm)
            })
            .sum()
    }
}

impl Retriever for Bm25 {
    fn name(&self) -> &str {
        "bm25"
    }

    fn index(&mut self, chunks: &[Chunk]) -> Result<(), RetrieveError> {
        *self = Self::default();
        for chunk in chunks {
            let tokens = tokenize(&chunk.document());
            let mut freqs: HashMap<String, f64> = HashMap::new();
            for token in &tokens {
                *freqs.entry(token.clone()).or_insert(0.0) += 1.0;
            }
            for term in freqs.keys() {
                *self.doc_freq.entry(term.clone()).or_insert(0.0) += 1.0;
            }
            self.ids.push(chunk.id.clone());
            self.lengths.push(tokens.len() as f64);
            self.term_freqs.push(freqs);
        }
        let total: f64 = self.lengths.iter().sum();
        self.avg_len = if chunks.is_empty() {
            0.0
        } else {
            total / chunks.len() as f64
        };
        self.indexed = true;
        Ok(())
    }

    fn rank(&self, query: &str) -> Result<Vec<String>, RetrieveError> {
        if !self.indexed {
            return Err(RetrieveError::NotIndexed);
        }
        let terms = tokenize(query);
        let n = self.ids.len() as f64;
        let scores: Vec<f64> = self
            .term_freqs
            .iter()
            .zip(&self.lengths)
            .map(|(freqs, len)| self.score_doc(&terms, freqs, *len, n))
            .collect();
        Ok(rank_by_score(&self.ids, &scores))
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]
mod tests {
    use super::*;

    fn chunk(id: &str, text: &str) -> Chunk {
        Chunk {
            id: id.to_owned(),
            title: String::new(),
            text: text.to_owned(),
        }
    }

    fn indexed(chunks: &[Chunk]) -> Bm25 {
        let mut bm25 = Bm25::new();
        bm25.index(chunks).unwrap();
        bm25
    }

    #[test]
    fn tokenize_lowercases_and_splits_on_punctuation() {
        assert_eq!(
            tokenize("Examplarr→exd: ::1 (IPv6) foo_bar"),
            ["examplarr", "exd", "1", "ipv6", "foo_bar"]
        );
    }

    #[test]
    fn doc_containing_the_query_term_ranks_first() {
        let bm25 = indexed(&[
            chunk("cats", "cats purr softly"),
            chunk("dogs", "dogs bark loudly"),
            chunk("birds", "birds sing"),
        ]);
        let ranked = bm25.rank("bark").unwrap();
        assert_eq!(ranked.first().map(String::as_str), Some("dogs"));
        assert_eq!(ranked.len(), 3);
    }

    #[test]
    fn rare_term_outweighs_common_term() {
        let bm25 = indexed(&[
            chunk("a", "the the the the zebra"),
            chunk("b", "the the the the the"),
            chunk("c", "the the the the the"),
        ]);
        assert_eq!(
            bm25.rank("the zebra").unwrap().first().map(String::as_str),
            Some("a")
        );
    }

    #[test]
    fn query_with_no_matches_still_returns_every_chunk_in_id_order() {
        let bm25 = indexed(&[chunk("b", "x"), chunk("a", "y")]);
        assert_eq!(bm25.rank("zzz").unwrap(), ["a", "b"].map(str::to_owned));
    }

    #[test]
    fn rank_before_index_is_an_error() {
        assert!(matches!(
            Bm25::new().rank("x"),
            Err(RetrieveError::NotIndexed)
        ));
    }

    #[test]
    fn reindexing_replaces_the_previous_corpus() {
        let mut bm25 = indexed(&[chunk("old", "alpha")]);
        bm25.index(&[chunk("new", "beta")]).unwrap();
        assert_eq!(bm25.rank("beta").unwrap(), ["new".to_owned()]);
    }
}
