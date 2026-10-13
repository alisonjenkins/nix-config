//! Error types. One enum per fallible operation, with a variant per failure
//! site carrying the path, offset or length that identifies it.

use std::io;
use std::path::PathBuf;

use thiserror::Error;

/// Failures when building, storing or loading a [`crate::snapshot::ConfigSnapshot`].
#[derive(Debug, Error)]
pub enum SnapshotError {
    #[error("configuration is {got} bytes, expected {expected}")]
    Length { got: usize, expected: usize },

    #[error("{path}: sha256 of the bytes is {actual}, the sidecar says {expected}")]
    HashMismatch {
        path: PathBuf,
        expected: String,
        actual: String,
    },

    #[error("cannot read {path}")]
    Read {
        path: PathBuf,
        #[source]
        source: io::Error,
    },

    #[error("cannot write {path}")]
    Write {
        path: PathBuf,
        #[source]
        source: io::Error,
    },

    #[error("cannot parse the metadata in {path}")]
    MetaParse {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },

    #[error("cannot serialise the snapshot metadata")]
    MetaSerialize {
        #[source]
        source: serde_json::Error,
    },

    #[error("redacting {len} bytes at offset {offset} runs past the end of the configuration")]
    RedactRange { offset: usize, len: usize },
}
