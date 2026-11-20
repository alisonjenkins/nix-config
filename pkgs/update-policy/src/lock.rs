//! Reads `flake.lock` and lists every input with a source key.

use serde::Deserialize;
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::fmt;

#[derive(Debug, Deserialize)]
struct LockFile {
    nodes: BTreeMap<String, Node>,
    root: String,
    version: u64,
}

#[derive(Debug, Deserialize)]
struct Node {
    #[serde(default)]
    inputs: BTreeMap<String, Value>,
    #[serde(default)]
    original: Option<BTreeMap<String, Value>>,
    #[serde(default)]
    locked: Option<BTreeMap<String, Value>>,
}

/// One locked input that came from somewhere other than this repository.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LockedInput {
    /// Node name in flake.lock.
    pub node: String,
    /// How it is reached from the root, for example `stylix/base16`.
    pub via: String,
    /// `<kind>:<path>`, lowercase. `None` for a local `path:` input.
    pub key: Option<String>,
    /// The original reference, for messages.
    pub original: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LockError {
    Json(String),
    Version(u64),
    MissingRoot(String),
    UnknownType { node: String, kind: String },
}

impl fmt::Display for LockError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            LockError::Json(e) => write!(f, "flake.lock is not valid: {e}"),
            LockError::Version(v) => write!(f, "flake.lock version {v} is not supported (expected 7)"),
            LockError::MissingRoot(r) => write!(f, "flake.lock root node `{r}` is missing"),
            LockError::UnknownType { node, kind } => write!(
                f,
                "flake.lock node `{node}` has source type `{kind}`, which update-policy cannot classify yet; add support in pkgs/update-policy/src/lock.rs"
            ),
        }
    }
}

fn s<'a>(o: &'a BTreeMap<String, Value>, k: &str) -> Option<&'a str> {
    o.get(k).and_then(Value::as_str)
}

/// The source key for an `original` reference.
fn key_for(node: &str, o: &BTreeMap<String, Value>) -> Result<Option<String>, LockError> {
    let kind = s(o, "type").unwrap_or("");
    let key = match kind {
        "github" | "gitlab" | "sourcehut" => {
            let (owner, repo) = (s(o, "owner").unwrap_or(""), s(o, "repo").unwrap_or(""));
            let default_host = match kind {
                "github" => "github.com",
                "gitlab" => "gitlab.com",
                _ => "git.sr.ht",
            };
            match s(o, "host") {
                // A GitHub Enterprise or self-hosted server is a different
                // source from the public one, so it gets its own key and
                // never inherits a public repository's tier.
                Some(host) if !host.eq_ignore_ascii_case(default_host) => format!("{kind}:{host}/{owner}/{repo}"),
                _ => format!("{kind}:{owner}/{repo}"),
            }
        }
        "tarball" | "file" | "git" => {
            let url = s(o, "url").unwrap_or("");
            // git+https://host/x?ref=y: drop the query, it is not part of the source.
            let url = url.split('?').next().unwrap_or(url);
            format!("{kind}:{url}")
        }
        "path" => return Ok(None),
        "indirect" => format!("indirect:{}", s(o, "id").unwrap_or("")),
        other => {
            return Err(LockError::UnknownType { node: node.to_string(), kind: other.to_string() })
        }
    };
    Ok(Some(key.to_lowercase()))
}

fn describe(o: &BTreeMap<String, Value>) -> String {
    let mut parts: Vec<String> = Vec::new();
    for k in ["type", "host", "owner", "repo", "url", "ref", "id"] {
        if let Some(v) = s(o, k) {
            parts.push(format!("{k}={v}"));
        }
    }
    parts.join(" ")
}

/// Every non-local input in the lock, each reached by its shortest path
/// from the root. Inputs that `follows` another node are reported once, at
/// the node they resolve to.
pub fn inputs(text: &str) -> Result<Vec<LockedInput>, Vec<LockError>> {
    let lock: LockFile = serde_json::from_str(text).map_err(|e| vec![LockError::Json(e.to_string())])?;
    if lock.version != 7 {
        return Err(vec![LockError::Version(lock.version)]);
    }
    if !lock.nodes.contains_key(&lock.root) {
        return Err(vec![LockError::MissingRoot(lock.root)]);
    }

    // Breadth-first from the root, so each node gets its shortest path.
    // Only direct references (a string) are edges; a `follows` list points
    // at a node that is reached through its own owner anyway.
    let mut via: BTreeMap<String, String> = BTreeMap::new();
    let mut queue = VecDeque::new();
    let mut seen = BTreeSet::new();
    queue.push_back((lock.root.clone(), String::new()));
    seen.insert(lock.root.clone());
    while let Some((name, path)) = queue.pop_front() {
        let Some(node) = lock.nodes.get(&name) else { continue };
        for (input_name, target) in &node.inputs {
            let Some(target) = target.as_str() else { continue };
            if seen.insert(target.to_string()) {
                let p = if path.is_empty() { input_name.clone() } else { format!("{path}/{input_name}") };
                via.insert(target.to_string(), p.clone());
                queue.push_back((target.to_string(), p));
            }
        }
    }

    let mut out = Vec::new();
    let mut errors = Vec::new();
    for (name, path) in via {
        let Some(node) = lock.nodes.get(&name) else { continue };
        let Some(original) = node.original.as_ref() else { continue };
        // An indirect reference (`nixpkgs` from the registry) is whatever
        // the registry resolved it to when locking: classify that.
        let source = match (s(original, "type"), node.locked.as_ref()) {
            (Some("indirect"), Some(locked)) => locked,
            _ => original,
        };
        match key_for(&name, source) {
            Ok(key) => out.push(LockedInput {
                node: name,
                via: path,
                key,
                original: describe(original),
            }),
            Err(e) => errors.push(e),
        }
    }
    if errors.is_empty() {
        Ok(out)
    } else {
        Err(errors)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const LOCK: &str = r#"{
      "version": 7, "root": "root",
      "nodes": {
        "root": {"inputs": {"nixpkgs": "nixpkgs", "stylix": "stylix", "local": "local"}},
        "nixpkgs": {"locked": {}, "original": {"type": "github", "owner": "NixOS", "repo": "nixpkgs", "ref": "nixos-unstable"}},
        "stylix": {"inputs": {"nixpkgs": ["nixpkgs"], "base16": "base16"},
                   "original": {"type": "github", "owner": "danth", "repo": "stylix"}},
        "base16": {"inputs": {"shell": "shell"}, "original": {"type": "github", "owner": "SenchoPens", "repo": "base16.nix"}},
        "shell": {"original": {"type": "gitlab", "host": "gitlab.gnome.org", "owner": "GNOME", "repo": "gnome-shell", "ref": "gnome-49"}},
        "local": {"original": {"type": "path", "path": "./pkgs"}},
        "orphan": {"original": {"type": "github", "owner": "x", "repo": "unreachable"}}
      }
    }"#;

    #[test]
    fn lists_reachable_inputs_with_paths() {
        let got = inputs(LOCK).unwrap();
        let keys: Vec<(&str, &str, Option<&str>)> =
            got.iter().map(|i| (i.node.as_str(), i.via.as_str(), i.key.as_deref())).collect();
        assert_eq!(
            keys,
            vec![
                ("base16", "stylix/base16", Some("github:senchopens/base16.nix")),
                ("local", "local", None),
                ("nixpkgs", "nixpkgs", Some("github:nixos/nixpkgs")),
                ("shell", "stylix/base16/shell", Some("gitlab:gitlab.gnome.org/gnome/gnome-shell")),
                ("stylix", "stylix", Some("github:danth/stylix")),
            ]
        );
        assert_eq!(got[2].original, "type=github owner=NixOS repo=nixpkgs ref=nixos-unstable");
    }

    #[test]
    fn tarball_and_git_urls() {
        let lock = r#"{"version": 7, "root": "root", "nodes": {
            "root": {"inputs": {"a": "a", "b": "b", "c": "c", "d": "d", "e": "e", "f": "f", "g": "g", "h": "h", "i": "i"}},
            "a": {"original": {"type": "tarball", "url": "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz"}},
            "b": {"original": {"type": "git", "url": "https://Example.org/x.git?ref=main"}},
            "c": {"original": {"type": "indirect", "id": "nixpkgs"}},
            "d": {"original": {"type": "github", "host": "github.com", "owner": "o", "repo": "r"}},
            "e": {"original": {"type": "github", "host": "GHE.example.org", "owner": "NixOS", "repo": "nixpkgs"}},
            "f": {"original": {"type": "indirect", "id": "nixpkgs"},
                  "locked": {"type": "github", "owner": "NixOS", "repo": "nixpkgs", "rev": "abc"}},
            "g": {"original": {"type": "gitlab", "host": "gitlab.com", "owner": "o", "repo": "r"}},
            "h": {"original": {"type": "sourcehut", "owner": "~o", "repo": "r"}},
            "i": {"original": {"type": "sourcehut", "host": "hg.example", "owner": "~o", "repo": "r"}}
        }}"#;
        let keys: Vec<String> = inputs(lock).unwrap().into_iter().filter_map(|i| i.key).collect();
        assert_eq!(
            keys,
            vec![
                "tarball:https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz",
                "git:https://example.org/x.git",
                "indirect:nixpkgs",
                "github:o/r",
                "github:ghe.example.org/nixos/nixpkgs",
                "github:nixos/nixpkgs",
                "gitlab:o/r",
                "sourcehut:~o/r",
                "sourcehut:hg.example/~o/r",
            ]
        );
    }

    #[test]
    fn errors_are_reported() {
        assert!(matches!(&inputs("{").unwrap_err()[0], LockError::Json(_)));
        assert_eq!(
            inputs(r#"{"version": 6, "root": "root", "nodes": {}}"#).unwrap_err(),
            vec![LockError::Version(6)]
        );
        assert_eq!(
            inputs(r#"{"version": 7, "root": "r", "nodes": {}}"#).unwrap_err(),
            vec![LockError::MissingRoot("r".into())]
        );
        let lock = r#"{"version": 7, "root": "root", "nodes": {
            "root": {"inputs": {"a": "a"}}, "a": {"original": {"type": "mercurial", "url": "x"}}}}"#;
        let errs = inputs(lock).unwrap_err();
        assert_eq!(errs, vec![LockError::UnknownType { node: "a".into(), kind: "mercurial".into() }]);
        assert!(errs[0].to_string().contains("pkgs/update-policy/src/lock.rs"));
    }
}
