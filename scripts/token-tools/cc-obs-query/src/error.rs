//! One variant per failure site; `report()` turns each into the single JSON object
//! `{error, operation, input, fix}` the CLI prints on stderr.
use std::io;
use std::path::PathBuf;

use serde::Serialize;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("cannot locate the endpoints file: neither CC_OBS_ENDPOINTS, XDG_CONFIG_HOME nor HOME is set")]
    EndpointsLocate,
    #[error("cannot read the endpoints file {path}: {source}")]
    EndpointsRead { path: PathBuf, source: io::Error },
    #[error("the endpoints file {path} is not valid: {source}")]
    EndpointsParse {
        path: PathBuf,
        source: serde_json::Error,
    },
    #[error("{operation} failed: {source}")]
    Http {
        operation: &'static str,
        url: String,
        source: Box<ureq::Error>,
    },
    #[error("{operation}: the answer from {url} is not JSON: {source}")]
    ResponseJson {
        operation: &'static str,
        url: String,
        source: serde_json::Error,
    },
    #[error("{operation}: the backend answered {status}: {detail}")]
    BackendRejected {
        operation: &'static str,
        status: String,
        detail: String,
    },
    #[error("{operation}: unexpected response shape: {reason}")]
    ResponseShape {
        operation: &'static str,
        reason: String,
    },
    #[error("invalid value {value:?} for {flag}: {reason}")]
    BadArgument {
        flag: &'static str,
        value: String,
        reason: String,
    },
    #[error("{message}")]
    Usage { message: String, input: String },
    #[error("cannot read the question pack {path}: {source}")]
    PackRead { path: PathBuf, source: io::Error },
    #[error("the question pack {path} is not valid YAML for a pack: {source}")]
    PackParse {
        path: PathBuf,
        source: serde_yaml::Error,
    },
    #[error("the question pack {path} is invalid: {reason}")]
    PackInvalid { path: PathBuf, reason: String },
    #[error("unknown question {id:?}")]
    UnknownQuestion { id: String, known: String },
    #[error("question {id:?} has an unusable query command {command:?}: {reason}")]
    QueryCommand {
        id: String,
        command: String,
        reason: String,
    },
    #[error("cannot read the decisions in {path}: {source}")]
    DecisionsRead { path: PathBuf, source: io::Error },
    #[error("decision record {path} is invalid: {reason}")]
    DecisionInvalid { path: PathBuf, reason: String },
    #[error("cannot read the digest {path}: {source}")]
    DigestRead { path: PathBuf, source: io::Error },
    #[error("the digest {path} is not JSON: {source}")]
    DigestParse {
        path: PathBuf,
        source: serde_json::Error,
    },
    #[error("the digest is invalid: {}", problems.join("; "))]
    DigestInvalid { problems: Vec<String> },
    #[error("cannot write the digest to {path}: {source}")]
    DigestWrite { path: PathBuf, source: io::Error },
    #[error("cannot serialise the output: {source}")]
    Render { source: serde_json::Error },
}

#[derive(Debug, Serialize, PartialEq, Eq)]
pub struct ErrorReport {
    pub error: String,
    pub operation: String,
    pub input: String,
    pub fix: String,
}

impl Error {
    pub fn report(&self) -> ErrorReport {
        let (operation, input, fix) = match self {
            Self::EndpointsLocate => (
                "locate endpoints file".to_owned(),
                String::new(),
                "set CC_OBS_ENDPOINTS to the endpoints.json the observability-stack module writes".to_owned(),
            ),
            Self::EndpointsRead { path, .. } | Self::EndpointsParse { path, .. } => (
                "load endpoints file".to_owned(),
                path.display().to_string(),
                "set CC_OBS_ENDPOINTS to a readable endpoints.json, or enable the observability-stack module so it writes $XDG_CONFIG_HOME/cc-obs/endpoints.json".to_owned(),
            ),
            Self::Http { operation, url, .. } | Self::ResponseJson { operation, url, .. } => (
                (*operation).to_owned(),
                url.clone(),
                "check the stack is running with `cc-obs-query health` and that the URL in endpoints.json is right".to_owned(),
            ),
            Self::BackendRejected { operation, detail, .. } => (
                (*operation).to_owned(),
                detail.clone(),
                "fix the query or flag named in the detail, then retry".to_owned(),
            ),
            Self::ResponseShape { operation, .. } => (
                (*operation).to_owned(),
                String::new(),
                "the store version may not match this tool; check `cc-obs-query health`".to_owned(),
            ),
            Self::BadArgument { flag, value, .. } => (
                format!("parse {flag}"),
                format!("{flag} {value}"),
                match *flag {
                    "--since" => "use a number and a unit, e.g. --since 7d (s, m, h, d, w)".to_owned(),
                    "--a" | "--b" | "--until" => "use dates like 2026-09-01..2026-09-08 (or 2026-09-08 for --until)".to_owned(),
                    _ => format!("pass a valid value for {flag}; see --help"),
                },
            ),
            Self::Usage { input, .. } => (
                "parse arguments".to_owned(),
                input.clone(),
                "run `cc-obs-query --help` for the commands and flags".to_owned(),
            ),
            Self::PackRead { path, .. } | Self::PackParse { path, .. } | Self::PackInvalid { path, .. } => (
                "load question pack".to_owned(),
                path.display().to_string(),
                "fix the pack (see specs/007-local-observability-stack/contracts/review-formats.md) or pass --pack".to_owned(),
            ),
            Self::UnknownQuestion { id, known } => (
                "find question".to_owned(),
                id.clone(),
                format!("use one of: {known}"),
            ),
            Self::QueryCommand { id, command, .. } => (
                "parse question query".to_owned(),
                format!("{id}: {command}"),
                "make the pack's query.command a valid cc-obs-query invocation".to_owned(),
            ),
            Self::DecisionsRead { path, .. } | Self::DecisionInvalid { path, .. } => (
                "load decision records".to_owned(),
                path.display().to_string(),
                "fix the front matter of the record (see review-formats.md) or pass --decisions".to_owned(),
            ),
            Self::DigestRead { path, .. } | Self::DigestParse { path, .. } | Self::DigestWrite { path, .. } => (
                "handle digest file".to_owned(),
                path.display().to_string(),
                "pass a readable JSON file to --write and a writable path to --out".to_owned(),
            ),
            Self::DigestInvalid { problems } => (
                "validate digest".to_owned(),
                problems.first().cloned().unwrap_or_default(),
                "fix every listed problem and submit again; cite only references that exist".to_owned(),
            ),
            Self::Render { .. } => (
                "render output".to_owned(),
                String::new(),
                "report this as a bug".to_owned(),
            ),
        };
        let fix = match self {
            Self::BadArgument { reason, .. } => format!("{fix} ({reason})"),
            _ => fix,
        };
        ErrorReport {
            error: self.to_string(),
            operation,
            input,
            fix,
        }
    }
}
