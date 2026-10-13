//! Who the device says it is, read from its configuration report.
//!
//! The offsets are the kernel driver's (`aquacomputer_d5next`). They are
//! unverified for this firmware until the hardware tasks confirm them; if one
//! is wrong the firmware reads as unknown and nothing is written.

use crate::snapshot::ConfigBytes;

/// The serial is two big-endian 16-bit numbers at 0x07 and 0x09, shown as
/// `NNNNN-NNNNN` (the vendor's installer shows the same form).
pub const SERIAL_OFFSET: usize = 0x07;

/// The firmware version is a big-endian 16-bit number at 0x0b.
pub const FIRMWARE_OFFSET: usize = 0x0b;

/// `12345-54321`.
pub fn serial(config: &ConfigBytes) -> String {
    let first = be16(config, SERIAL_OFFSET);
    let second = be16(config, SERIAL_OFFSET.saturating_add(2));
    format!("{first:05}-{second:05}")
}

pub fn firmware(config: &ConfigBytes) -> u32 {
    u32::from(be16(config, FIRMWARE_OFFSET))
}

fn be16(config: &ConfigBytes, offset: usize) -> u16 {
    let bytes = config.as_slice();
    let at = |i: usize| bytes.get(i).copied().unwrap_or(0);
    u16::from_be_bytes([at(offset), at(offset.saturating_add(1))])
}
