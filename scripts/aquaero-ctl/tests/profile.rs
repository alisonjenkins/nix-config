// Panicking on a bad fixture is the correct failure inside a test.
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects,
    clippy::panic
)]

//! The firmware profile, checked against dumps of the real device.

use std::time::Duration;

use aquaero_ctl::error::ProfileError;
use aquaero_ctl::profile::{Profile, NO_SOURCE};
use aquaero_ctl::snapshot::ConfigBytes;

fn fixture(name: &str) -> ConfigBytes {
    let path = format!("{}/tests/fixtures/{name}", env!("CARGO_MANIFEST_DIR"));
    ConfigBytes::new(std::fs::read(path).unwrap()).unwrap()
}

fn profile() -> Profile {
    Profile::for_data_version(1200).unwrap()
}

#[test]
fn the_known_versions_are_listed() {
    assert_eq!(Profile::known_versions(), vec![1200]);
}

#[test]
fn an_unknown_version_is_refused_and_the_known_ones_named() {
    let err = Profile::for_data_version(1300).unwrap_err();
    match err {
        ProfileError::UnknownVersion { version, known } => {
            assert_eq!(version, 1300);
            assert_eq!(known, vec![1200]);
        }
        other => panic!("{other:?}"),
    }
}

#[test]
fn the_profile_says_which_firmware_it_was_verified_on() {
    let p = profile();
    assert_eq!(p.data_version(), 1200);
    assert_eq!(p.firmware(), 2104);
    assert!(!p.verified_on().is_empty());
}

#[test]
fn fan_four_settings_before_the_reflash() {
    let fan = profile()
        .fan_settings(&fixture("before-reflash.bin"), 4)
        .unwrap();
    // The radiators were driven by Preset value 4 (source 0x5f).
    assert_eq!(fan.source, 0x005f);
    assert_eq!(fan.min_hundredths, 0);
    assert_eq!(fan.max_hundredths, 10_000);
}

#[test]
fn fan_four_settings_after_the_reflash() {
    let fan = profile()
        .fan_settings(&fixture("after-reflash.bin"), 4)
        .unwrap();
    // Factory defaults: Preset fan (0x5c), 35 % to 100 %.
    assert_eq!(fan.source, 0x005c);
    assert_eq!(fan.min_hundredths, 3_500);
    assert_eq!(fan.max_hundredths, 10_000);
}

#[test]
fn a_fan_that_does_not_exist_is_refused() {
    let p = profile();
    let config = fixture("after-reflash.bin");
    assert!(matches!(
        p.fan_settings(&config, 0),
        Err(ProfileError::NoSuchFan { fan: 0, .. })
    ));
    assert!(matches!(
        p.fan_settings(&config, 5),
        Err(ProfileError::NoSuchFan { fan: 5, .. })
    ));
}

#[test]
fn the_default_curve_controller_has_sixteen_points_and_no_source() {
    let curve = profile()
        .curve_settings(&fixture("after-reflash.bin"), 1)
        .unwrap();
    assert_eq!(curve.source, NO_SOURCE);
    assert_eq!(curve.start_hundredths, 3_000);
    assert_eq!(curve.temperatures_hundredths.len(), 16);
    assert_eq!(curve.outputs_hundredths.len(), 16);
    assert_eq!(curve.temperatures_hundredths[0], 2_700);
    assert_eq!(curve.temperatures_hundredths[15], 4_000);
    assert_eq!(curve.outputs_hundredths[0], 0);
    assert_eq!(curve.outputs_hundredths[15], 10_000);
}

#[test]
fn a_curve_controller_set_up_in_aquasuite_decodes_as_it_was_entered() {
    // Sensor 1, startup 31.7 °C, third point's output 3.6 %.
    let curve = profile()
        .curve_settings(&fixture("curve-controller-1.bin"), 1)
        .unwrap();
    assert_eq!(curve.source, 0);
    assert_eq!(curve.start_hundredths, 3_170);
    assert_eq!(curve.outputs_hundredths[2], 360);
}

#[test]
fn only_the_four_curve_slots_exist() {
    let p = profile();
    let config = fixture("after-reflash.bin");
    assert!(p.curve_settings(&config, 4).is_ok());
    assert!(matches!(
        p.curve_settings(&config, 0),
        Err(ProfileError::NoSuchCurve { slot: 0, .. })
    ));
    assert!(matches!(
        p.curve_settings(&config, 5),
        Err(ProfileError::NoSuchCurve { slot: 5, .. })
    ));
}

#[test]
fn source_numbers_follow_the_vendor_numbering() {
    let p = profile();
    assert_eq!(p.sensor_source(1).unwrap(), 0);
    assert_eq!(p.sensor_source(2).unwrap(), 1);
    assert_eq!(p.curve_source(1).unwrap(), 0x58);
    assert_eq!(p.curve_source(4).unwrap(), 0x5b);
    assert!(p.curve_source(5).is_err());
}

#[test]
fn the_save_command_follows_the_write_after_the_observed_delay() {
    let reports = profile().commit_reports();
    assert_eq!(reports.len(), 1);
    assert_eq!(
        reports[0].bytes,
        vec![0x06, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00]
    );
    assert_eq!(reports[0].delay_before, Duration::from_millis(4100));
}

#[test]
fn a_profile_with_an_unknown_field_is_rejected() {
    let text = "data_version = 1\nfirmware = 1\nverified_on = []\nsurprise = true\n";
    assert!(matches!(
        Profile::from_toml(text),
        Err(ProfileError::Parse { .. })
    ));
}
