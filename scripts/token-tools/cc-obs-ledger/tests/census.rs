#![allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]

use std::fs;
use std::io::Write;
use std::process::{Command, Stdio};

use cc_obs_ledger::census::{project_dir_name, run, CensusInput};

fn write(path: &std::path::Path, text: &str) {
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(path, text).unwrap();
}

#[test]
fn counts_instruction_files_from_the_working_directory_up_to_home() {
    let home = tempfile::tempdir().unwrap();
    let proj = home.path().join("work/proj");
    write(&home.path().join(".claude/CLAUDE.md"), &"a".repeat(400));
    write(&proj.join("CLAUDE.md"), &"b".repeat(800));
    write(&home.path().join("work/CLAUDE.md"), &"c".repeat(200));
    let census = run(&CensusInput {
        cwd: &proj,
        home: home.path(),
    });
    assert_eq!(census.components["instructions"], (400 + 800 + 200) / 4);
}

#[test]
fn counts_skill_names_and_descriptions_for_the_listing() {
    let home = tempfile::tempdir().unwrap();
    let description = "d".repeat(195);
    write(
        &home.path().join(".claude/skills/alpha/SKILL.md"),
        &format!("---\nname: alpha\ndescription: {description}\n---\nbody that is not counted"),
    );
    let census = run(&CensusInput {
        cwd: home.path(),
        home: home.path(),
    });
    assert_eq!(census.components["skills_listing"], 50);
}

#[test]
fn a_folded_multi_line_description_is_counted_whole() {
    let home = tempfile::tempdir().unwrap();
    write(
        &home.path().join(".claude/skills/beta/SKILL.md"),
        &format!(
            "---\nname: beta\ndescription: >\n  {}\n  {}\nallowed-tools: x\n---\n",
            "e".repeat(90),
            "f".repeat(100)
        ),
    );
    let census = run(&CensusInput {
        cwd: home.path(),
        home: home.path(),
    });
    assert_eq!(census.components["skills_listing"], (4 + 90 + 100) / 4);
}

#[test]
fn counts_the_memory_index_for_the_project() {
    let home = tempfile::tempdir().unwrap();
    let proj = home.path().join("work/proj");
    fs::create_dir_all(&proj).unwrap();
    let name = project_dir_name(&proj);
    write(
        &home
            .path()
            .join(format!(".claude/projects/{name}/memory/MEMORY.md")),
        &"m".repeat(1000),
    );
    let census = run(&CensusInput {
        cwd: &proj,
        home: home.path(),
    });
    assert_eq!(census.components["memory_index"], 250);
}

#[test]
fn project_directory_names_replace_slashes_and_dots() {
    let name = project_dir_name(std::path::Path::new("/home/ali/git/x/.claude/worktrees/y"));
    assert_eq!(name, "-home-ali-git-x--claude-worktrees-y");
}

#[test]
fn nothing_found_counts_zero_not_missing() {
    let home = tempfile::tempdir().unwrap();
    let census = run(&CensusInput {
        cwd: home.path(),
        home: home.path(),
    });
    for key in ["instructions", "skills_listing", "memory_index"] {
        assert_eq!(census.components[key], 0, "{key}");
    }
}

#[test]
fn the_census_subcommand_prints_nothing_and_stores_the_result() {
    let home = tempfile::tempdir().unwrap();
    let state = tempfile::tempdir().unwrap();
    write(&home.path().join(".claude/CLAUDE.md"), &"a".repeat(400));
    let mut child = Command::new(env!("CARGO_BIN_EXE_cc-obs-ledger"))
        .arg("census")
        .env("HOME", home.path())
        .env("XDG_STATE_HOME", state.path())
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let hook = format!(
        r#"{{"session_id":"sess-9","cwd":"{}","hook_event_name":"SessionStart"}}"#,
        home.path().display()
    );
    child
        .stdin
        .take()
        .unwrap()
        .write_all(hook.as_bytes())
        .unwrap();
    let out = child.wait_with_output().unwrap();
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(out.stdout.is_empty(), "stdout must stay empty");
    let stored = state.path().join("cc-obs-ledger/census/sess-9.json");
    let text = fs::read_to_string(&stored).unwrap();
    assert!(text.contains("\"instructions\":100"), "{text}");
}

#[test]
fn bad_hook_input_still_exits_zero_and_prints_nothing() {
    let home = tempfile::tempdir().unwrap();
    let state = tempfile::tempdir().unwrap();
    let mut child = Command::new(env!("CARGO_BIN_EXE_cc-obs-ledger"))
        .arg("census")
        .env("HOME", home.path())
        .env("XDG_STATE_HOME", state.path())
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child.stdin.take().unwrap().write_all(b"not json").unwrap();
    let out = child.wait_with_output().unwrap();
    assert!(out.status.success());
    assert!(out.stdout.is_empty());
    let log = state.path().join("cc-obs-ledger/ledger.log");
    assert!(fs::read_to_string(log).unwrap().contains("census"));
}
