// Panicking on a bad fixture is the correct failure inside a test.
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects,
    clippy::panic
)]

mod common;

use std::path::Path;

use aquaero_ctl::apply::{restore_config, ApplyOptions, ApplyReport};
use aquaero_ctl::diff::{diff, VolatileSet};
use aquaero_ctl::error::{ApplyError, RestoreError};
use aquaero_ctl::fake::Fault;
use aquaero_ctl::snapshot::ConfigSnapshot;
use aquaero_ctl::timestamp::UtcTimestamp;
use common::{config, config_with, device_holding, FIRMWARE, SERIAL};

fn options(dir: &Path) -> ApplyOptions {
    ApplyOptions {
        backup_dir: dir.to_path_buf(),
        commit_reports: vec![],
    }
}

fn now() -> UtcTimestamp {
    UtcTimestamp::from_unix(1_700_000_000)
}

fn snapshot_of(
    bytes: aquaero_ctl::snapshot::ConfigBytes,
    serial: &str,
    firmware: u32,
) -> ConfigSnapshot {
    ConfigSnapshot::new(bytes, serial.to_string(), firmware, now(), "saved")
}

#[test]
fn restoring_returns_the_device_to_the_snapshot_byte_for_byte() {
    let backups = tempfile::tempdir().unwrap();
    let saved = config_with(0x11, &[(300, 0xaa), (900, 0xbb)]);
    let (mut dev, _) = device_holding(config(0x33));

    let report = restore_config(
        &mut dev,
        &snapshot_of(saved.clone(), SERIAL, FIRMWARE),
        &options(backups.path()),
        now(),
    )
    .unwrap();

    assert!(matches!(report, ApplyReport::Applied { .. }));
    assert_eq!(diff(&dev.config(), &saved, &VolatileSet::none()), vec![]);
}

#[test]
fn a_restore_keeps_a_backup_of_what_it_replaced() {
    let backups = tempfile::tempdir().unwrap();
    let before = config(0x33);
    let (mut dev, _) = device_holding(before.clone());

    let report = restore_config(
        &mut dev,
        &snapshot_of(config(0x11), SERIAL, FIRMWARE),
        &options(backups.path()),
        now(),
    )
    .unwrap();

    let ApplyReport::Applied { backup, .. } = report else {
        panic!("expected a write");
    };
    let snap = ConfigSnapshot::read(&backup.bin).unwrap();
    assert_eq!(snap.bytes(), &before);
    assert_eq!(snap.meta().label, "pre-restore");
}

#[test]
fn restoring_what_is_already_there_writes_nothing() {
    let backups = tempfile::tempdir().unwrap();
    let (mut dev, _) = device_holding(config(0x11));

    let report = restore_config(
        &mut dev,
        &snapshot_of(config(0x11), SERIAL, FIRMWARE),
        &options(backups.path()),
        now(),
    )
    .unwrap();

    assert!(matches!(report, ApplyReport::AlreadyApplied));
    assert_eq!(dev.writes_applied(), 0);
}

#[test]
fn a_snapshot_from_another_device_is_refused() {
    let backups = tempfile::tempdir().unwrap();
    let (mut dev, _) = device_holding(config(0x33));

    let err = restore_config(
        &mut dev,
        &snapshot_of(config(0x11), "99999-99999", FIRMWARE),
        &options(backups.path()),
        now(),
    )
    .unwrap_err();

    match err {
        RestoreError::WrongDevice { snapshot, device } => {
            assert_eq!(snapshot, "99999-99999");
            assert_eq!(device, SERIAL);
        }
        other => panic!("{other:?}"),
    }
    assert_eq!(dev.writes_applied(), 0);
}

#[test]
fn a_snapshot_from_other_firmware_is_refused() {
    let backups = tempfile::tempdir().unwrap();
    let (mut dev, _) = device_holding(config(0x33));

    let err = restore_config(
        &mut dev,
        &snapshot_of(config(0x11), SERIAL, 2104),
        &options(backups.path()),
        now(),
    )
    .unwrap_err();

    assert!(
        matches!(
            err,
            RestoreError::FirmwareMismatch {
                snapshot: 2104,
                device: 1036
            }
        ),
        "{err:?}"
    );
    assert_eq!(dev.writes_applied(), 0);
}

#[test]
fn a_restore_is_verified_by_reading_back() {
    let backups = tempfile::tempdir().unwrap();
    let (mut dev, _) = device_holding(config(0x33));
    dev.inject(Fault::DriftAfterNextWrite { offset: 400 });

    let err = restore_config(
        &mut dev,
        &snapshot_of(config(0x11), SERIAL, FIRMWARE),
        &options(backups.path()),
        now(),
    )
    .unwrap_err();

    assert!(
        matches!(
            err,
            RestoreError::Apply {
                source: ApplyError::Mismatch { .. }
            }
        ),
        "{err:?}"
    );
}
