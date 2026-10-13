//! What the stored configuration says about itself.
//!
//! The report starts `0b 04 b0`: after the report id comes a big-endian 16-bit
//! number, 1200 on the one device read so far. That matches the data version
//! the vendor library expects, so it is the version a firmware profile is
//! keyed on. The serial is not in the report; it comes from the device node
//! (`HidDevice::serial`). The firmware's own version number has not been
//! located yet.

use crate::snapshot::ConfigBytes;

/// Bytes 3 to 6 of a written configuration hold a host clock (a big-endian
/// seconds counter). The device never keeps them: it reads zeros there, even
/// right after Aquasuite wrote a counter. They are not part of the settings.
pub const CLOCK_OFFSET: usize = 3;
pub const CLOCK_LEN: usize = 4;

/// Offset of the big-endian 16-bit data version.
pub const DATA_VERSION_OFFSET: usize = 0x01;

/// The configuration data version, or 0 if the report is too short.
pub fn data_version(config: &ConfigBytes) -> u32 {
    let bytes = config.as_slice();
    let at = |i: usize| bytes.get(i).copied().unwrap_or(0);
    u32::from(u16::from_be_bytes([
        at(DATA_VERSION_OFFSET),
        at(DATA_VERSION_OFFSET.saturating_add(1)),
    ]))
}
