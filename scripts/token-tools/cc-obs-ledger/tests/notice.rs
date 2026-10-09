#![allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use cc_obs_ledger::notice::notice_line;

const FINDINGS: &str = "---\nreview: 2026-10-09-ali-desktop\nhost: ali-desktop\n---\n## 1. Title\n";

fn findings(state: &Path, name: &str, text: &str) -> PathBuf {
    let path = state.join("findings").join(name);
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(&path, text).unwrap();
    path
}

#[test]
fn no_state_dir_prints_nothing() {
    let root = tempfile::tempdir().unwrap();
    assert_eq!(notice_line(&root.path().join("missing")), None);
}

#[test]
fn empty_state_dir_prints_nothing() {
    let state = tempfile::tempdir().unwrap();
    fs::create_dir_all(state.path().join("findings")).unwrap();
    assert_eq!(notice_line(state.path()), None);
}

#[test]
fn unpromoted_newest_findings_print_the_review_id() {
    let state = tempfile::tempdir().unwrap();
    findings(state.path(), "2026-10-09-ali-desktop.md", FINDINGS);
    assert_eq!(
        notice_line(state.path()),
        Some("token review ready: 2026-10-09-ali-desktop".to_owned())
    );
}

#[test]
fn without_a_review_key_the_file_stem_names_the_review() {
    let state = tempfile::tempdir().unwrap();
    findings(state.path(), "2026-10-09-ali-desktop.md", "## 1. Title\n");
    assert_eq!(
        notice_line(state.path()),
        Some("token review ready: 2026-10-09-ali-desktop".to_owned())
    );
}

#[test]
fn a_promoted_marker_silences_the_notice() {
    let state = tempfile::tempdir().unwrap();
    findings(state.path(), "2026-10-09-ali-desktop.md", FINDINGS);
    findings(state.path(), "2026-10-09-ali-desktop.md.promoted", "");
    assert_eq!(notice_line(state.path()), None);
}

#[test]
fn a_dismissed_marker_silences_the_notice() {
    let state = tempfile::tempdir().unwrap();
    findings(state.path(), "2026-10-09-ali-desktop.md", FINDINGS);
    findings(state.path(), "2026-10-09-ali-desktop.md.dismissed", "");
    assert_eq!(notice_line(state.path()), None);
}

#[test]
fn an_older_unpromoted_file_does_not_resurface_when_the_newest_is_marked() {
    let state = tempfile::tempdir().unwrap();
    findings(state.path(), "2026-10-02-ali-desktop.md", FINDINGS);
    findings(state.path(), "2026-10-09-ali-desktop.md", FINDINGS);
    findings(state.path(), "2026-10-09-ali-desktop.md.promoted", "");
    assert_eq!(notice_line(state.path()), None);
}

#[test]
fn a_garbage_newest_file_is_silent() {
    let state = tempfile::tempdir().unwrap();
    findings(state.path(), "2026-10-09-ali-desktop.md", FINDINGS);
    let bytes = [0xff_u8, 0xfe, 0x00, 0x80];
    fs::write(state.path().join("findings/2026-10-10-garbage.md"), bytes).unwrap();
    assert_eq!(notice_line(state.path()), None);
}

#[test]
fn the_binary_prints_one_line_and_exits_zero() {
    let state = tempfile::tempdir().unwrap();
    findings(state.path(), "2026-10-09-ali-desktop.md", FINDINGS);
    let out = Command::new(env!("CARGO_BIN_EXE_cc-obs-ledger"))
        .arg("notice")
        .env("CC_OBS_REVIEW_STATE_DIR", state.path())
        .output()
        .unwrap();
    assert!(out.status.success());
    assert_eq!(
        String::from_utf8(out.stdout).unwrap(),
        "token review ready: 2026-10-09-ali-desktop\n"
    );
}

#[test]
fn a_closed_stdout_does_not_make_the_binary_fail() {
    let state = tempfile::tempdir().unwrap();
    findings(state.path(), "2026-10-09-ali-desktop.md", FINDINGS);
    let (reader, writer) = std::io::pipe().unwrap();
    drop(reader);
    let out = Command::new(env!("CARGO_BIN_EXE_cc-obs-ledger"))
        .arg("notice")
        .arg("--check")
        .env("CC_OBS_REVIEW_STATE_DIR", state.path())
        .stdout(writer)
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&out.stderr)
    );
}

#[test]
fn the_binary_falls_back_to_xdg_state_home_and_is_silent_when_missing() {
    let home = tempfile::tempdir().unwrap();
    let out = Command::new(env!("CARGO_BIN_EXE_cc-obs-ledger"))
        .arg("notice")
        .env_remove("CC_OBS_REVIEW_STATE_DIR")
        .env("XDG_STATE_HOME", home.path())
        .env("HOME", home.path())
        .output()
        .unwrap();
    assert!(out.status.success());
    assert!(out.stdout.is_empty());
}

const OVER: &str = r#"{"state":"over","usedBytes":21500000000,"capBytes":20000000000,"updated":"2026-10-09T12:00:00Z"}"#;
const OVER_LINE: &str = "observability stack over its disk budget: 21.5 of 20.0 GB (data kept, ingestion not stopped)\n";
const REVIEW_LINE: &str = "token review ready: 2026-10-09-ali-desktop\n";

fn guard(stack: &Path, bytes: &[u8]) {
    fs::create_dir_all(stack).unwrap();
    fs::write(stack.join("guard.json"), bytes).unwrap();
}

fn notice_with(review: &Path, stack: Option<&Path>) -> std::process::Output {
    let mut cmd = Command::new(env!("CARGO_BIN_EXE_cc-obs-ledger"));
    cmd.arg("notice")
        .arg("--check")
        .env("CC_OBS_REVIEW_STATE_DIR", review);
    match stack {
        Some(dir) => cmd.env("CC_OBS_STACK_STATE_DIR", dir),
        None => cmd.env_remove("CC_OBS_STACK_STATE_DIR"),
    };
    cmd.output().unwrap()
}

fn stdout_of(out: &std::process::Output) -> String {
    String::from_utf8(out.stdout.clone()).unwrap()
}

#[test]
fn an_over_budget_stack_prints_its_line_with_gb_to_one_decimal() {
    let stack = tempfile::tempdir().unwrap();
    let review = tempfile::tempdir().unwrap();
    guard(stack.path(), OVER.as_bytes());
    let out = notice_with(review.path(), Some(stack.path()));
    assert!(out.status.success());
    assert_eq!(stdout_of(&out), OVER_LINE);
}

#[test]
fn gb_figures_round_half_up_to_one_decimal() {
    let cases = [
        (1_250_000_000_u64, "1.3"),
        (1_249_000_000, "1.2"),
        (999_950_000, "1.0"),
    ];
    for (used, expected) in cases {
        let stack = tempfile::tempdir().unwrap();
        let review = tempfile::tempdir().unwrap();
        let text = format!(
            r#"{{"state":"over","usedBytes":{used},"capBytes":20000000000,"updated":"2026-10-09T12:00:00Z"}}"#
        );
        guard(stack.path(), text.as_bytes());
        let out = notice_with(review.path(), Some(stack.path()));
        assert!(out.status.success());
        assert_eq!(
            stdout_of(&out),
            format!("observability stack over its disk budget: {expected} of 20.0 GB (data kept, ingestion not stopped)\n"),
            "usedBytes {used}"
        );
    }
}

#[test]
fn an_ok_stack_prints_nothing() {
    let stack = tempfile::tempdir().unwrap();
    let review = tempfile::tempdir().unwrap();
    let text = r#"{"state":"ok","usedBytes":5000000000,"capBytes":20000000000,"updated":"2026-10-09T12:00:00Z","notified":"2026-10-08T12:00:00Z"}"#;
    guard(stack.path(), text.as_bytes());
    let out = notice_with(review.path(), Some(stack.path()));
    assert!(out.status.success());
    assert!(out.stdout.is_empty());
}

#[test]
fn a_garbage_stack_file_prints_nothing_and_exits_zero() {
    let cases: [&[u8]; 6] = [
        b"not json",
        b"{\"state\":\"over\"",
        br#"{"state":"degraded","usedBytes":1,"capBytes":1,"updated":"2026-10-09T12:00:00Z"}"#,
        br#"{"state":"over","usedBytes":21500000000,"capBytes":20000000000}"#,
        br#"{"state":"over","usedBytes":-5,"capBytes":20000000000,"updated":"2026-10-09T12:00:00Z"}"#,
        &[0xff, 0xfe, 0x00, 0x80],
    ];
    for bytes in cases {
        let stack = tempfile::tempdir().unwrap();
        let review = tempfile::tempdir().unwrap();
        guard(stack.path(), bytes);
        let out = notice_with(review.path(), Some(stack.path()));
        assert!(out.status.success(), "{bytes:?}");
        assert!(out.stdout.is_empty(), "{bytes:?}");
    }
}

#[test]
fn a_missing_stack_dir_prints_nothing_and_exits_zero() {
    let root = tempfile::tempdir().unwrap();
    let review = tempfile::tempdir().unwrap();
    let out = notice_with(review.path(), Some(&root.path().join("missing")));
    assert!(out.status.success());
    assert!(out.stdout.is_empty());
}

#[test]
fn both_sources_print_the_stack_line_first_then_the_review_line() {
    let stack = tempfile::tempdir().unwrap();
    let review = tempfile::tempdir().unwrap();
    guard(stack.path(), OVER.as_bytes());
    findings(review.path(), "2026-10-09-ali-desktop.md", FINDINGS);
    let out = notice_with(review.path(), Some(stack.path()));
    assert!(out.status.success());
    assert_eq!(stdout_of(&out), format!("{OVER_LINE}{REVIEW_LINE}"));
}

#[test]
fn the_review_line_still_prints_when_the_stack_variable_is_unset() {
    let review = tempfile::tempdir().unwrap();
    findings(review.path(), "2026-10-09-ali-desktop.md", FINDINGS);
    let out = notice_with(review.path(), None);
    assert!(out.status.success());
    assert_eq!(stdout_of(&out), REVIEW_LINE);
}
