//! Finds every file that can reference a GitHub Action, and the Actions in
//! them: workflows, every composite action under `.github/actions` at any
//! depth, and any local action a workflow points at with `uses: ./path`.

use crate::workflows::{self, ActionUse};
use std::collections::{BTreeSet, VecDeque};
use std::path::{Path, PathBuf};

fn list(dir: &Path) -> Result<Vec<PathBuf>, String> {
    match std::fs::read_dir(dir) {
        Ok(rd) => {
            let mut v: Vec<PathBuf> = rd.filter_map(|e| e.ok().map(|e| e.path())).collect();
            v.sort();
            Ok(v)
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Vec::new()),
        Err(e) => Err(format!("cannot list {}: {e}", dir.display())),
    }
}

fn is_yaml(p: &Path) -> bool {
    matches!(p.extension().and_then(|e| e.to_str()), Some("yml" | "yaml"))
}

fn is_action_metadata(p: &Path) -> bool {
    matches!(p.file_name().and_then(|n| n.to_str()), Some("action.yml" | "action.yaml"))
}

/// Workflows directly under `.github/workflows` (GitHub reads no deeper),
/// then every `action.yml`/`action.yaml` under `.github/actions`.
pub fn workflow_files(repo: &Path) -> Result<Vec<PathBuf>, String> {
    let mut files: Vec<PathBuf> =
        list(&repo.join(".github/workflows"))?.into_iter().filter(|p| p.is_file() && is_yaml(p)).collect();
    let mut dirs = VecDeque::from([repo.join(".github/actions")]);
    while let Some(dir) = dirs.pop_front() {
        for p in list(&dir)? {
            if p.is_dir() {
                dirs.push_back(p);
            } else if is_action_metadata(&p) {
                files.push(p);
            }
        }
    }
    Ok(files)
}

fn rel(repo: &Path, p: &Path) -> String {
    p.strip_prefix(repo).unwrap_or(p).display().to_string()
}

/// Every remote Action reference reachable from the repository's workflows.
pub fn collect_actions(repo: &Path) -> Result<Vec<ActionUse>, String> {
    let mut queue: VecDeque<PathBuf> = workflow_files(repo)?.into();
    let mut seen: BTreeSet<PathBuf> = queue.iter().cloned().collect();
    let mut out = Vec::new();
    while let Some(file) = queue.pop_front() {
        let name = rel(repo, &file);
        let text = std::fs::read_to_string(&file).map_err(|e| format!("cannot read {name}: {e}"))?;
        let scan = workflows::scan(&name, &text)?;
        out.extend(scan.remote);
        for local in scan.local {
            let dir = repo.join(&local);
            let meta = ["action.yml", "action.yaml"].iter().map(|n| dir.join(n)).find(|p| p.is_file());
            match meta {
                Some(m) => {
                    if seen.insert(m.clone()) {
                        queue.push_back(m);
                    }
                }
                None => {
                    return Err(format!(
                        "{name} uses local action `./{local}`, but {local}/action.yml does not exist"
                    ))
                }
            }
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn tmp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("update-policy-files-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    fn put(d: &Path, rel: &str, text: &str) {
        let p = d.join(rel);
        fs::create_dir_all(p.parent().unwrap()).unwrap();
        fs::write(p, text).unwrap();
    }

    #[test]
    fn lists_workflows_and_nested_composite_actions() {
        let d = tmp("list");
        for f in [
            ".github/workflows/b.yaml",
            ".github/workflows/a.yml",
            ".github/workflows/README.md",
            ".github/workflows/nested/c.yaml",
            ".github/actions/setup/action.yml",
            ".github/actions/setup/notes.yml",
            ".github/actions/group/tool/action.yaml",
            ".github/actions/top.yaml",
        ] {
            put(&d, f, "x: 1\n");
        }
        let got: Vec<String> = workflow_files(&d).unwrap().iter().map(|p| rel(&d, p)).collect();
        assert_eq!(
            got,
            vec![
                ".github/workflows/a.yml",
                ".github/workflows/b.yaml",
                ".github/actions/setup/action.yml",
                ".github/actions/group/tool/action.yaml",
            ]
        );
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn follows_local_actions_once() {
        let d = tmp("follow");
        put(&d, ".github/workflows/ci.yaml", "steps:\n  - uses: ./tools/act\n  - uses: ./tools/act\n  - uses: a/b@v1\n");
        put(&d, "tools/act/action.yml", "runs:\n  steps:\n    - uses: c/d@v2\n    - uses: ./tools/act\n");
        let got: Vec<(String, usize, String)> =
            collect_actions(&d).unwrap().into_iter().map(|u| (u.file, u.line, u.repo)).collect();
        assert_eq!(
            got,
            vec![
                (".github/workflows/ci.yaml".into(), 4, "a/b".into()),
                ("tools/act/action.yml".into(), 3, "c/d".into()),
            ]
        );
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn missing_local_action_and_bad_yaml_are_errors() {
        let d = tmp("missing");
        put(&d, ".github/workflows/ci.yaml", "steps:\n  - uses: ./nope\n");
        assert_eq!(
            collect_actions(&d).unwrap_err(),
            ".github/workflows/ci.yaml uses local action `./nope`, but nope/action.yml does not exist"
        );
        put(&d, ".github/workflows/ci.yaml", "a: [\n");
        assert!(collect_actions(&d).unwrap_err().starts_with(".github/workflows/ci.yaml: not valid YAML"));
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn missing_dirs_are_empty_but_other_errors_are_reported() {
        let d = tmp("errs");
        assert!(workflow_files(&d).unwrap().is_empty());
        assert!(collect_actions(&d).unwrap().is_empty());
        fs::create_dir_all(d.join(".github")).unwrap();
        fs::write(d.join(".github/workflows"), "not a dir").unwrap();
        let err = workflow_files(&d).unwrap_err();
        assert!(err.starts_with("cannot list "), "{err}");
        fs::remove_dir_all(&d).unwrap();
    }
}
