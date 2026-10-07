use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

use serde::Deserialize;
use thiserror::Error;

use crate::corpus::Chunk;

#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub struct Query {
    pub q: String,
    /// Any one of these chunk ids counts as a hit.
    pub expect: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct QueryFile {
    queries: Vec<Query>,
}

#[derive(Debug, Error)]
pub enum QueryError {
    #[error("read {path}: {source}")]
    Read {
        path: PathBuf,
        source: std::io::Error,
    },
    #[error("parse {path}: {source}")]
    Parse {
        path: PathBuf,
        source: serde_json::Error,
    },
    #[error("query {query:?} has an empty `expect` list")]
    EmptyExpect { query: String },
}

pub fn load(path: &Path) -> Result<Vec<Query>, QueryError> {
    let raw = fs::read_to_string(path).map_err(|source| QueryError::Read {
        path: path.to_owned(),
        source,
    })?;
    let file: QueryFile = serde_json::from_str(&raw).map_err(|source| QueryError::Parse {
        path: path.to_owned(),
        source,
    })?;
    if let Some(query) = file.queries.iter().find(|q| q.expect.is_empty()) {
        return Err(QueryError::EmptyExpect {
            query: query.q.clone(),
        });
    }
    Ok(file.queries)
}

/// `(query, expected id)` pairs whose id is not in the corpus: stale ground truth.
pub fn unknown_expectations(queries: &[Query], chunks: &[Chunk]) -> Vec<(String, String)> {
    let known: HashSet<&str> = chunks.iter().map(|c| c.id.as_str()).collect();
    queries
        .iter()
        .flat_map(|query| {
            query
                .expect
                .iter()
                .filter(|id| !known.contains(id.as_str()))
                .map(|id| (query.q.clone(), id.clone()))
        })
        .collect()
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]
mod tests {
    use super::*;

    fn write(dir: &tempfile::TempDir, body: &str) -> PathBuf {
        let path = dir.path().join("q.json");
        fs::write(&path, body).unwrap();
        path
    }

    #[test]
    fn loads_queries_with_expected_ids() {
        let dir = tempfile::tempdir().unwrap();
        let path = write(&dir, r#"{"queries":[{"q":"hi","expect":["a.md","b.md"]}]}"#);
        assert_eq!(
            load(&path).unwrap(),
            [Query {
                q: "hi".to_owned(),
                expect: vec!["a.md".to_owned(), "b.md".to_owned()],
            }]
        );
    }

    #[test]
    fn empty_expect_is_rejected_naming_the_query() {
        let dir = tempfile::tempdir().unwrap();
        let path = write(&dir, r#"{"queries":[{"q":"lonely","expect":[]}]}"#);
        let err = load(&path).unwrap_err();
        assert!(err.to_string().contains("lonely"));
    }

    #[test]
    fn malformed_json_error_names_the_file() {
        let dir = tempfile::tempdir().unwrap();
        let path = write(&dir, "{not json");
        assert!(load(&path).unwrap_err().to_string().contains("q.json"));
    }

    #[test]
    fn unknown_expectations_lists_only_missing_ids() {
        let chunks = [Chunk {
            id: "a.md".to_owned(),
            title: String::new(),
            text: String::new(),
        }];
        let queries = [Query {
            q: "x".to_owned(),
            expect: vec!["a.md".to_owned(), "gone.md".to_owned()],
        }];
        assert_eq!(
            unknown_expectations(&queries, &chunks),
            [("x".to_owned(), "gone.md".to_owned())]
        );
    }
}
