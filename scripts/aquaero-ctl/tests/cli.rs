// Panicking on a bad fixture is the correct failure inside a test.
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects,
    clippy::panic
)]

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use aquaero_ctl::snapshot::{ConfigBytes, ConfigSnapshot, CONFIG_LEN};
use aquaero_ctl::timestamp::UtcTimestamp;

fn run(args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_aquaero-ctl"))
        .args(args)
        .output()
        .unwrap()
}

fn stdout(out: &Output) -> String {
    String::from_utf8_lossy(&out.stdout).into_owned()
}

fn stderr(out: &Output) -> String {
    String::from_utf8_lossy(&out.stderr).into_owned()
}

fn code(out: &Output) -> i32 {
    out.status.code().unwrap()
}

fn bytes_with(changes: &[(usize, u8)]) -> ConfigBytes {
    let mut bytes = vec![0u8; CONFIG_LEN];
    for &(offset, value) in changes {
        bytes[offset] = value;
    }
    ConfigBytes::new(bytes).unwrap()
}

/// Writes a snapshot of `changes` over zeros and returns its `.bin` path.
fn snapshot(dir: &Path, label: &str, secs: i64, changes: &[(usize, u8)]) -> PathBuf {
    ConfigSnapshot::new(
        bytes_with(changes),
        "12345-54321".to_string(),
        1036,
        UtcTimestamp::from_unix(secs),
        label,
    )
    .write_to(dir)
    .unwrap()
    .bin
}

fn s(p: &Path) -> &str {
    p.to_str().unwrap()
}

#[test]
fn help_lists_the_commands() {
    let out = run(&["--help"]);
    assert_eq!(code(&out), 0);
    assert!(stdout(&out).contains("dump"));
    assert!(stdout(&out).contains("diff"));
}

#[test]
fn no_command_is_a_usage_error() {
    let out = run(&[]);
    assert_eq!(code(&out), 2);
    assert!(stderr(&out).contains("Usage"), "{}", stderr(&out));
}

#[test]
fn an_unknown_command_is_a_usage_error() {
    assert_eq!(code(&run(&["frobnicate"])), 2);
}

#[test]
fn dump_requires_an_output_directory() {
    assert_eq!(code(&run(&["dump"])), 2);
}

#[test]
fn diff_requires_two_snapshots() {
    assert_eq!(code(&run(&["diff", "only-one.bin"])), 2);
}

#[test]
fn diff_shows_the_changed_byte_in_hex() {
    let dir = tempfile::tempdir().unwrap();
    let a = snapshot(dir.path(), "a", 1_000_000_000, &[]);
    let b = snapshot(dir.path(), "b", 1_000_000_100, &[(100, 0x42)]);

    let out = run(&["diff", s(&a), s(&b)]);

    assert_eq!(code(&out), 0, "{}", stderr(&out));
    let text = stdout(&out);
    assert!(text.contains("0x0064  00 -> 42"), "{text}");
    assert!(text.contains("1 run, 1 byte differs"), "{text}");
}

#[test]
fn diff_groups_adjacent_bytes_into_one_line() {
    let dir = tempfile::tempdir().unwrap();
    let a = snapshot(dir.path(), "a", 1_000_000_000, &[]);
    let b = snapshot(dir.path(), "b", 1_000_000_100, &[(10, 1), (11, 2), (12, 3)]);

    let text = stdout(&run(&["diff", s(&a), s(&b)]));

    assert!(text.contains("0x000a  00 00 00 -> 01 02 03"), "{text}");
    assert!(text.contains("1 run, 3 bytes differ"), "{text}");
}

#[test]
fn identical_snapshots_say_so_and_exit_zero() {
    let dir = tempfile::tempdir().unwrap();
    let a = snapshot(dir.path(), "a", 1_000_000_000, &[(5, 9)]);
    let b = snapshot(dir.path(), "b", 1_000_000_100, &[(5, 9)]);

    let out = run(&["diff", s(&a), s(&b)]);

    assert_eq!(code(&out), 0);
    assert!(stdout(&out).contains("no differences"), "{}", stdout(&out));
}

#[test]
fn a_baseline_marks_positions_that_change_on_their_own_as_volatile() {
    let dir = tempfile::tempdir().unwrap();
    // a and the baseline are two reads of the untouched device; they differ at 50.
    let a = snapshot(dir.path(), "a", 1_000_000_000, &[]);
    let untouched = snapshot(dir.path(), "c", 1_000_000_050, &[(50, 7)]);
    let b = snapshot(dir.path(), "b", 1_000_000_100, &[(50, 9), (100, 1)]);

    let out = run(&["diff", s(&a), s(&b), "--baseline", s(&untouched)]);

    assert_eq!(code(&out), 0, "{}", stderr(&out));
    let text = stdout(&out);
    assert!(text.contains("0x0032  00 -> 09  (volatile)"), "{text}");
    assert!(text.contains("0x0064  00 -> 01\n"), "{text}");
    assert!(
        text.contains("2 runs, 2 bytes differ (1 volatile)"),
        "{text}"
    );
}

#[test]
fn diff_can_emit_json() {
    let dir = tempfile::tempdir().unwrap();
    let a = snapshot(dir.path(), "a", 1_000_000_000, &[]);
    let b = snapshot(dir.path(), "b", 1_000_000_100, &[(100, 0x42)]);

    let out = run(&["--json", "diff", s(&a), s(&b)]);

    assert_eq!(code(&out), 0, "{}", stderr(&out));
    let json: serde_json::Value = serde_json::from_str(&stdout(&out)).unwrap();
    assert_eq!(json["runs"][0]["offset"], 100);
    assert_eq!(json["runs"][0]["before"], serde_json::json!([0]));
    assert_eq!(json["runs"][0]["after"], serde_json::json!([66]));
    assert_eq!(json["runs"][0]["volatile"], false);
    assert_eq!(json["differing_bytes"], 1);
    assert_eq!(json["volatile_bytes"], 0);
}

#[test]
fn a_missing_snapshot_exits_one_and_names_the_path() {
    let dir = tempfile::tempdir().unwrap();
    let a = snapshot(dir.path(), "a", 1_000_000_000, &[]);
    let missing = dir.path().join("nope.bin");

    let out = run(&["diff", s(&a), s(&missing)]);

    assert_eq!(code(&out), 1);
    assert!(stderr(&out).contains("nope.json"), "{}", stderr(&out));
}

#[test]
fn a_tampered_snapshot_fails_the_hash_check() {
    let dir = tempfile::tempdir().unwrap();
    let a = snapshot(dir.path(), "a", 1_000_000_000, &[]);
    let b = snapshot(dir.path(), "b", 1_000_000_100, &[]);
    let mut raw = std::fs::read(&b).unwrap();
    raw[7] ^= 0xff;
    std::fs::write(&b, raw).unwrap();

    let out = run(&["diff", s(&a), s(&b)]);

    assert_eq!(code(&out), 1);
    assert!(stderr(&out).contains("sha256"), "{}", stderr(&out));
}

#[test]
fn dump_with_no_aquaero_connected_exits_one_and_says_so() {
    let sys = tempfile::tempdir().unwrap();
    let out_dir = tempfile::tempdir().unwrap();

    let out = run(&[
        "--sysfs-root",
        s(sys.path()),
        "--dev-dir",
        s(sys.path()),
        "dump",
        "--out",
        s(out_dir.path()),
    ]);

    assert_eq!(code(&out), 1);
    assert!(
        stderr(&out).contains("no aquaero is connected"),
        "{}",
        stderr(&out)
    );
    assert_eq!(std::fs::read_dir(out_dir.path()).unwrap().count(), 0);
}

#[test]
fn dump_with_two_devices_and_no_serial_exits_four() {
    let sys = tempfile::tempdir().unwrap();
    for (n, phys, uniq) in [
        (3, "usb-a-3/input0", "11111-22222"),
        (5, "usb-a-4/input0", "33333-44444"),
    ] {
        let dir = sys.path().join(format!("class/hidraw/hidraw{n}/device"));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(
            dir.join("uevent"),
            format!("HID_ID=0003:00000C70:0000F001\nHID_PHYS={phys}\nHID_UNIQ={uniq}\n"),
        )
        .unwrap();
    }
    let out_dir = tempfile::tempdir().unwrap();

    let out = run(&[
        "--sysfs-root",
        s(sys.path()),
        "--dev-dir",
        s(sys.path()),
        "dump",
        "--out",
        s(out_dir.path()),
    ]);

    assert_eq!(code(&out), 4);
    assert!(stderr(&out).contains("--serial"), "{}", stderr(&out));
    assert!(stderr(&out).contains("11111-22222"), "{}", stderr(&out));
}
