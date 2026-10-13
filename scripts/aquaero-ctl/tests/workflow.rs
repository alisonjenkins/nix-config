// Panicking on a bad fixture is the correct failure inside a test.
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects,
    clippy::panic
)]

//! The whole sequence (read, profile check, validate, plan, back up, write,
//! save, read back) against the fake device holding a real configuration.

use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

use aquaero_ctl::curve::{FanCurve, Point};
use aquaero_ctl::error::{ApplyError, CurveError, PlanError, ProfileError};
use aquaero_ctl::fake::{FakeDevice, Fault, ManualClock, OpKind};
use aquaero_ctl::hid::{CTRL_REPORT_ID, SECONDARY_REPORT_ID};
use aquaero_ctl::snapshot::ConfigBytes;
use aquaero_ctl::timestamp::UtcTimestamp;
use aquaero_ctl::workflow::{apply_desired, plan_for_device, Outcome, WorkflowError};

fn fixture(name: &str) -> ConfigBytes {
    let path = format!("{}/tests/fixtures/{name}", env!("CARGO_MANIFEST_DIR"));
    ConfigBytes::new(std::fs::read(path).unwrap()).unwrap()
}

fn device(config: ConfigBytes) -> FakeDevice {
    FakeDevice::new(config, Arc::new(ManualClock::new()))
        .with_serial("21998-56576")
        .with_clock_bytes_cleared()
}

fn desired() -> FanCurve {
    FanCurve {
        fan: 4,
        sensor: 1,
        min_percent: 30.0,
        points: vec![
            Point {
                temp: 30.0,
                percent: 30.0,
            },
            Point {
                temp: 40.0,
                percent: 60.0,
            },
            Point {
                temp: 45.0,
                percent: 100.0,
            },
        ],
    }
}

fn now() -> UtcTimestamp {
    UtcTimestamp::from_unix(1_700_000_000)
}

fn files_in(dir: &Path) -> usize {
    std::fs::read_dir(dir).map(|d| d.count()).unwrap_or(0)
}

#[test]
fn check_mode_reports_drift_and_writes_nothing() {
    let backups = tempfile::tempdir().unwrap();
    let mut dev = device(fixture("after-reflash.bin"));

    let outcome = apply_desired(&mut dev, &desired(), true, backups.path(), now()).unwrap();

    match outcome {
        Outcome::Drift { plan, .. } => assert!(!plan.changes.is_empty()),
        other => panic!("{other:?}"),
    }
    assert_eq!(dev.writes_applied(), 0);
    assert!(dev.ops().iter().all(|op| op.kind == OpKind::Get));
    assert_eq!(files_in(backups.path()), 0);
}

#[test]
fn apply_backs_up_writes_saves_and_verifies() {
    let backups = tempfile::tempdir().unwrap();
    let original = fixture("after-reflash.bin");
    let mut dev = device(original.clone());

    let outcome = apply_desired(&mut dev, &desired(), false, backups.path(), now()).unwrap();

    let Outcome::Applied { backup, plan, .. } = outcome else {
        panic!("expected a write");
    };
    assert!(backup.bin.exists());
    assert!(!plan.changes.is_empty());
    assert_eq!(dev.writes_applied(), 1);

    // The save command followed the configuration after the observed delay.
    let ops = dev.ops();
    let write = ops
        .iter()
        .find(|op| op.kind == OpKind::Set && op.report_id == CTRL_REPORT_ID)
        .unwrap();
    let save = ops
        .iter()
        .find(|op| op.kind == OpKind::Set && op.report_id == SECONDARY_REPORT_ID)
        .unwrap();
    assert!(save.at - write.at >= Duration::from_millis(4100));
    assert_eq!(
        dev.secondary_reports(),
        &[vec![0x06, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00]]
    );

    // The device now holds the plan, apart from the clock bytes it never keeps.
    let held = dev.config();
    assert_eq!(&held.as_slice()[7..], &plan.intended.as_slice()[7..]);
}

#[test]
fn a_second_apply_writes_nothing() {
    let backups = tempfile::tempdir().unwrap();
    let mut dev = device(fixture("after-reflash.bin"));
    apply_desired(&mut dev, &desired(), false, backups.path(), now()).unwrap();
    let writes = dev.writes_applied();
    let backups_after_first = files_in(backups.path());

    let again = apply_desired(&mut dev, &desired(), false, backups.path(), now()).unwrap();

    assert!(matches!(again, Outcome::AlreadyApplied { .. }));
    assert_eq!(dev.writes_applied(), writes);
    assert_eq!(files_in(backups.path()), backups_after_first);
}

#[test]
fn a_configuration_version_with_no_profile_is_refused_before_anything_else() {
    let backups = tempfile::tempdir().unwrap();
    let mut bytes = fixture("after-reflash.bin").as_slice().to_vec();
    bytes[2] = 0xb1; // data version 1201
    let mut dev = device(ConfigBytes::new(bytes).unwrap());

    let err = apply_desired(&mut dev, &desired(), false, backups.path(), now()).unwrap_err();

    assert!(
        matches!(
            err,
            WorkflowError::NoProfile {
                source: ProfileError::UnknownVersion { version: 1201, .. }
            }
        ),
        "{err:?}"
    );
    assert_eq!(dev.writes_applied(), 0);
    assert_eq!(files_in(backups.path()), 0);
}

#[test]
fn an_invalid_curve_is_refused_after_reads_only() {
    let backups = tempfile::tempdir().unwrap();
    let mut dev = device(fixture("after-reflash.bin"));
    let mut curve = desired();
    curve.points.truncate(1);

    let err = apply_desired(&mut dev, &curve, false, backups.path(), now()).unwrap_err();

    assert!(
        matches!(
            err,
            WorkflowError::Plan {
                source: PlanError::Curve {
                    source: CurveError::TooFewPoints { count: 1 }
                }
            }
        ),
        "{err:?}"
    );
    assert!(dev.ops().iter().all(|op| op.kind == OpKind::Get));
    assert_eq!(files_in(backups.path()), 0);
}

#[test]
fn a_rejected_write_names_the_backup_and_how_to_restore_it() {
    let backups = tempfile::tempdir().unwrap();
    let mut dev = device(fixture("after-reflash.bin"));
    dev.inject(Fault::RejectNextWrite);

    let err = apply_desired(&mut dev, &desired(), false, backups.path(), now()).unwrap_err();

    match &err {
        WorkflowError::Apply {
            source: ApplyError::Write { backup, .. },
        } => assert!(backup.bin.exists()),
        other => panic!("{other:?}"),
    }
    let text = format!("{}", std::error::Error::source(&err).unwrap());
    assert!(text.contains("restore"), "{text}");
}

#[test]
fn planning_alone_reads_only_and_saves_nothing() {
    let mut dev = device(fixture("after-reflash.bin"));

    let (profile, plan) = plan_for_device(&mut dev, &desired()).unwrap();

    assert_eq!(profile.data_version(), 1200);
    assert!(!plan.changes.is_empty());
    assert!(dev.ops().iter().all(|op| op.kind == OpKind::Get));
}
