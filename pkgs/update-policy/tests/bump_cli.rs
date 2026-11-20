//! End-to-end tests of `update-policy bump` with a fake `nix` on PATH.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;
use std::process::{Command, Output};

const SOURCES: &str = r#"{"schema": 1,
  "tiers": {
    "established": {"cooldown_days": 7, "automerge": true, "description": "e"},
    "sensitive": {"cooldown_days": 7, "automerge": false, "description": "s"}
  },
  "sources": [
    {"match": "github:nix-community/*", "tier": "established"},
    {"match": "github:nix-community/lanzaboote", "tier": "sensitive"}
  ]}"#;

fn sha(c: char) -> String {
    std::iter::repeat_n(c, 40).collect()
}

fn lock() -> String {
    format!(
        r#"{{"version": 7, "root": "root", "nodes": {{
      "root": {{"inputs": {{"disko": "disko", "lanzaboote": "lanzaboote"}}}},
      "disko": {{"locked": {{"rev": "{a}"}}, "original": {{"type": "github", "owner": "nix-community", "repo": "disko"}}}},
      "lanzaboote": {{"locked": {{"rev": "{a}"}}, "original": {{"type": "github", "owner": "nix-community", "repo": "lanzaboote"}}}}
    }}}}"#,
        a = sha('a')
    )
}

struct Repo(PathBuf);

impl Repo {
    fn new(name: &str) -> Repo {
        let dir = std::env::temp_dir().join(format!("update-policy-bump-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("pins")).unwrap();
        fs::create_dir_all(dir.join("bin")).unwrap();
        fs::write(dir.join("pins/sources.json"), SOURCES).unwrap();
        fs::write(dir.join("flake.lock"), lock()).unwrap();
        fs::write(
            dir.join("heads.json"),
            format!(r#"{{"disko": "{b}", "lanzaboote": "{b}"}}"#, b = sha('b')),
        )
        .unwrap();
        // Fake nix: records its arguments, fails when asked to.
        let nix = dir.join("bin/nix");
        fs::write(&nix, "#!/bin/sh\necho \"$@\" >> \"$PWD/nix-calls\"\n[ -z \"$FAKE_NIX_FAIL\" ]\n").unwrap();
        fs::set_permissions(&nix, fs::Permissions::from_mode(0o755)).unwrap();
        Repo(dir)
    }
    fn run(&self, today: &str, extra: &[&str], fail: bool) -> Output {
        let path = format!("{}:{}", self.0.join("bin").display(), std::env::var("PATH").unwrap_or_default());
        let mut cmd = Command::new(env!("CARGO_BIN_EXE_update-policy"));
        cmd.arg("bump")
            .arg("--repo")
            .arg(&self.0)
            .args(["--today", today, "--heads"])
            .arg(self.0.join("heads.json"))
            .args(extra)
            .env("PATH", path);
        if fail {
            cmd.env("FAKE_NIX_FAIL", "1");
        }
        cmd.output().unwrap()
    }
    fn read(&self, rel: &str) -> Option<String> {
        fs::read_to_string(self.0.join(rel)).ok()
    }
}

impl Drop for Repo {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn out(o: &Output) -> String {
    format!("{}{}", String::from_utf8_lossy(&o.stdout), String::from_utf8_lossy(&o.stderr))
}

#[test]
fn dry_run_writes_nothing() {
    let repo = Repo::new("dry");
    let o = repo.run("2026-11-20", &[], false);
    assert_eq!(o.status.code(), Some(0), "{}", out(&o));
    assert!(out(&o).contains("disko [established, auto]: waiting, bbbbbbbb eligible on 2026-11-27"), "{}", out(&o));
    assert!(out(&o).contains("0 input(s) to update (dry run: nothing written)"));
    assert!(repo.read("pins/flake-seen.json").is_none());
    assert!(repo.read("nix-calls").is_none());
}

#[test]
fn records_then_bumps_after_the_cooldown() {
    let repo = Repo::new("cooldown");
    let o = repo.run("2026-11-20", &["--apply", "--group", "auto"], false);
    assert_eq!(o.status.code(), Some(0), "{}", out(&o));
    let seen = repo.read("pins/flake-seen.json").unwrap();
    assert!(seen.contains(&sha('b')) && seen.contains("2026-11-20"), "{seen}");
    assert!(repo.read("nix-calls").is_none(), "nothing is old enough yet");

    let summary = repo.0.join("summary.md");
    let o = repo.run("2026-11-27", &["--apply", "--group", "auto", "--summary", summary.to_str().unwrap()], false);
    assert_eq!(o.status.code(), Some(0), "{}", out(&o));
    assert!(out(&o).contains("1 input(s) to update in the auto group"), "{}", out(&o));
    assert_eq!(
        repo.read("nix-calls").unwrap(),
        format!("flake lock --override-input disko github:nix-community/disko/{}\n", sha('b'))
    );
    let md = fs::read_to_string(summary).unwrap();
    assert!(md.contains("| `disko` | established | `aaaaaaaa` | `bbbbbbbb` | 2026-11-20 (7 days ago) | 7 days |"), "{md}");
    assert!(!md.contains("lanzaboote"), "{md}");
}

#[test]
fn manual_group_bumps_sensitive_and_leaves_the_seen_file_alone() {
    let repo = Repo::new("manual");
    repo.run("2026-11-20", &["--apply", "--group", "auto"], false);
    let before = repo.read("pins/flake-seen.json").unwrap();
    let o = repo.run("2026-11-28", &["--apply", "--group", "manual"], false);
    assert_eq!(o.status.code(), Some(0), "{}", out(&o));
    assert_eq!(repo.read("pins/flake-seen.json").unwrap(), before);
    assert_eq!(
        repo.read("nix-calls").unwrap(),
        format!("flake lock --override-input lanzaboote github:nix-community/lanzaboote/{}\n", sha('b'))
    );
}

#[test]
fn nix_failure_is_reported() {
    let repo = Repo::new("nixfail");
    repo.run("2026-11-20", &["--apply"], false);
    let o = repo.run("2026-11-28", &["--apply"], true);
    assert_eq!(o.status.code(), Some(2));
    assert!(out(&o).contains("`nix flake lock` failed"), "{}", out(&o));
}

#[test]
fn bad_inputs_exit_2() {
    let repo = Repo::new("bad");
    fs::write(repo.0.join("pins/flake-seen.json"), r#"{"schema": 9, "inputs": {}}"#).unwrap();
    let o = repo.run("2026-11-20", &[], false);
    assert_eq!(o.status.code(), Some(2));
    assert!(out(&o).contains("flake-seen.json: seen file schema 9 is not supported"), "{}", out(&o));

    let repo = Repo::new("badgroup");
    let o = repo.run("2026-11-20", &["--group", "sometimes"], false);
    assert_eq!(o.status.code(), Some(2));
    assert!(out(&o).contains("`--group sometimes` must be `auto` or `manual`"));

}

#[test]
fn check_rejects_bump_only_flags() {
    let repo = Repo::new("checkflags");
    let bin = env!("CARGO_BIN_EXE_update-policy");
    let base = Command::new(bin).arg("check").arg("--repo").arg(&repo.0).output().unwrap();
    assert_eq!(base.status.code(), Some(0), "{}", out(&base));
    for flag in [&["--apply"][..], &["--seen", "x"], &["--heads", "x"], &["--summary", "x"], &["--group", "auto"]] {
        let o = Command::new(bin).arg("check").arg("--repo").arg(&repo.0).args(flag).output().unwrap();
        assert_eq!(o.status.code(), Some(2), "{flag:?}");
        assert!(out(&o).contains(&format!("unknown option `{}`", flag[0])), "{flag:?}: {}", out(&o));
    }
}

#[test]
fn custom_seen_path() {
    let repo = Repo::new("seenpath");
    let seen = repo.0.join("elsewhere.json");
    let o = repo.run("2026-11-20", &["--apply", "--seen", seen.to_str().unwrap()], false);
    assert_eq!(o.status.code(), Some(0), "{}", out(&o));
    assert!(fs::read_to_string(&seen).unwrap().contains(&sha('b')));
    assert!(repo.read("pins/flake-seen.json").is_none());
}

#[test]
fn heads_come_from_git_ls_remote() {
    let repo = Repo::new("lsremote");
    // Fake git: disko resolves, lanzaboote's remote fails. A pinned input
    // must not be looked up at all.
    let git = repo.0.join("bin/git");
    fs::write(
        &git,
        format!(
            "#!/bin/sh\necho \"$@\" >> \"$PWD/git-calls\"\ncase \"$2\" in\n  */disko) printf '{b}\\tHEAD\\n' ;;\n  *) echo 'fatal: repository not found' >&2; exit 128 ;;\nesac\n",
            b = sha('b')
        ),
    )
    .unwrap();
    fs::set_permissions(&git, fs::Permissions::from_mode(0o755)).unwrap();
    let mut lock = lock();
    lock = lock.replace(
        r#""disko": "disko", "lanzaboote": "lanzaboote""#,
        r#""disko": "disko", "lanzaboote": "lanzaboote", "pinned": "pinned""#,
    );
    lock = lock.replacen(
        r#""lanzaboote": {"locked""#,
        &format!(
            r#""pinned": {{"locked": {{"rev": "{a}"}}, "original": {{"type": "github", "owner": "nix-community", "repo": "pinned", "rev": "{a}"}}}},
      "lanzaboote": {{"locked""#,
            a = sha('a')
        ),
        1,
    );
    fs::write(repo.0.join("flake.lock"), lock).unwrap();
    let path = format!("{}:{}", repo.0.join("bin").display(), std::env::var("PATH").unwrap_or_default());
    let o = Command::new(env!("CARGO_BIN_EXE_update-policy"))
        .arg("bump")
        .arg("--repo")
        .arg(&repo.0)
        .args(["--today", "2026-11-20"])
        .current_dir(&repo.0)
        .env("PATH", path)
        .output()
        .unwrap();
    assert_eq!(o.status.code(), Some(0), "{}", out(&o));
    let text = out(&o);
    assert!(text.contains("disko [established, auto]: waiting, bbbbbbbb eligible on 2026-11-27"), "{text}");
    assert!(
        text.contains("warning: lanzaboote: not bumped: could not read upstream: `git ls-remote https://github.com/nix-community/lanzaboote HEAD` failed: fatal: repository not found"),
        "{text}"
    );
    assert!(text.contains("warning: pinned: not bumped: pinned to a rev in flake.nix"), "{text}");
    let calls = repo.read("git-calls").unwrap();
    assert_eq!(calls.lines().count(), 2, "{calls}");
    assert!(!calls.contains("pinned"), "{calls}");
}
