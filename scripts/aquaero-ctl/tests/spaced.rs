// Panicking on a bad fixture is the correct failure inside a test.
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects,
    clippy::panic
)]

use std::sync::Arc;
use std::time::Duration;

use aquaero_ctl::fake::{FakeDevice, ManualClock};
use aquaero_ctl::hid::{read_config, HidDevice, CONTROL_GAP, CTRL_REPORT_ID};
use aquaero_ctl::lock::{DeviceLock, SpacedDevice};
use aquaero_ctl::snapshot::{ConfigBytes, CONFIG_LEN};

fn config(fill: u8) -> ConfigBytes {
    let mut bytes = vec![fill; CONFIG_LEN];
    bytes[0] = CTRL_REPORT_ID;
    ConfigBytes::new(bytes).unwrap()
}

#[test]
fn consecutive_operations_are_at_least_one_gap_apart() {
    let dir = tempfile::tempdir().unwrap();
    let mut lock = DeviceLock::acquire(&dir.path().join("l")).unwrap();
    let clock = Arc::new(ManualClock::new());
    let fake = FakeDevice::new(config(1), Arc::clone(&clock));

    let mut spaced = SpacedDevice::new(fake, &mut lock, &clock);
    read_config(&mut spaced).unwrap();
    spaced.set_feature(config(2).as_slice()).unwrap();
    read_config(&mut spaced).unwrap();

    let gaps = spaced.into_inner().observed_gaps();
    assert_eq!(gaps, vec![CONTROL_GAP, CONTROL_GAP]);
}

#[test]
fn the_first_operation_is_not_delayed() {
    let dir = tempfile::tempdir().unwrap();
    let mut lock = DeviceLock::acquire(&dir.path().join("l")).unwrap();
    let clock = Arc::new(ManualClock::new());
    let fake = FakeDevice::new(config(1), Arc::clone(&clock));

    let mut spaced = SpacedDevice::new(fake, &mut lock, &clock);
    read_config(&mut spaced).unwrap();

    assert_eq!(spaced.into_inner().ops()[0].at, Duration::ZERO);
}

#[test]
fn the_wrapper_passes_reads_and_writes_through() {
    let dir = tempfile::tempdir().unwrap();
    let mut lock = DeviceLock::acquire(&dir.path().join("l")).unwrap();
    let clock = Arc::new(ManualClock::new());
    let fake = FakeDevice::new(config(1), Arc::clone(&clock));

    let mut spaced = SpacedDevice::new(fake, &mut lock, &clock);
    spaced.set_feature(config(9).as_slice()).unwrap();

    assert_eq!(read_config(&mut spaced).unwrap(), config(9));
    assert_eq!(spaced.path(), std::path::Path::new("/dev/fake-hidraw0"));
}
