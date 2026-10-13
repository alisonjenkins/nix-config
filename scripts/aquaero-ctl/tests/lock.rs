// Panicking on a bad fixture is the correct failure inside a test.
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects,
    clippy::panic
)]

use std::time::Duration;

use aquaero_ctl::error::LockError;
use aquaero_ctl::fake::ManualClock;
use aquaero_ctl::hid::{Clock, CONTROL_GAP};
use aquaero_ctl::lock::DeviceLock;

const MS: fn(u64) -> Duration = Duration::from_millis;

fn lock_path() -> (tempfile::TempDir, std::path::PathBuf) {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("aquaero-ctl.lock");
    (dir, path)
}

#[test]
fn a_free_lock_is_acquired_and_its_file_created() {
    let (_dir, path) = lock_path();
    let _lock = DeviceLock::acquire(&path).unwrap();
    assert!(path.exists());
}

#[test]
fn a_second_holder_is_refused_while_the_first_lives() {
    let (_dir, path) = lock_path();
    let _first = DeviceLock::acquire(&path).unwrap();

    let err = DeviceLock::acquire(&path).unwrap_err();
    assert!(
        matches!(&err, LockError::Held { path: p } if *p == path),
        "{err:?}"
    );
}

#[test]
fn dropping_the_lock_releases_it() {
    let (_dir, path) = lock_path();
    drop(DeviceLock::acquire(&path).unwrap());
    DeviceLock::acquire(&path).unwrap();
}

fn work_that_fails_while_locked(path: &std::path::Path) -> Result<(), String> {
    let _lock = DeviceLock::acquire(path).map_err(|e| e.to_string())?;
    Err("the work failed".to_string())
}

#[test]
fn an_error_path_releases_the_lock() {
    let (_dir, path) = lock_path();

    assert!(work_that_fails_while_locked(&path).is_err());

    DeviceLock::acquire(&path).unwrap();
}

#[test]
fn different_paths_do_not_block_each_other() {
    let dir = tempfile::tempdir().unwrap();
    let _a = DeviceLock::acquire(&dir.path().join("a.lock")).unwrap();
    let _b = DeviceLock::acquire(&dir.path().join("b.lock")).unwrap();
}

#[test]
fn a_missing_directory_is_an_error_naming_the_path() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("no-such-dir").join("x.lock");

    let err = DeviceLock::acquire(&path).unwrap_err();
    assert!(
        matches!(&err, LockError::Create { path: p, .. } if *p == path),
        "{err:?}"
    );
}

#[test]
fn the_first_operation_does_not_wait() {
    let (_dir, path) = lock_path();
    let mut lock = DeviceLock::acquire(&path).unwrap();
    let clock = ManualClock::new();

    assert_eq!(
        lock.wait_for_gap(&clock, CONTROL_GAP).unwrap(),
        Duration::ZERO
    );
    assert_eq!(clock.now(), Duration::ZERO);
}

#[test]
fn an_immediate_second_operation_waits_the_whole_gap() {
    let (_dir, path) = lock_path();
    let mut lock = DeviceLock::acquire(&path).unwrap();
    let clock = ManualClock::new();

    lock.wait_for_gap(&clock, CONTROL_GAP).unwrap();
    let waited = lock.wait_for_gap(&clock, CONTROL_GAP).unwrap();

    assert_eq!(waited, CONTROL_GAP);
    assert_eq!(clock.now(), CONTROL_GAP);
}

#[test]
fn only_the_rest_of_the_gap_is_waited() {
    let (_dir, path) = lock_path();
    let mut lock = DeviceLock::acquire(&path).unwrap();
    let clock = ManualClock::new();

    lock.wait_for_gap(&clock, CONTROL_GAP).unwrap();
    clock.sleep(MS(50));
    let waited = lock.wait_for_gap(&clock, CONTROL_GAP).unwrap();

    assert_eq!(waited, MS(150));
    assert_eq!(clock.now(), MS(200));
}

#[test]
fn no_wait_once_the_gap_has_passed() {
    let (_dir, path) = lock_path();
    let mut lock = DeviceLock::acquire(&path).unwrap();
    let clock = ManualClock::new();

    lock.wait_for_gap(&clock, CONTROL_GAP).unwrap();
    clock.sleep(MS(250));
    assert_eq!(
        lock.wait_for_gap(&clock, CONTROL_GAP).unwrap(),
        Duration::ZERO
    );
}

#[test]
fn the_gap_holds_across_two_runs_of_the_tool() {
    let (_dir, path) = lock_path();
    let clock = ManualClock::new();

    let mut first_run = DeviceLock::acquire(&path).unwrap();
    first_run.wait_for_gap(&clock, CONTROL_GAP).unwrap();
    drop(first_run);

    clock.sleep(MS(80));
    let mut second_run = DeviceLock::acquire(&path).unwrap();
    assert_eq!(
        second_run.wait_for_gap(&clock, CONTROL_GAP).unwrap(),
        MS(120)
    );
}

#[test]
fn an_unreadable_record_counts_as_no_previous_operation() {
    let (_dir, path) = lock_path();
    std::fs::write(&path, "not a number").unwrap();
    let mut lock = DeviceLock::acquire(&path).unwrap();
    let clock = ManualClock::new();

    assert_eq!(
        lock.wait_for_gap(&clock, CONTROL_GAP).unwrap(),
        Duration::ZERO
    );
}

#[test]
fn a_clock_that_jumped_back_never_waits_longer_than_one_gap() {
    let (_dir, path) = lock_path();
    let clock = ManualClock::new();
    clock.sleep(Duration::from_secs(60));

    let mut lock = DeviceLock::acquire(&path).unwrap();
    lock.wait_for_gap(&clock, CONTROL_GAP).unwrap();
    drop(lock);

    // A fresh clock reads far earlier than the recorded operation.
    let earlier = ManualClock::new();
    let mut lock = DeviceLock::acquire(&path).unwrap();
    let waited = lock.wait_for_gap(&earlier, CONTROL_GAP).unwrap();

    assert_eq!(waited, CONTROL_GAP);
}
