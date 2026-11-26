//! End-to-end tests of `update-policy shepherd`.

use std::fs;
use std::path::PathBuf;
use std::process::{Command, Output};

// 2026-11-24T00:00:00Z
const NOW: &str = "1795478400";

fn prs_file(name: &str, text: &str) -> PathBuf {
    let path = std::env::temp_dir().join(format!("update-policy-shepherd-{}-{name}.json", std::process::id()));
    fs::write(&path, text).unwrap();
    path
}

fn run(args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_update-policy")).arg("shepherd").args(args).output().unwrap()
}

fn stdout(o: &Output) -> String {
    String::from_utf8_lossy(&o.stdout).into_owned()
}

fn stderr(o: &Output) -> String {
    String::from_utf8_lossy(&o.stderr).into_owned()
}

const BEHIND: &str = r#"[{"number": 1070, "headRefName": "flake-update-45280843759-1", "isDraft": false,
  "createdAt": "2026-11-23T22:39:57Z", "mergeStateStatus": "BEHIND",
  "statusCheckRollup": [{"__typename": "CheckRun", "name": "flake-check", "status": "COMPLETED", "conclusion": "SUCCESS"}]}]"#;

#[test]
fn prints_one_line_per_decision() {
    let f = prs_file("behind", BEHIND);
    let o = run(&["--prs", f.to_str().unwrap(), "--now", NOW]);
    assert!(o.status.success(), "{}", stderr(&o));
    assert_eq!(stdout(&o), "rebase 1070\n");

    let o = run(&["--prs", f.to_str().unwrap(), "--now", NOW, "--rebase-window", "00:30-04:30"]);
    assert_eq!(stdout(&o), "wait 1070 open 1.3h, merge state behind, no checks pending, rebase waits for 00:30-04:30 UTC\n");
    let o = run(&["--prs", f.to_str().unwrap(), "--now", NOW, "--rebase-window", "23:30-04:30"]);
    assert_eq!(stdout(&o), "rebase 1070\n");

    let o = run(&["--prs", f.to_str().unwrap(), "--now", NOW, "--stuck-after-hours", "1"]);
    assert_eq!(stdout(&o), "rebase 1070\nstuck 1070 not merged after 1.0h (open 1.3h, merge state behind, no checks pending)\n");
    fs::remove_file(f).unwrap();
}

#[test]
fn reports_a_missed_nightly_only_when_asked_and_late() {
    let f = prs_file("missed", "[]");
    let p = f.to_str().unwrap();
    // NOW is 2026-11-24T00:00:00Z.
    let o = run(&["--prs", p, "--now", NOW, "--last-nightly", "2026-11-23T02:00:00Z"]);
    assert_eq!(stdout(&o), "");
    let o = run(&["--prs", p, "--now", NOW, "--last-nightly", "2026-11-22T22:00:00Z"]);
    assert!(stdout(&o).starts_with("missed the nightly flake update has not started for 26.0h;"), "{}", stdout(&o));
    let o = run(&["--prs", p, "--now", NOW, "--last-nightly", "2026-11-23T02:00:00Z", "--max-nightly-gap-hours", "20"]);
    assert!(stdout(&o).starts_with("missed the nightly flake update has not started for 22.0h;"), "{}", stdout(&o));
    let o = run(&["--prs", p, "--now", NOW, "--last-nightly", "none"]);
    assert!(stdout(&o).starts_with("missed the nightly flake update has never run;"), "{}", stdout(&o));
    assert_eq!(stdout(&o).lines().count(), 1);
    fs::remove_file(f).unwrap();
}

#[test]
fn no_prs_prints_nothing() {
    let f = prs_file("empty", "[]");
    let o = run(&["--prs", f.to_str().unwrap(), "--now", NOW]);
    assert!(o.status.success());
    assert_eq!(stdout(&o), "");
    fs::remove_file(f).unwrap();
}

#[test]
fn bad_input_exits_2_with_the_file_and_problem() {
    let f = prs_file("bad", "[{}]");
    let o = run(&["--prs", f.to_str().unwrap()]);
    assert_eq!(o.status.code(), Some(2));
    assert!(stderr(&o).contains(&format!("{}: pull request [0]: missing `number`", f.display())), "{}", stderr(&o));
    fs::remove_file(f).unwrap();

    let o = run(&["--prs", "/nonexistent/prs.json"]);
    assert_eq!(o.status.code(), Some(2));
    assert!(stderr(&o).contains("cannot read /nonexistent/prs.json"));
}

#[test]
fn bad_arguments_exit_2() {
    for (args, msg) in [
        (&[][..], "shepherd needs `--prs FILE`"),
        (&["--prs", "x", "--now", "soon"][..], "`--now soon` is not a number of Unix seconds"),
        (&["--prs", "x", "--stuck-after-hours", "0"][..], "`--stuck-after-hours 0` is not a positive whole number"),
        (&["--prs", "x", "--apply"][..], "unknown option `--apply`"),
        (&["--prs", "x", "--rebase-window", "1-2"][..], "`--rebase-window 1-2` is not HH:MM-HH:MM (UTC)"),
        (&["--prs", "x", "--last-nightly", "today"][..], "`--last-nightly today` is not a UTC timestamp"),
        (&["--prs", "x", "--max-nightly-gap-hours", "0"][..], "`--max-nightly-gap-hours 0` is not a positive whole number"),
    ] {
        let o = run(args);
        assert_eq!(o.status.code(), Some(2), "{args:?}");
        assert!(stderr(&o).contains(msg), "{args:?}: {}", stderr(&o));
    }
}

#[test]
fn shepherd_options_belong_to_shepherd_only() {
    for flag in ["--prs", "--now", "--stuck-after-hours", "--rebase-window", "--last-nightly", "--max-nightly-gap-hours"] {
        let o = Command::new(env!("CARGO_BIN_EXE_update-policy")).args(["bump", flag, "1"]).output().unwrap();
        assert_eq!(o.status.code(), Some(2), "{flag}");
        assert!(stderr(&o).contains(&format!("unknown option `{flag}`")), "{flag}: {}", stderr(&o));
    }
}
