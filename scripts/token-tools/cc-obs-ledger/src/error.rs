use std::io;
use std::path::PathBuf;

#[derive(Debug, thiserror::Error)]
pub enum LedgerError {
    #[error("creating directory {path}: {source}")]
    CreateDir { path: PathBuf, source: io::Error },
    #[error("reading {path}: {source}")]
    Read { path: PathBuf, source: io::Error },
    #[error("writing {path}: {source}")]
    Write { path: PathBuf, source: io::Error },
    #[error("reading hook input from stdin: {0}")]
    Stdin(io::Error),
    #[error("hook input is not the expected JSON: {0}")]
    HookJson(serde_json::Error),
    #[error("hook input has no {field}")]
    MissingField { field: &'static str },
    #[error("parsing {path}: {source}")]
    ParseFile {
        path: PathBuf,
        source: serde_json::Error,
    },
    #[error("starting the detached sender {exe}: {source}")]
    Spawn { exe: PathBuf, source: io::Error },
    #[error("formatting a timestamp: {0}")]
    Time(time::error::Format),
}
