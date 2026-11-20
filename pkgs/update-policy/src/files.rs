//! Finds the YAML files that can reference GitHub Actions.

use std::path::{Path, PathBuf};

/// YAML files directly under `.github/workflows` and in `.github/actions/*/`.
pub fn workflow_files(repo: &Path) -> Result<Vec<PathBuf>, String> {
    let mut files = Vec::new();
    let is_yaml = |p: &Path| matches!(p.extension().and_then(|e| e.to_str()), Some("yml" | "yaml"));
    let list = |dir: &Path| -> Result<Vec<PathBuf>, String> {
        match std::fs::read_dir(dir) {
            Ok(rd) => {
                let mut v: Vec<PathBuf> = rd.filter_map(|e| e.ok().map(|e| e.path())).collect();
                v.sort();
                Ok(v)
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Vec::new()),
            Err(e) => Err(format!("cannot list {}: {e}", dir.display())),
        }
    };
    for p in list(&repo.join(".github/workflows"))? {
        if p.is_file() && is_yaml(&p) {
            files.push(p);
        }
    }
    for d in list(&repo.join(".github/actions"))? {
        if d.is_dir() {
            for p in list(&d)? {
                if p.is_file() && is_yaml(&p) {
                    files.push(p);
                }
            }
        }
    }
    Ok(files)
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

    #[test]
    fn lists_workflows_and_composite_actions_only() {
        let d = tmp("list");
        fs::create_dir_all(d.join(".github/workflows/nested")).unwrap();
        fs::create_dir_all(d.join(".github/actions/setup")).unwrap();
        for f in [
            ".github/workflows/b.yaml",
            ".github/workflows/a.yml",
            ".github/workflows/README.md",
            ".github/workflows/nested/c.yaml",
            ".github/actions/setup/action.yml",
            ".github/actions/setup/notes.txt",
            ".github/actions/top.yaml",
        ] {
            fs::write(d.join(f), "x").unwrap();
        }
        let got: Vec<String> = workflow_files(&d)
            .unwrap()
            .iter()
            .map(|p| p.strip_prefix(&d).unwrap().display().to_string())
            .collect();
        assert_eq!(
            got,
            vec![".github/workflows/a.yml", ".github/workflows/b.yaml", ".github/actions/setup/action.yml"]
        );
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn missing_dirs_are_empty_but_other_errors_are_reported() {
        let d = tmp("errs");
        assert!(workflow_files(&d).unwrap().is_empty());
        fs::create_dir_all(d.join(".github")).unwrap();
        fs::write(d.join(".github/workflows"), "not a dir").unwrap();
        let err = workflow_files(&d).unwrap_err();
        assert!(err.starts_with("cannot list "), "{err}");
        fs::remove_dir_all(&d).unwrap();
    }
}
