// Panicking on a bad fixture is the correct failure inside a test.
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects,
    clippy::panic
)]

mod common;

use std::path::PathBuf;
use std::time::Duration;

use aquaero_ctl::apply::{apply_config, preview, ApplyOptions, ApplyReport, CommitReport};
use aquaero_ctl::error::ApplyError;
use aquaero_ctl::fake::{Fault, OpKind};
use aquaero_ctl::hid::{
    HidDevice, CONTROL_GAP, CTRL_REPORT_ID, SECONDARY_REPORT_ID, SECONDARY_REPORT_LEN,
};
use aquaero_ctl::lock::{DeviceLock, SpacedDevice};
use aquaero_ctl::snapshot::ConfigSnapshot;
use aquaero_ctl::timestamp::UtcTimestamp;
use common::{config, config_with, device_holding, FIRMWARE, SERIAL};

fn options(dir: &std::path::Path) -> ApplyOptions {
    ApplyOptions {
        backup_dir: dir.to_path_buf(),
        commit_reports: vec![],
    }
}

fn now() -> UtcTimestamp {
    UtcTimestamp::from_unix(1_700_000_000)
}

fn backup_files(dir: &std::path::Path) -> Vec<PathBuf> {
    match std::fs::read_dir(dir) {
        Ok(entries) => entries.map(|e| e.unwrap().path()).collect(),
        Err(_) => vec![],
    }
}

#[test]
fn applying_a_different_configuration_writes_it_and_reports_the_changes() {
    let backups = tempfile::tempdir().unwrap();
    let original = config(0x11);
    let intended = config_with(0x11, &[(300, 0xaa), (301, 0xbb), (900, 0xcc)]);
    let (mut dev, _) = device_holding(original.clone());

    let report = apply_config(&mut dev, &intended, &options(backups.path()), now()).unwrap();

    assert_eq!(dev.config(), intended);
    match report {
        ApplyReport::Applied { changes, .. } => {
            let offsets: Vec<usize> = changes.iter().map(|c| c.offset).collect();
            assert_eq!(offsets, vec![300, 900]);
        }
        other => panic!("{other:?}"),
    }
}

#[test]
fn the_backup_is_a_snapshot_of_what_was_on_the_device() {
    let backups = tempfile::tempdir().unwrap();
    let original = config(0x11);
    let (mut dev, _) = device_holding(original.clone());

    let report = apply_config(&mut dev, &config(0x22), &options(backups.path()), now()).unwrap();

    let ApplyReport::Applied { backup, .. } = report else {
        panic!("expected a write");
    };
    let snap = ConfigSnapshot::read(&backup.bin).unwrap();
    assert_eq!(snap.bytes(), &original);
    assert_eq!(snap.meta().serial, SERIAL);
    assert_eq!(snap.meta().firmware, FIRMWARE);
    assert_eq!(snap.meta().label, "pre-apply");
    assert_eq!(snap.meta().taken_at, "2023-11-14T22:13:20Z");
}

#[test]
fn the_backup_exists_even_when_the_write_is_rejected() {
    let backups = tempfile::tempdir().unwrap();
    let (mut dev, _) = device_holding(config(0x11));
    dev.inject(Fault::RejectNextWrite);

    let err = apply_config(&mut dev, &config(0x22), &options(backups.path()), now()).unwrap_err();

    assert!(matches!(err, ApplyError::Write { .. }), "{err:?}");
    assert_eq!(backup_files(backups.path()).len(), 2, "a .bin and a .json");
}

#[test]
fn no_backup_means_no_write() {
    let dir = tempfile::tempdir().unwrap();
    // A file where the backup directory should be: the backup cannot be saved.
    let blocked = dir.path().join("blocked");
    std::fs::write(&blocked, "not a directory").unwrap();
    let (mut dev, _) = device_holding(config(0x11));

    let err = apply_config(&mut dev, &config(0x22), &options(&blocked), now()).unwrap_err();

    assert!(matches!(err, ApplyError::Backup { .. }), "{err:?}");
    assert_eq!(dev.writes_applied(), 0);
    assert!(dev.ops().iter().all(|op| op.kind == OpKind::Get));
    assert_eq!(dev.config(), config(0x11));
}

#[test]
fn an_already_applied_configuration_writes_nothing_and_saves_nothing() {
    let backups = tempfile::tempdir().unwrap();
    let (mut dev, _) = device_holding(config(0x11));

    let report = apply_config(&mut dev, &config(0x11), &options(backups.path()), now()).unwrap();

    assert!(matches!(report, ApplyReport::AlreadyApplied));
    assert_eq!(dev.writes_applied(), 0);
    assert!(backup_files(backups.path()).is_empty());
}

#[test]
fn the_write_is_verified_by_reading_it_back() {
    let backups = tempfile::tempdir().unwrap();
    let (mut dev, _) = device_holding(config(0x11));
    dev.inject(Fault::DriftAfterNextWrite { offset: 200 });

    let err = apply_config(&mut dev, &config(0x22), &options(backups.path()), now()).unwrap_err();

    match err {
        ApplyError::Mismatch { runs, backup } => {
            assert_eq!(runs.len(), 1);
            assert_eq!(runs[0].offset, 200);
            assert_eq!(runs[0].before, vec![0x22]);
            assert_eq!(runs[0].after, vec![0x22 ^ 0xff]);
            assert!(backup.bin.exists());
        }
        other => panic!("{other:?}"),
    }
}

#[test]
fn a_preview_reports_the_changes_and_touches_nothing() {
    let backups = tempfile::tempdir().unwrap();
    let (mut dev, _) = device_holding(config(0x11));

    let runs = preview(&mut dev, &config_with(0x11, &[(500, 7)])).unwrap();

    assert_eq!(runs.len(), 1);
    assert_eq!(runs[0].offset, 500);
    assert_eq!(dev.writes_applied(), 0);
    assert!(dev.ops().iter().all(|op| op.kind == OpKind::Get));
    assert!(backup_files(backups.path()).is_empty());
}

#[test]
fn the_commit_reports_follow_the_configuration_write_in_order() {
    let backups = tempfile::tempdir().unwrap();
    let (mut dev, _) = device_holding(config(0x11));
    let mut save = vec![0u8; SECONDARY_REPORT_LEN];
    save[0] = SECONDARY_REPORT_ID;
    save[1] = 2;
    let opts = ApplyOptions {
        backup_dir: backups.path().to_path_buf(),
        commit_reports: vec![CommitReport {
            bytes: save.clone(),
            delay_before: Duration::ZERO,
        }],
    };

    apply_config(&mut dev, &config(0x22), &opts, now()).unwrap();

    let sets: Vec<u8> = dev
        .ops()
        .iter()
        .filter(|op| op.kind == OpKind::Set)
        .map(|op| op.report_id)
        .collect();
    assert_eq!(sets, vec![CTRL_REPORT_ID, SECONDARY_REPORT_ID]);
    assert_eq!(dev.secondary_reports(), &[save]);
    // The read-back comes after the commit.
    assert_eq!(dev.ops().last().unwrap().kind, OpKind::Get);
}

#[test]
fn a_commit_report_waits_its_delay_after_the_configuration_write() {
    // Aquasuite sends the save command about 4.1 s after the configuration.
    let backups = tempfile::tempdir().unwrap();
    let (mut dev, _) = device_holding(config(0x11));
    let mut save = vec![0u8; SECONDARY_REPORT_LEN];
    save[0] = SECONDARY_REPORT_ID;
    save[2] = 2;
    let opts = ApplyOptions {
        backup_dir: backups.path().to_path_buf(),
        commit_reports: vec![CommitReport {
            bytes: save,
            delay_before: Duration::from_millis(4100),
        }],
    };

    apply_config(&mut dev, &config(0x22), &opts, now()).unwrap();

    let ops = dev.ops();
    let write = ops
        .iter()
        .find(|op| op.kind == OpKind::Set && op.report_id == CTRL_REPORT_ID)
        .unwrap();
    let commit = ops
        .iter()
        .find(|op| op.kind == OpKind::Set && op.report_id == SECONDARY_REPORT_ID)
        .unwrap();
    assert!(commit.at - write.at >= Duration::from_millis(4100));
}

#[test]
fn operations_through_the_spaced_device_keep_the_gap() {
    let backups = tempfile::tempdir().unwrap();
    let lock_dir = tempfile::tempdir().unwrap();
    let mut lock = DeviceLock::acquire(&lock_dir.path().join("l")).unwrap();
    let (dev, clock) = device_holding(config(0x11));

    let mut spaced = aquaero_ctl::lock::SpacedDevice::new(dev, &mut lock, &clock);
    apply_config(&mut spaced, &config(0x22), &options(backups.path()), now()).unwrap();

    let gaps = spaced.into_inner().observed_gaps();
    assert!(!gaps.is_empty());
    assert!(gaps.iter().all(|g| *g >= CONTROL_GAP), "{gaps:?}");
}

#[test]
fn a_configuration_with_the_wrong_report_id_is_refused_before_any_device_access() {
    let backups = tempfile::tempdir().unwrap();
    let (mut dev, _) = device_holding(config(0x11));
    let mut bytes = config(0x22).as_slice().to_vec();
    bytes[0] = 0x01;
    let wrong = aquaero_ctl::snapshot::ConfigBytes::new(bytes).unwrap();

    let err = apply_config(&mut dev, &wrong, &options(backups.path()), now()).unwrap_err();

    assert!(
        matches!(
            err,
            ApplyError::InvalidIntended {
                expected: 0x0b,
                got: 0x01
            }
        ),
        "{err:?}"
    );
    assert!(dev.ops().is_empty());
    assert!(backup_files(backups.path()).is_empty());
}

#[test]
fn spaced_device_is_usable_as_a_trait_object() {
    // Guards the signature: apply takes `&mut dyn HidDevice`.
    let lock_dir = tempfile::tempdir().unwrap();
    let mut lock = DeviceLock::acquire(&lock_dir.path().join("l")).unwrap();
    let (dev, clock) = device_holding(config(0x11));
    let mut spaced = SpacedDevice::new(dev, &mut lock, &clock);
    let as_dyn: &mut dyn HidDevice = &mut spaced;
    assert!(as_dyn.path().to_string_lossy().contains("fake"));
}
