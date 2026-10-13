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

use aquaero_ctl::error::HidError;
use aquaero_ctl::fake::{FakeDevice, Fault, ManualClock};
use aquaero_ctl::hid::{
    read_config, Clock, HidDevice, CONTROL_GAP, CTRL_REPORT_ID, SECONDARY_REPORT_ID,
    SECONDARY_REPORT_LEN,
};
use aquaero_ctl::snapshot::{ConfigBytes, CONFIG_LEN};

fn config(fill: u8) -> ConfigBytes {
    let mut bytes = vec![fill; CONFIG_LEN];
    bytes[0] = CTRL_REPORT_ID;
    ConfigBytes::new(bytes).unwrap()
}

fn device(fill: u8) -> (FakeDevice, Arc<ManualClock>) {
    let clock = Arc::new(ManualClock::new());
    (FakeDevice::new(config(fill), Arc::clone(&clock)), clock)
}

#[test]
fn the_report_constants_match_the_kernel_driver() {
    assert_eq!(CTRL_REPORT_ID, 0x0b);
    assert_eq!(SECONDARY_REPORT_ID, 0x06);
    assert_eq!(SECONDARY_REPORT_LEN, 7);
    assert_eq!(CONTROL_GAP, Duration::from_millis(200));
}

#[test]
fn reading_returns_the_stored_configuration() {
    let (mut dev, _) = device(0x11);
    assert_eq!(read_config(&mut dev).unwrap(), config(0x11));
}

#[test]
fn a_write_is_visible_to_the_next_read() {
    let (mut dev, _) = device(0x11);
    dev.set_feature(config(0x22).as_slice()).unwrap();

    assert_eq!(read_config(&mut dev).unwrap(), config(0x22));
    assert_eq!(dev.writes_applied(), 1);
}

#[test]
fn a_write_of_the_wrong_length_is_refused_and_changes_nothing() {
    let (mut dev, _) = device(0x11);
    let err = dev.set_feature(&[CTRL_REPORT_ID, 1, 2, 3]).unwrap_err();

    assert!(matches!(err, HidError::SetFeature { .. }), "{err:?}");
    assert_eq!(dev.config(), config(0x11));
    assert_eq!(dev.writes_applied(), 0);
}

#[test]
fn an_unknown_report_cannot_be_read() {
    let (mut dev, _) = device(0x11);
    let err = dev.get_feature(0x01, 16).unwrap_err();
    assert!(
        matches!(
            err,
            HidError::GetFeature {
                report_id: 0x01,
                ..
            }
        ),
        "{err:?}"
    );
}

#[test]
fn the_secondary_report_is_recorded_and_leaves_the_configuration_alone() {
    let (mut dev, _) = device(0x11);
    let mut report = vec![0u8; SECONDARY_REPORT_LEN];
    report[0] = SECONDARY_REPORT_ID;
    report[3] = 0x7f;

    dev.set_feature(&report).unwrap();

    assert_eq!(dev.secondary_reports(), &[report]);
    assert_eq!(dev.config(), config(0x11));
    assert_eq!(dev.writes_applied(), 0);
}

#[test]
fn a_configuration_without_the_report_id_byte_is_rejected_on_read() {
    let clock = Arc::new(ManualClock::new());
    let mut bytes = vec![0x55u8; CONFIG_LEN];
    bytes[0] = 0x99;
    let mut dev = FakeDevice::new(ConfigBytes::new(bytes).unwrap(), clock);

    let err = read_config(&mut dev).unwrap_err();
    assert!(
        matches!(
            err,
            HidError::UnexpectedReportId {
                expected: 0x0b,
                got: 0x99,
                ..
            }
        ),
        "{err:?}"
    );
}

#[test]
fn a_short_read_is_reported_with_both_lengths() {
    let (mut dev, _) = device(0x11);
    dev.inject(Fault::ShortReadNext { bytes: 100 });

    let err = read_config(&mut dev).unwrap_err();
    assert!(
        matches!(err, HidError::ShortRead { expected, got: 100, .. } if expected == CONFIG_LEN),
        "{err:?}"
    );
    // The fault applies once.
    assert_eq!(read_config(&mut dev).unwrap(), config(0x11));
}

#[test]
fn a_rejected_write_changes_nothing_and_applies_once() {
    let (mut dev, _) = device(0x11);
    dev.inject(Fault::RejectNextWrite);

    let err = dev.set_feature(config(0x22).as_slice()).unwrap_err();
    assert!(matches!(err, HidError::SetFeature { .. }), "{err:?}");
    assert_eq!(dev.config(), config(0x11));
    assert_eq!(dev.writes_applied(), 0);

    dev.set_feature(config(0x22).as_slice()).unwrap();
    assert_eq!(dev.config(), config(0x22));
}

#[test]
fn a_disconnect_fails_every_operation_after_the_allowed_ones() {
    let (mut dev, _) = device(0x11);
    dev.inject(Fault::DisconnectAfter { ops: 2 });

    read_config(&mut dev).unwrap();
    dev.set_feature(config(0x22).as_slice()).unwrap();

    for _ in 0..3 {
        let err = read_config(&mut dev).unwrap_err();
        assert!(matches!(err, HidError::Disconnected { .. }), "{err:?}");
    }
    let err = dev.set_feature(config(0x33).as_slice()).unwrap_err();
    assert!(matches!(err, HidError::Disconnected { .. }), "{err:?}");
    assert_eq!(dev.config(), config(0x22));
}

#[test]
fn a_write_the_device_alters_shows_up_as_a_different_read_back() {
    let (mut dev, _) = device(0x11);
    dev.inject(Fault::DriftAfterNextWrite { offset: 200 });

    dev.set_feature(config(0x22).as_slice()).unwrap();
    let read_back = read_config(&mut dev).unwrap();

    assert_ne!(read_back, config(0x22));
    assert_eq!(read_back.as_slice()[200], 0x22 ^ 0xff);
    assert_eq!(read_back.as_slice()[199], 0x22);
}

#[test]
fn operations_are_timestamped_from_the_injected_clock() {
    let (mut dev, clock) = device(0x11);

    read_config(&mut dev).unwrap();
    clock.sleep(CONTROL_GAP);
    dev.set_feature(config(0x22).as_slice()).unwrap();
    clock.sleep(Duration::from_millis(350));
    read_config(&mut dev).unwrap();

    assert_eq!(
        dev.observed_gaps(),
        vec![Duration::from_millis(200), Duration::from_millis(350)]
    );
}

#[test]
fn back_to_back_operations_show_a_zero_gap() {
    let (mut dev, _) = device(0x11);
    read_config(&mut dev).unwrap();
    read_config(&mut dev).unwrap();
    assert_eq!(dev.observed_gaps(), vec![Duration::ZERO]);
}

#[test]
fn the_manual_clock_only_moves_when_told() {
    let clock = ManualClock::new();
    let start = clock.now();
    assert_eq!(clock.now(), start);
    clock.sleep(Duration::from_millis(5));
    assert_eq!(clock.now(), start + Duration::from_millis(5));
}
