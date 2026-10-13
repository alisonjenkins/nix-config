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

fn fixture(name: &str) -> ConfigBytes {
    let path = format!("{}/tests/fixtures/{name}", env!("CARGO_MANIFEST_DIR"));
    ConfigBytes::new(std::fs::read(path).unwrap()).unwrap()
}

/// Writes `bytes` as a snapshot with a sidecar and returns its `.bin` path.
fn snapshot_of(
    dir: &Path,
    bytes: ConfigBytes,
    serial: &str,
    firmware: u32,
    secs: i64,
    label: &str,
) -> PathBuf {
    ConfigSnapshot::new(
        bytes,
        serial.to_string(),
        firmware,
        UtcTimestamp::from_unix(secs),
        label,
    )
    .write_to(dir)
    .unwrap()
    .bin
}

fn fixture_snapshot(dir: &Path, name: &str) -> PathBuf {
    snapshot_of(
        dir,
        fixture(name),
        "12345-54321",
        1200,
        1_000_000_000,
        "fixture",
    )
}

fn desired_json(points: &[(f64, f64)]) -> String {
    let points: Vec<serde_json::Value> = points
        .iter()
        .map(|(temp, percent)| serde_json::json!({"temp": temp, "percent": percent}))
        .collect();
    serde_json::json!({
        "fans": {"4": {"sensor": 1, "min_percent": 30.0, "points": points}}
    })
    .to_string()
}

const GOOD_POINTS: [(f64, f64); 3] = [(30.0, 30.0), (40.0, 60.0), (45.0, 100.0)];

fn write_desired(dir: &Path, text: &str) -> PathBuf {
    let path = dir.join("desired.json");
    std::fs::write(&path, text).unwrap();
    path
}

/// A sysfs tree with one aquaero node, `hidraw0`.
fn one_node_tree(sys: &Path) {
    let dir = sys.join("class/hidraw/hidraw0/device");
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(
        dir.join("uevent"),
        "HID_ID=0003:00000C70:0000F001\nHID_PHYS=usb-a-3/input0\nHID_UNIQ=11111-22222\n",
    )
    .unwrap();
}

#[test]
fn show_decodes_a_snapshot_offline() {
    let dir = tempfile::tempdir().unwrap();
    let snap = fixture_snapshot(dir.path(), "after-reflash.bin");

    let out = run(&["show", "--snapshot", s(&snap)]);

    assert_eq!(code(&out), 0, "{}", stderr(&out));
    let text = stdout(&out);
    assert!(text.contains("data version 1200"), "{text}");
    assert!(text.contains("curve controller 1"), "{text}");
}

#[test]
fn show_can_emit_json() {
    let dir = tempfile::tempdir().unwrap();
    let snap = fixture_snapshot(dir.path(), "curve-controller-1.bin");

    let out = run(&["--json", "show", "--snapshot", s(&snap)]);

    assert_eq!(code(&out), 0, "{}", stderr(&out));
    let json: serde_json::Value = serde_json::from_str(&stdout(&out)).unwrap();
    assert_eq!(json["data_version"], 1200);
}

#[test]
fn show_of_an_unknown_data_version_exits_three_and_names_the_versions() {
    let dir = tempfile::tempdir().unwrap();
    let snap = snapshot(dir.path(), "a", 1_000_000_000, &[]);

    let out = run(&["show", "--snapshot", s(&snap)]);

    assert_eq!(code(&out), 3);
    assert!(stderr(&out).contains("known versions"), "{}", stderr(&out));
}

#[test]
fn show_on_an_empty_tree_exits_one() {
    let sys = tempfile::tempdir().unwrap();

    let out = run(&[
        "--sysfs-root",
        s(sys.path()),
        "--dev-dir",
        s(sys.path()),
        "show",
    ]);

    assert_eq!(code(&out), 1);
    assert!(
        stderr(&out).contains("no aquaero is connected"),
        "{}",
        stderr(&out)
    );
}

#[test]
fn plan_lists_each_change_with_its_byte_positions() {
    let dir = tempfile::tempdir().unwrap();
    let snap = fixture_snapshot(dir.path(), "after-reflash.bin");
    let desired = write_desired(dir.path(), &desired_json(&GOOD_POINTS));

    let out = run(&["plan", "--desired", s(&desired), "--snapshot", s(&snap)]);

    assert_eq!(code(&out), 0, "{}", stderr(&out));
    let text = stdout(&out);
    assert!(text.contains("fan 4 minimum power: "), "{text}");
    assert!(text.contains(" -> "), "{text}");
    assert!(text.contains("(bytes 0x"), "{text}");
    assert!(
        text.contains("changes; every other byte is unchanged"),
        "{text}"
    );
}

#[test]
fn plan_can_emit_json() {
    let dir = tempfile::tempdir().unwrap();
    let snap = fixture_snapshot(dir.path(), "after-reflash.bin");
    let desired = write_desired(dir.path(), &desired_json(&GOOD_POINTS));

    let out = run(&[
        "--json",
        "plan",
        "--desired",
        s(&desired),
        "--snapshot",
        s(&snap),
    ]);

    assert_eq!(code(&out), 0, "{}", stderr(&out));
    let json: serde_json::Value = serde_json::from_str(&stdout(&out)).unwrap();
    assert_eq!(json["already_applied"], false);
    assert_eq!(json["untouched_equal"], true);
    let first = &json["changes"][0];
    assert!(first["name"].is_string());
    assert!(first["old"].is_string());
    assert!(first["new"].is_string());
    assert_eq!(first["positions"][0].as_array().unwrap().len(), 2);
}

#[test]
fn plan_against_a_snapshot_already_holding_the_state_says_so() {
    use aquaero_ctl::curve::{FanCurve, Point};
    use aquaero_ctl::plan::build_plan;
    use aquaero_ctl::profile::Profile;

    let dir = tempfile::tempdir().unwrap();
    let curve = FanCurve {
        fan: 4,
        sensor: 1,
        min_percent: 30.0,
        points: GOOD_POINTS
            .iter()
            .map(|&(temp, percent)| Point { temp, percent })
            .collect(),
    };
    let plan = build_plan(
        &fixture("after-reflash.bin"),
        &curve,
        &Profile::for_data_version(1200).unwrap(),
    )
    .unwrap();
    let snap = snapshot_of(
        dir.path(),
        plan.intended,
        "12345-54321",
        1200,
        1_000_000_000,
        "intended",
    );
    let desired = write_desired(dir.path(), &desired_json(&GOOD_POINTS));

    let out = run(&["plan", "--desired", s(&desired), "--snapshot", s(&snap)]);

    assert_eq!(code(&out), 0, "{}", stderr(&out));
    assert!(
        stdout(&out).contains("already as desired; nothing to write"),
        "{}",
        stdout(&out)
    );
}

#[test]
fn plan_of_an_unknown_data_version_exits_three() {
    let dir = tempfile::tempdir().unwrap();
    let snap = snapshot(dir.path(), "a", 1_000_000_000, &[]);
    let desired = write_desired(dir.path(), &desired_json(&GOOD_POINTS));

    let out = run(&["plan", "--desired", s(&desired), "--snapshot", s(&snap)]);

    assert_eq!(code(&out), 3, "{}", stderr(&out));
}

#[test]
fn plan_of_a_curve_with_a_decreasing_temperature_exits_two() {
    let dir = tempfile::tempdir().unwrap();
    let snap = fixture_snapshot(dir.path(), "after-reflash.bin");
    let desired = write_desired(
        dir.path(),
        &desired_json(&[(40.0, 30.0), (30.0, 60.0), (45.0, 100.0)]),
    );

    let out = run(&["plan", "--desired", s(&desired), "--snapshot", s(&snap)]);

    assert_eq!(code(&out), 2);
    assert!(
        stderr(&out).contains("does not rise above"),
        "{}",
        stderr(&out)
    );
}

#[test]
fn a_desired_file_that_does_not_parse_exits_two() {
    let dir = tempfile::tempdir().unwrap();
    let snap = fixture_snapshot(dir.path(), "after-reflash.bin");
    let desired = write_desired(dir.path(), "{ not json");

    let out = run(&["plan", "--desired", s(&desired), "--snapshot", s(&snap)]);

    assert_eq!(code(&out), 2);
    assert!(stderr(&out).contains("not valid"), "{}", stderr(&out));
}

#[test]
fn a_desired_file_with_no_fans_exits_two() {
    let dir = tempfile::tempdir().unwrap();
    let snap = fixture_snapshot(dir.path(), "after-reflash.bin");
    let desired = write_desired(dir.path(), r#"{"fans": {}}"#);

    let out = run(&["plan", "--desired", s(&desired), "--snapshot", s(&snap)]);

    assert_eq!(code(&out), 2);
}

#[test]
fn a_missing_desired_file_exits_two_and_names_it() {
    let dir = tempfile::tempdir().unwrap();
    let missing = dir.path().join("nope-desired.json");

    let out = run(&["plan", "--desired", s(&missing)]);

    assert_eq!(code(&out), 2);
    assert!(
        stderr(&out).contains("nope-desired.json"),
        "{}",
        stderr(&out)
    );
}

#[test]
fn an_invalid_desired_file_stops_the_applying_command_with_exit_two() {
    let dir = tempfile::tempdir().unwrap();
    let sys = tempfile::tempdir().unwrap();
    let desired = write_desired(dir.path(), "{ not json");

    let out = run(&[
        "--sysfs-root",
        s(sys.path()),
        "--dev-dir",
        s(sys.path()),
        "apply",
        "--desired",
        s(&desired),
    ]);

    assert_eq!(code(&out), 2, "{}", stderr(&out));
}

#[test]
fn the_applying_command_with_no_aquaero_warns_and_exits_zero() {
    let dir = tempfile::tempdir().unwrap();
    let sys = tempfile::tempdir().unwrap();
    let desired = write_desired(dir.path(), &desired_json(&GOOD_POINTS));
    let tree = ["--sysfs-root", s(sys.path()), "--dev-dir", s(sys.path())];

    let mut args = tree.to_vec();
    args.extend(["apply", "--desired", s(&desired)]);
    let out = run(&args);

    assert_eq!(code(&out), 0, "{}", stderr(&out));
    assert!(
        stderr(&out).contains("no aquaero is connected"),
        "{}",
        stderr(&out)
    );

    let out_dir = dir.path().join("dumps");
    let mut args = tree.to_vec();
    args.extend(["dump", "--out", s(&out_dir)]);
    assert_eq!(code(&run(&args)), 1);
}

#[test]
fn the_applying_command_exits_seven_while_another_instance_holds_the_lock() {
    use aquaero_ctl::lock::DeviceLock;

    let dir = tempfile::tempdir().unwrap();
    let sys = tempfile::tempdir().unwrap();
    one_node_tree(sys.path());
    let desired = write_desired(dir.path(), &desired_json(&GOOD_POINTS));
    let lock_path = dir.path().join("test.lock");
    let _held = DeviceLock::acquire(&lock_path).unwrap();

    let out = run(&[
        "--sysfs-root",
        s(sys.path()),
        "--dev-dir",
        s(sys.path()),
        "--lock-file",
        s(&lock_path),
        "apply",
        "--desired",
        s(&desired),
        "--backup-dir",
        s(&dir.path().join("backups")),
    ]);

    assert_eq!(code(&out), 7, "{}", stderr(&out));
}

#[test]
fn putting_a_snapshot_back_without_yes_and_without_a_terminal_exits_two() {
    let dir = tempfile::tempdir().unwrap();
    let snap = fixture_snapshot(dir.path(), "after-reflash.bin");

    let out = run(&["restore", s(&snap)]);

    assert_eq!(code(&out), 2, "{}", stderr(&out));
    assert!(stderr(&out).contains("--yes"), "{}", stderr(&out));
}

#[test]
fn putting_back_a_snapshot_with_no_profile_exits_three() {
    let dir = tempfile::tempdir().unwrap();
    let snap = snapshot(dir.path(), "a", 1_000_000_000, &[]);

    let out = run(&["restore", s(&snap), "--yes"]);

    assert_eq!(code(&out), 3, "{}", stderr(&out));
}

#[test]
fn putting_a_snapshot_back_with_no_aquaero_connected_exits_one() {
    let dir = tempfile::tempdir().unwrap();
    let sys = tempfile::tempdir().unwrap();
    let snap = fixture_snapshot(dir.path(), "after-reflash.bin");

    let out = run(&[
        "--sysfs-root",
        s(sys.path()),
        "--dev-dir",
        s(sys.path()),
        "restore",
        s(&snap),
        "--yes",
    ]);

    assert_eq!(code(&out), 1, "{}", stderr(&out));
}

fn two_backups(dir: &Path) -> (PathBuf, PathBuf) {
    let older = snapshot_of(
        dir,
        bytes_with(&[]),
        "11111-22222",
        1200,
        1_000_000_000,
        "pre-apply",
    );
    let newer = snapshot_of(
        dir,
        bytes_with(&[(9, 1)]),
        "33333-44444",
        1200,
        1_000_000_500,
        "pre-restore",
    );
    (older, newer)
}

#[test]
fn list_backups_lists_the_newest_first() {
    let dir = tempfile::tempdir().unwrap();
    let (older, newer) = two_backups(dir.path());

    let out = run(&["list-backups", "--backup-dir", s(dir.path())]);

    assert_eq!(code(&out), 0, "{}", stderr(&out));
    let text = stdout(&out);
    let at_newer = text.find(s(&newer)).unwrap();
    let at_older = text.find(s(&older)).unwrap();
    assert!(at_newer < at_older, "{text}");
    assert!(text.contains("pre-restore"), "{text}");
    assert!(text.contains("33333-44444"), "{text}");
    assert!(text.contains("2001-09-09T01:55:00Z"), "{text}");
    assert!(text.contains("1200"), "{text}");
}

#[test]
fn list_backups_filters_by_serial() {
    let dir = tempfile::tempdir().unwrap();
    let (older, newer) = two_backups(dir.path());

    let out = run(&[
        "--serial",
        "11111-22222",
        "list-backups",
        "--backup-dir",
        s(dir.path()),
    ]);

    assert_eq!(code(&out), 0, "{}", stderr(&out));
    let text = stdout(&out);
    assert!(text.contains(s(&older)), "{text}");
    assert!(!text.contains(s(&newer)), "{text}");
}

#[test]
fn list_backups_can_emit_json() {
    let dir = tempfile::tempdir().unwrap();
    let (_, newer) = two_backups(dir.path());

    let out = run(&["--json", "list-backups", "--backup-dir", s(dir.path())]);

    assert_eq!(code(&out), 0, "{}", stderr(&out));
    let json: serde_json::Value = serde_json::from_str(&stdout(&out)).unwrap();
    assert_eq!(json.as_array().unwrap().len(), 2);
    assert_eq!(json[0]["bin"], s(&newer));
    assert_eq!(json[0]["serial"], "33333-44444");
    assert_eq!(json[0]["data_version"], 1200);
}

#[test]
fn list_backups_of_an_empty_directory_says_so() {
    let dir = tempfile::tempdir().unwrap();

    let out = run(&["list-backups", "--backup-dir", s(dir.path())]);

    assert_eq!(code(&out), 0, "{}", stderr(&out));
    assert!(stdout(&out).contains("no backups"), "{}", stdout(&out));
}

#[test]
fn list_backups_of_a_missing_directory_says_so() {
    let dir = tempfile::tempdir().unwrap();

    let out = run(&[
        "list-backups",
        "--backup-dir",
        s(&dir.path().join("absent")),
    ]);

    assert_eq!(code(&out), 0, "{}", stderr(&out));
    assert!(stdout(&out).contains("no backups"), "{}", stdout(&out));
}

fn list_backups_with_env(env: &[(&str, &Path)]) -> Output {
    let mut command = Command::new(env!("CARGO_BIN_EXE_aquaero-ctl"));
    command
        .arg("list-backups")
        .env_remove("STATE_DIRECTORY")
        .env_remove("XDG_STATE_HOME")
        .env_remove("HOME");
    for (key, value) in env {
        command.env(key, value);
    }
    command.output().unwrap()
}

#[test]
fn the_default_backup_directory_follows_state_directory_first() {
    let state = tempfile::tempdir().unwrap();
    let xdg = tempfile::tempdir().unwrap();
    let (_, newer) = two_backups(&state.path().join("backups"));

    let out = list_backups_with_env(&[
        ("STATE_DIRECTORY", state.path()),
        ("XDG_STATE_HOME", xdg.path()),
    ]);

    assert_eq!(code(&out), 0, "{}", stderr(&out));
    assert!(stdout(&out).contains(s(&newer)), "{}", stdout(&out));
}

#[test]
fn the_default_backup_directory_falls_back_to_xdg_state_home() {
    let xdg = tempfile::tempdir().unwrap();
    let (_, newer) = two_backups(&xdg.path().join("aquaero-ctl/backups"));

    let out = list_backups_with_env(&[("XDG_STATE_HOME", xdg.path())]);

    assert_eq!(code(&out), 0, "{}", stderr(&out));
    assert!(stdout(&out).contains(s(&newer)), "{}", stdout(&out));
}

#[test]
fn the_default_backup_directory_falls_back_to_home() {
    let home = tempfile::tempdir().unwrap();
    let (_, newer) = two_backups(&home.path().join(".local/state/aquaero-ctl/backups"));

    let out = list_backups_with_env(&[("HOME", home.path())]);

    assert_eq!(code(&out), 0, "{}", stderr(&out));
    assert!(stdout(&out).contains(s(&newer)), "{}", stdout(&out));
}
