// Panicking on a bad fixture is the correct failure inside a test.
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects,
    clippy::panic
)]

mod common;

use std::error::Error;
use std::path::{Path, PathBuf};

use aquaero_ctl::apply::{apply_config, ApplyOptions};
use aquaero_ctl::error::{ApplyError, HidError};
use aquaero_ctl::fake::{FakeDevice, Fault};
use aquaero_ctl::snapshot::ConfigBytes;
use aquaero_ctl::timestamp::UtcTimestamp;
use common::{config, device_holding};

fn options(dir: &Path) -> ApplyOptions {
    ApplyOptions {
        backup_dir: dir.to_path_buf(),
        commit_reports: vec![],
    }
}

fn now() -> UtcTimestamp {
    UtcTimestamp::from_unix(1_700_000_000)
}

fn backup_bins(dir: &Path) -> Vec<PathBuf> {
    std::fs::read_dir(dir)
        .map(|entries| {
            entries
                .map(|e| e.unwrap().path())
                .filter(|p| p.extension().is_some_and(|x| x == "bin"))
                .collect()
        })
        .unwrap_or_default()
}

/// The whole message an owner would see: the error and every cause.
fn full_message(error: &dyn Error) -> String {
    let mut text = error.to_string();
    let mut source = error.source();
    while let Some(cause) = source {
        text.push_str(" | ");
        text.push_str(&cause.to_string());
        source = cause.source();
    }
    text
}

fn run(fault: Option<Fault>) -> (Result<(), ApplyError>, FakeDevice, tempfile::TempDir) {
    let backups = tempfile::tempdir().unwrap();
    let (mut dev, _) = device_holding(config(0x11));
    if let Some(fault) = fault {
        dev.inject(fault);
    }
    let result = apply_config(&mut dev, &config(0x22), &options(backups.path()), now()).map(|_| ());
    (result, dev, backups)
}

#[test]
fn a_rejected_write_names_the_backup_and_the_restore_command() {
    let (result, dev, backups) = run(Some(Fault::RejectNextWrite));
    let err = result.unwrap_err();

    assert!(matches!(err, ApplyError::Write { .. }), "{err:?}");
    assert_eq!(dev.config(), config(0x11));
    let bin = &backup_bins(backups.path())[0];
    let message = full_message(&err);
    assert!(message.contains(bin.to_str().unwrap()), "{message}");
    assert!(message.contains("aquaero-ctl restore"), "{message}");
}

#[test]
fn a_short_initial_read_writes_nothing_and_saves_no_backup() {
    let (result, dev, backups) = run(Some(Fault::ShortReadNext { bytes: 10 }));
    let err = result.unwrap_err();

    assert!(
        matches!(
            err,
            ApplyError::Read {
                source: HidError::ShortRead { got: 10, .. }
            }
        ),
        "{err:?}"
    );
    assert_eq!(dev.writes_applied(), 0);
    assert!(backup_bins(backups.path()).is_empty());
}

#[test]
fn a_disconnect_before_the_write_leaves_the_original() {
    // One operation (the initial read) is allowed, then the device is gone.
    let (result, dev, backups) = run(Some(Fault::DisconnectAfter { ops: 1 }));
    let err = result.unwrap_err();

    assert!(
        matches!(
            &err,
            ApplyError::Write {
                source: HidError::Disconnected { .. },
                ..
            }
        ),
        "{err:?}"
    );
    assert_eq!(dev.config(), config(0x11));
    assert_eq!(backup_bins(backups.path()).len(), 1);
}

#[test]
fn a_disconnect_after_the_write_says_the_device_holds_the_new_configuration() {
    // Read and write are allowed; the read-back finds the device gone.
    let (result, dev, backups) = run(Some(Fault::DisconnectAfter { ops: 2 }));
    let err = result.unwrap_err();

    assert!(matches!(err, ApplyError::ReadBack { .. }), "{err:?}");
    assert_eq!(dev.config(), config(0x22));
    let message = full_message(&err);
    assert!(
        message.contains(backup_bins(backups.path())[0].to_str().unwrap()),
        "{message}"
    );
    assert!(message.contains("not verified"), "{message}");
}

#[test]
fn a_mismatch_shows_the_offset_both_values_and_the_backup() {
    let (result, _dev, backups) = run(Some(Fault::DriftAfterNextWrite { offset: 200 }));
    let err = result.unwrap_err();

    let message = full_message(&err);
    assert!(message.contains("0x00c8"), "{message}");
    assert!(message.contains("22"), "{message}");
    assert!(message.contains("dd"), "{message}");
    assert!(
        message.contains(backup_bins(backups.path())[0].to_str().unwrap()),
        "{message}"
    );
}

/// SC-006: whatever goes wrong, the device holds the original or the
/// intended configuration (or the owner is told how to restore), and an
/// error that follows a changed device always names the backup.
#[test]
fn every_injected_failure_ends_safe() {
    let original = config(0x11);
    let intended = config(0x22);
    let faults = [
        None,
        Some(Fault::RejectNextWrite),
        Some(Fault::ShortReadNext { bytes: 10 }),
        Some(Fault::DisconnectAfter { ops: 0 }),
        Some(Fault::DisconnectAfter { ops: 1 }),
        Some(Fault::DisconnectAfter { ops: 2 }),
        Some(Fault::DriftAfterNextWrite { offset: 200 }),
        Some(Fault::DriftAfterNextWrite { offset: 1 }),
    ];

    for fault in faults {
        let (result, dev, backups) = run(fault);
        let held: ConfigBytes = dev.config();

        match &result {
            Ok(()) => assert_eq!(held, intended, "{fault:?}: success must mean intended"),
            Err(err) => {
                let message = full_message(err);
                let changed = held != original;
                if changed {
                    let bins = backup_bins(backups.path());
                    assert_eq!(bins.len(), 1, "{fault:?}: a changed device needs a backup");
                    assert!(
                        message.contains(bins[0].to_str().unwrap()),
                        "{fault:?}: {message}"
                    );
                } else {
                    assert_eq!(dev.writes_applied(), 0, "{fault:?}");
                }
            }
        }
    }
}
