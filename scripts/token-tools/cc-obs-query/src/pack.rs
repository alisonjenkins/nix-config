//! The review question pack (`docs/token-efficiency/questions.yaml`) and the
//! decision records that refer to it.
use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

use serde::Deserialize;
use sha1::{Digest, Sha1};

use crate::error::Error;

/// Every signal the stack collects that a question may name. A signal named by a
/// question must be in this list; one in no question and not in `retire:` fails
/// `unused-signals`.
pub const COLLECTED_SIGNALS: [&str; 25] = [
    "claude_code.token.usage",
    "claude_code.cost.usage",
    "claude_code.session.count",
    "claude_code.active_time.total",
    "claude_code.lines_of_code.count",
    "claude_code.code_edit_tool.decision",
    "claude_code.tool_result.tool_result_size_bytes",
    "claude_code.tool_result.tool_input_size_bytes",
    "claude_code.tool_result.duration_ms",
    "claude_code.api_request",
    "claude_code.api_error",
    "claude_code.skill_activated",
    "claude_code.subagent_completed.total_tokens",
    "claude_code.compaction.pre_tokens",
    "claude_code.compaction.post_tokens",
    "claude_code.hook_execution.additional_context_chars",
    "cc_obs_ledger_fixed_context_tokens",
    "cc_obs_ledger_context_tokens",
    "cc_obs_ledger_cache_hit_ratio",
    "cc_obs_ledger.session",
    "cc_obs_ledger.tool_call",
    "recall_requests_total",
    "recall_hits_total",
    "recall_latency_seconds",
    "recall_tokens_injected_total",
];

pub const DEFAULT_REGROWTH_FACTOR: f64 = 1.5;
pub const QUERY_PROGRAM: &str = "cc-obs-query";

fn default_regrowth() -> f64 {
    DEFAULT_REGROWTH_FACTOR
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Query {
    pub command: String,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Threshold {
    pub min_share: Option<f64>,
    pub min_calls: Option<u64>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Question {
    pub id: String,
    pub title: String,
    pub signals: Vec<String>,
    pub query: Query,
    #[serde(default)]
    pub decision_kind: String,
    #[serde(default)]
    pub threshold: Threshold,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Pack {
    pub version: u32,
    #[serde(default = "default_regrowth")]
    pub regrowth_factor: f64,
    #[serde(default)]
    pub retire: Vec<String>,
    pub questions: Vec<Question>,
    #[serde(skip)]
    pub sha: String,
}

/// The git blob sha of the file, so a digest names the exact pack it ran.
fn blob_sha(bytes: &[u8]) -> String {
    let mut hasher = Sha1::new();
    hasher.update(format!("blob {}\0", bytes.len()).as_bytes());
    hasher.update(bytes);
    hasher
        .finalize()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

impl Pack {
    pub fn load(path: &Path) -> Result<Self, Error> {
        let bytes = std::fs::read(path).map_err(|source| Error::PackRead {
            path: path.to_owned(),
            source,
        })?;
        let parse = |source| Error::PackParse {
            path: path.to_owned(),
            source,
        };
        let raw: serde_yaml::Value = serde_yaml::from_slice(&bytes).map_err(parse)?;
        // Parse each question alone first so a typo names its question.
        let questions = raw
            .get("questions")
            .and_then(serde_yaml::Value::as_sequence)
            .map(Vec::as_slice)
            .unwrap_or_default();
        for raw_question in questions {
            if let Err(e) = serde_yaml::from_value::<Question>(raw_question.clone()) {
                let id = raw_question
                    .get("id")
                    .and_then(serde_yaml::Value::as_str)
                    .unwrap_or("(no id)");
                return Err(Error::PackInvalid {
                    path: path.to_owned(),
                    reason: format!("question {id:?}: {e}"),
                });
            }
        }
        let mut pack: Pack = serde_yaml::from_value(raw).map_err(parse)?;
        pack.sha = blob_sha(&bytes);
        pack.validate(path)?;
        Ok(pack)
    }

    fn validate(&self, path: &Path) -> Result<(), Error> {
        let invalid = |reason: String| Error::PackInvalid {
            path: path.to_owned(),
            reason,
        };
        let mut seen = BTreeSet::new();
        for question in &self.questions {
            if !seen.insert(question.id.as_str()) {
                return Err(invalid(format!("duplicate question id {:?}", question.id)));
            }
            if question.signals.is_empty() {
                return Err(invalid(format!(
                    "question {:?} lists no signals",
                    question.id
                )));
            }
            if question.query.command.split_whitespace().next() != Some(QUERY_PROGRAM) {
                return Err(invalid(format!(
                    "question {:?}: query.command must start with {QUERY_PROGRAM}",
                    question.id
                )));
            }
            for signal in &question.signals {
                if !COLLECTED_SIGNALS.contains(&signal.as_str()) {
                    return Err(invalid(format!(
                        "question {:?} names unknown signal {signal:?}",
                        question.id
                    )));
                }
            }
        }
        for signal in &self.retire {
            if !COLLECTED_SIGNALS.contains(&signal.as_str()) {
                return Err(invalid(format!("retire names unknown signal {signal:?}")));
            }
        }
        Ok(())
    }

    pub fn question(&self, id: &str) -> Result<&Question, Error> {
        self.questions
            .iter()
            .find(|q| q.id == id)
            .ok_or_else(|| Error::UnknownQuestion {
                id: id.to_owned(),
                known: self
                    .questions
                    .iter()
                    .map(|q| q.id.as_str())
                    .collect::<Vec<_>>()
                    .join(", "),
            })
    }

    /// Collected signals that no question references and `retire:` does not list.
    pub fn unused(&self) -> Vec<&'static str> {
        COLLECTED_SIGNALS
            .iter()
            .copied()
            .filter(|signal| {
                !self.retire.iter().any(|r| r == signal)
                    && !self
                        .questions
                        .iter()
                        .any(|q| q.signals.iter().any(|s| s == signal))
            })
            .collect()
    }
}

/// A dismissed finding comes back only once its metric grew past `factor` times
/// the baseline recorded when it was dismissed.
pub fn regrown(value: f64, baseline: f64, factor: f64) -> bool {
    value > baseline * factor
}

#[derive(Debug, Clone, Deserialize)]
pub struct DecisionMetric {
    pub question: String,
    pub key: String,
    pub baseline: f64,
    #[serde(default)]
    pub unit: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Decision {
    pub id: String,
    pub decision: String,
    pub metric: Option<DecisionMetric>,
    pub acted_on: Option<String>,
    pub outcome: Option<String>,
}

fn front_matter(text: &str) -> Option<&str> {
    let rest = text.strip_prefix("---\n")?;
    rest.split_once("\n---").map(|(yaml, _)| yaml)
}

/// Every `*.md` record in `dir`; a missing directory means no decisions yet.
pub fn load_decisions(dir: &Path) -> Result<Vec<Decision>, Error> {
    let entries = match std::fs::read_dir(dir) {
        Ok(entries) => entries,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(source) => {
            return Err(Error::DecisionsRead {
                path: dir.to_owned(),
                source,
            })
        }
    };
    let mut paths: Vec<PathBuf> = entries
        .filter_map(Result::ok)
        .map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|e| e == "md"))
        .collect();
    paths.sort();
    let mut decisions = Vec::new();
    for path in paths {
        let text = std::fs::read_to_string(&path).map_err(|source| Error::DecisionsRead {
            path: path.clone(),
            source,
        })?;
        let Some(yaml) = front_matter(&text) else {
            continue;
        };
        let decision = serde_yaml::from_str(yaml).map_err(|e| Error::DecisionInvalid {
            path: path.clone(),
            reason: e.to_string(),
        })?;
        decisions.push(decision);
    }
    Ok(decisions)
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    #[test]
    fn blob_sha_matches_git() {
        // `printf 'hello\n' | git hash-object --stdin`
        assert_eq!(
            blob_sha(b"hello\n"),
            "ce013625030ba8dba906f756967f9e9ca394464a"
        );
    }

    #[test]
    fn front_matter_is_split_off() {
        assert_eq!(front_matter("---\nid: x\n---\nbody"), Some("id: x"));
        assert_eq!(front_matter("no front matter"), None);
    }
}
