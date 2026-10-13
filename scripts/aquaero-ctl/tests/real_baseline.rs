// Panicking on a bad fixture is the correct failure inside a test.
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects,
    clippy::panic
)]

//! Facts about the real device's stored configuration, pinned against a dump
//! taken from it on 2026-10-13 (the original Windows-made configuration, read
//! over hidraw with nothing written). Each assertion is something observed,
//! not something assumed from the kernel driver.

use aquaero_ctl::hid::CTRL_REPORT_ID;
use aquaero_ctl::identity::data_version;
use aquaero_ctl::snapshot::{ConfigBytes, CONFIG_LEN};

const FAN_STRUCT_BASE: usize = 0x20c;
const FAN_STRUCT_STRIDE: usize = 0x14;

fn fixture(name: &str) -> ConfigBytes {
    let path = format!("{}/tests/fixtures/{name}", env!("CARGO_MANIFEST_DIR"));
    ConfigBytes::new(std::fs::read(path).unwrap()).unwrap()
}

/// The original Windows-made configuration, read before the firmware was
/// reflashed.
fn baseline() -> ConfigBytes {
    fixture("before-reflash.bin")
}

/// Read after Aquasuite reflashed firmware 2104 over 2104 and restarted.
fn after_reflash() -> ConfigBytes {
    fixture("after-reflash.bin")
}

fn fan_struct(config: &ConfigBytes, channel: usize) -> &[u8] {
    let start = FAN_STRUCT_BASE + (channel - 1) * FAN_STRUCT_STRIDE;
    &config.as_slice()[start..start + FAN_STRUCT_STRIDE]
}

#[test]
fn the_report_is_the_expected_length_and_starts_with_its_id() {
    let config = baseline();
    assert_eq!(config.as_slice().len(), CONFIG_LEN);
    assert_eq!(config.as_slice()[0], CTRL_REPORT_ID);
}

#[test]
fn the_data_version_matches_the_one_the_vendor_library_expects() {
    assert_eq!(data_version(&baseline()), 1200);
}

#[test]
fn the_serial_is_not_stored_where_the_kernel_driver_looks() {
    // Bytes 7..11 are zero on the real device; the serial comes from USB.
    assert_eq!(&baseline().as_slice()[7..11], &[0, 0, 0, 0]);
}

#[test]
fn fan_structs_sit_at_the_kernel_drivers_offsets_with_fan_four_set_apart() {
    let config = baseline();
    // Channels 1 to 3 are left at their defaults and are identical; channel 4
    // (the radiator fans) was configured, so its struct differs.
    assert_eq!(fan_struct(&config, 1), fan_struct(&config, 2));
    assert_eq!(fan_struct(&config, 2), fan_struct(&config, 3));
    assert_ne!(fan_struct(&config, 3), fan_struct(&config, 4));
}

#[test]
fn the_reflash_rewrote_the_configuration_but_not_its_header() {
    let before = baseline();
    let after = after_reflash();

    let runs = aquaero_ctl::diff::diff(&before, &after, &aquaero_ctl::diff::VolatileSet::none());

    assert_eq!(runs.len(), 29);
    assert_eq!(runs.iter().map(|r| r.before.len()).sum::<usize>(), 106);
    assert_eq!(data_version(&after), 1200);
    assert_eq!(&before.as_slice()[..3], &after.as_slice()[..3]);
}

#[test]
fn after_the_reflash_all_four_fans_hold_the_same_defaults() {
    let config = after_reflash();
    // The radiator fans' own settings are gone: channel 4 now matches 1 to 3.
    assert_eq!(fan_struct(&config, 1), fan_struct(&config, 4));
    assert_eq!(fan_struct(&config, 2), fan_struct(&config, 4));
    assert_eq!(fan_struct(&config, 3), fan_struct(&config, 4));
}
