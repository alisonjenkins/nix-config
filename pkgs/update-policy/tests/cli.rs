//! End-to-end tests of the binary against throwaway repositories.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

const SOURCES: &str = r#"{"schema": 1,
  "tiers": {
    "own": {"cooldown_days": 0, "automerge": true, "description": "o"},
    "core": {"cooldown_days": 3, "automerge": true, "description": "c"}
  },
  "sources": [
    {"match": "github:nixos/nixpkgs", "tier": "core"},
    {"match": "action:actions/*", "tier": "core"}
  ]}"#;

const LOCK: &str = r#"{"version": 7, "root": "root", "nodes": {
  "root": {"inputs": {"nixpkgs": "nixpkgs"}},
  "nixpkgs": {"original": {"type": "github", "owner": "NixOS", "repo": "nixpkgs"}}}}"#;

const WF: &str = "jobs:\n  a:\n    steps:\n      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7\n";

struct Repo(PathBuf);

impl Repo {
    fn new(name: &str) -> Repo {
        let dir = std::env::temp_dir().join(format!("update-policy-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("pins")).unwrap();
        fs::create_dir_all(dir.join(".github/workflows")).unwrap();
        fs::create_dir_all(dir.join(".github/actions/setup")).unwrap();
        let repo = Repo(dir);
        repo.write("pins/sources.json", SOURCES);
        repo.write("flake.lock", LOCK);
        repo.write(".github/workflows/ci.yaml", WF);
        repo
    }
    fn write(&self, rel: &str, text: &str) {
        fs::write(self.0.join(rel), text).unwrap();
    }
    fn run(&self, extra: &[&str]) -> Output {
        Command::new(env!("CARGO_BIN_EXE_update-policy"))
            .arg("check")
            .arg("--repo")
            .arg(&self.0)
            .args(["--today", "2026-11-20"])
            .args(extra)
            .output()
            .unwrap()
    }
    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for Repo {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn stdout(o: &Output) -> String {
    String::from_utf8_lossy(&o.stdout).into_owned()
}
fn stderr(o: &Output) -> String {
    String::from_utf8_lossy(&o.stderr).into_owned()
}

#[test]
fn clean_repo_passes() {
    let repo = Repo::new("clean");
    let out = repo.run(&[]);
    assert_eq!(out.status.code(), Some(0), "{}{}", stdout(&out), stderr(&out));
    assert_eq!(
        stdout(&out),
        "update-policy: 1 flake inputs, 1 action references checked; 0 error(s), 0 warning(s)\n"
    );
}

#[test]
fn untiered_sources_fail_with_locations() {
    let repo = Repo::new("untiered");
    repo.write(
        ".github/actions/setup/action.yml",
        "runs:\n  steps:\n    - uses: someone/tool@v1\n",
    );
    repo.write(
        "flake.lock",
        r#"{"version": 7, "root": "root", "nodes": {
          "root": {"inputs": {"nixpkgs": "nixpkgs", "x": "x"}},
          "nixpkgs": {"original": {"type": "github", "owner": "NixOS", "repo": "nixpkgs"}},
          "x": {"original": {"type": "github", "owner": "Who", "repo": "What"}}}}"#,
    );
    let out = repo.run(&[]);
    assert_eq!(out.status.code(), Some(1));
    let text = stdout(&out);
    assert!(text.contains("error: flake input `x` (type=github owner=Who repo=What) has no trust tier"), "{text}");
    assert!(text.contains("error: .github/actions/setup/action.yml:3: action `someone/tool` has no trust tier"), "{text}");
    assert!(text.ends_with("2 error(s), 0 warning(s)\n"), "{text}");
}

#[test]
fn bad_sources_file_exits_2_and_lists_problems() {
    let repo = Repo::new("bad");
    repo.write(
        "pins/sources.json",
        r#"{"schema": 1, "tiers": {"core": {"cooldown_days": 3, "automerge": true, "description": "c"}},
            "sources": [{"match": "github:a/b", "tier": "nope"}, {"match": "github:a/b", "tier": "core"}]}"#,
    );
    let out = repo.run(&[]);
    assert_eq!(out.status.code(), Some(2));
    let err = stderr(&out);
    assert!(err.contains("the sources file has 2 problem(s):"), "{err}");
    assert!(err.contains("uses tier `nope`, which is not defined; use one of: core"), "{err}");
}

#[test]
fn missing_sources_file_exits_2() {
    let repo = Repo::new("missing");
    let other = repo.path().join("nope.json");
    let out = repo.run(&["--sources", other.to_str().unwrap()]);
    assert_eq!(out.status.code(), Some(2));
    assert!(stderr(&out).contains("cannot read"), "{}", stderr(&out));
}

#[test]
fn no_lock_and_no_workflows_is_fine() {
    let repo = Repo::new("empty");
    fs::remove_file(repo.path().join("flake.lock")).unwrap();
    fs::remove_dir_all(repo.path().join(".github")).unwrap();
    let out = repo.run(&[]);
    assert_eq!(out.status.code(), Some(0), "{}", stderr(&out));
    assert!(stdout(&out).contains("0 flake inputs, 0 action references"));
}

#[test]
fn usage_errors_exit_2() {
    let bin = env!("CARGO_BIN_EXE_update-policy");
    for args in [&[][..], &["frobnicate"][..], &["check", "--today", "2026-02-30"][..], &["check", "--repo"][..], &["check", "--bogus"][..]] {
        let out = Command::new(bin).args(args).output().unwrap();
        assert_eq!(out.status.code(), Some(2), "{args:?}");
        assert!(stderr(&out).contains("usage: update-policy check"), "{args:?}");
    }
    let out = Command::new(bin).arg("frobnicate").output().unwrap();
    assert!(stderr(&out).starts_with("update-policy: unknown command `frobnicate`\n"), "{}", stderr(&out));
    let out = Command::new(bin).arg("--help").output().unwrap();
    assert_eq!(out.status.code(), Some(0));
    assert!(stderr(&out).starts_with("usage: update-policy check"), "{}", stderr(&out));
}
