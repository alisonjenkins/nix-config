// Panicking on a bad fixture is the correct failure inside a test.
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects,
    clippy::panic
)]

use std::sync::Arc;

use aquaero_ctl::dump::{dump, DumpOptions};
use aquaero_ctl::error::{DumpError, HidError, SnapshotError};
use aquaero_ctl::fake::{FakeDevice, Fault, ManualClock, OpKind};
use aquaero_ctl::hid::CTRL_REPORT_ID;
use aquaero_ctl::identity::{firmware, serial, FIRMWARE_OFFSET, SERIAL_OFFSET};
use aquaero_ctl::snapshot::{ConfigBytes, ConfigSnapshot, CONFIG_LEN};
use aquaero_ctl::timestamp::UtcTimestamp;

/// A configuration whose serial is 12345-54321 and firmware 1036.
fn config() -> ConfigBytes {
    let mut bytes: Vec<u8> = (0..CONFIG_LEN).map(|i| (i % 251) as u8 | 1).collect();
    bytes[0] = CTRL_REPORT_ID;
    bytes[SERIAL_OFFSET..SERIAL_OFFSET + 2].copy_from_slice(&12345u16.to_be_bytes());
    bytes[SERIAL_OFFSET + 2..SERIAL_OFFSET + 4].copy_from_slice(&54321u16.to_be_bytes());
    bytes[FIRMWARE_OFFSET..FIRMWARE_OFFSET + 2].copy_from_slice(&1036u16.to_be_bytes());
    ConfigBytes::new(bytes).unwrap()
}

fn device() -> FakeDevice {
    FakeDevice::new(config(), Arc::new(ManualClock::new()))
}

fn options(dir: &std::path::Path) -> DumpOptions {
    DumpOptions {
        out_dir: dir.to_path_buf(),
        label: "Baseline".to_string(),
        redact_serial: false,
    }
}

#[test]
fn the_serial_is_two_zero_padded_numbers() {
    assert_eq!(serial(&config()), "12345-54321");

    let mut bytes = vec![0u8; CONFIG_LEN];
    bytes[SERIAL_OFFSET + 1] = 7;
    bytes[SERIAL_OFFSET + 3] = 42;
    assert_eq!(serial(&ConfigBytes::new(bytes).unwrap()), "00007-00042");
}

#[test]
fn the_firmware_is_a_big_endian_number() {
    assert_eq!(firmware(&config()), 1036);
}

#[test]
fn a_dump_reads_back_as_the_device_configuration() {
    let dir = tempfile::tempdir().unwrap();
    let mut dev = device();
    let now = UtcTimestamp::from_unix(1_700_000_000);

    let paths = dump(&mut dev, &options(dir.path()), now).unwrap();
    let snap = ConfigSnapshot::read(&paths.bin).unwrap();

    assert_eq!(snap.bytes(), &config());
    assert_eq!(snap.meta().serial, "12345-54321");
    assert_eq!(snap.meta().firmware, 1036);
    assert_eq!(snap.meta().taken_at, "2023-11-14T22:13:20Z");
    assert_eq!(snap.meta().label, "baseline");
}

#[test]
fn a_dump_never_writes_to_the_device() {
    let dir = tempfile::tempdir().unwrap();
    let mut dev = device();

    dump(&mut dev, &options(dir.path()), UtcTimestamp::from_unix(0)).unwrap();

    assert_eq!(dev.writes_applied(), 0);
    assert!(dev.ops().iter().all(|op| op.kind == OpKind::Get));
    assert_eq!(dev.config(), config());
}

#[test]
fn redacting_hides_the_serial_in_both_the_metadata_and_the_bytes() {
    let dir = tempfile::tempdir().unwrap();
    let mut dev = device();
    let mut opts = options(dir.path());
    opts.redact_serial = true;

    let paths = dump(&mut dev, &opts, UtcTimestamp::from_unix(0)).unwrap();
    let snap = ConfigSnapshot::read(&paths.bin).unwrap();

    assert_eq!(snap.meta().serial, "REDACTED");
    assert_eq!(
        &snap.bytes().as_slice()[SERIAL_OFFSET..SERIAL_OFFSET + 4],
        &[0, 0, 0, 0]
    );

    // Everything else is untouched, so the redacted file still diffs cleanly.
    let original = config();
    assert_eq!(
        &snap.bytes().as_slice()[..SERIAL_OFFSET],
        &original.as_slice()[..SERIAL_OFFSET]
    );
    assert_eq!(
        &snap.bytes().as_slice()[SERIAL_OFFSET + 4..],
        &original.as_slice()[SERIAL_OFFSET + 4..]
    );
}

#[test]
fn a_failed_read_writes_no_files_and_names_the_failure() {
    let dir = tempfile::tempdir().unwrap();
    let mut dev = device();
    dev.inject(Fault::ShortReadNext { bytes: 50 });

    let err = dump(&mut dev, &options(dir.path()), UtcTimestamp::from_unix(0)).unwrap_err();

    assert!(
        matches!(
            &err,
            DumpError::Read {
                source: HidError::ShortRead { got: 50, .. }
            }
        ),
        "{err:?}"
    );
    assert_eq!(std::fs::read_dir(dir.path()).unwrap().count(), 0);
}

#[test]
fn a_dump_never_overwrites_an_existing_snapshot() {
    let dir = tempfile::tempdir().unwrap();
    let now = UtcTimestamp::from_unix(1_700_000_000);
    dump(&mut device(), &options(dir.path()), now).unwrap();

    let err = dump(&mut device(), &options(dir.path()), now).unwrap_err();
    assert!(
        matches!(
            &err,
            DumpError::Save {
                source: SnapshotError::Write { .. }
            }
        ),
        "{err:?}"
    );
}
