// Shared fixtures for the apply, failure and restore tests.
#![allow(
    dead_code,
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects,
    clippy::panic
)]

use std::sync::Arc;

use aquaero_ctl::fake::{FakeDevice, ManualClock};
use aquaero_ctl::hid::CTRL_REPORT_ID;
use aquaero_ctl::identity::DATA_VERSION_OFFSET;
use aquaero_ctl::snapshot::{ConfigBytes, CONFIG_LEN};

pub const SERIAL: &str = "12345-54321";
pub const FIRMWARE: u32 = 1036;

/// A configuration filled with `fill`, with the data version set.
pub fn config(fill: u8) -> ConfigBytes {
    config_with(fill, &[])
}

/// Like [`config`], then each `(offset, value)` overridden.
pub fn config_with(fill: u8, changes: &[(usize, u8)]) -> ConfigBytes {
    let mut bytes = vec![fill; CONFIG_LEN];
    bytes[0] = CTRL_REPORT_ID;
    bytes[DATA_VERSION_OFFSET..DATA_VERSION_OFFSET + 2]
        .copy_from_slice(&(FIRMWARE as u16).to_be_bytes());
    for &(offset, value) in changes {
        bytes[offset] = value;
    }
    ConfigBytes::new(bytes).unwrap()
}

pub fn device_holding(config: ConfigBytes) -> (FakeDevice, Arc<ManualClock>) {
    let clock = Arc::new(ManualClock::new());
    (
        FakeDevice::new(config, Arc::clone(&clock)).with_serial(SERIAL),
        clock,
    )
}
