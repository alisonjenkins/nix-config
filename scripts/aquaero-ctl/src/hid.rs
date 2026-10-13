//! The device boundary: what the tool needs from a HID device, the report
//! constants, and the clock that spaces control operations.

use std::path::Path;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use crate::error::HidError;
use crate::snapshot::{ConfigBytes, CONFIG_LEN};

/// Aqua Computer's USB vendor id.
pub const VENDOR_ID: u16 = 0x0c70;
/// The aquaero's USB product id.
pub const PRODUCT_ID: u16 = 0xf001;

/// Feature report holding the whole stored configuration. The report is
/// [`CONFIG_LEN`] bytes including this id as its first byte.
pub const CTRL_REPORT_ID: u8 = 0x0b;
/// Short feature report the kernel driver sends after every configuration write.
pub const SECONDARY_REPORT_ID: u8 = 0x06;
pub const SECONDARY_REPORT_LEN: usize = 7;

/// Minimum spacing between control operations. The kernel driver enforces the
/// same 200 ms (`CTRL_REPORT_DELAY`), which suggests the device needs it.
pub const CONTROL_GAP: Duration = Duration::from_millis(200);

/// A device that exchanges HID feature reports. Reports include their id byte.
pub trait HidDevice {
    fn path(&self) -> &Path;

    /// The serial the device reports over USB, `NNNNN-NNNNN`. It is not part
    /// of the stored configuration.
    fn serial(&self) -> String;

    /// Reads feature report `report_id`; the result starts with that id.
    fn get_feature(&mut self, report_id: u8, len: usize) -> Result<Vec<u8>, HidError>;

    /// Writes one feature report; `report[0]` is its id.
    fn set_feature(&mut self, report: &[u8]) -> Result<(), HidError>;
}

/// Reads the stored configuration, checking its length and report id.
pub fn read_config(device: &mut dyn HidDevice) -> Result<ConfigBytes, HidError> {
    let raw = device.get_feature(CTRL_REPORT_ID, CONFIG_LEN)?;
    if raw.len() != CONFIG_LEN {
        return Err(HidError::ShortRead {
            path: device.path().to_path_buf(),
            report_id: CTRL_REPORT_ID,
            expected: CONFIG_LEN,
            got: raw.len(),
        });
    }
    if let Some(&got) = raw.first() {
        if got != CTRL_REPORT_ID {
            return Err(HidError::UnexpectedReportId {
                path: device.path().to_path_buf(),
                expected: CTRL_REPORT_ID,
                got,
            });
        }
    }
    ConfigBytes::new(raw).map_err(|source| HidError::InvalidConfig {
        path: device.path().to_path_buf(),
        source,
    })
}

/// Time as the tool sees it, so tests can supply their own.
pub trait Clock {
    /// Time since an arbitrary fixed origin; only differences mean anything.
    fn now(&self) -> Duration;

    fn sleep(&self, duration: Duration);
}

impl<C: Clock + ?Sized> Clock for Arc<C> {
    fn now(&self) -> Duration {
        (**self).now()
    }

    fn sleep(&self, duration: Duration) {
        (**self).sleep(duration);
    }
}

/// The real clock. Its origin is the Unix epoch, so times recorded by one run
/// of the tool mean the same thing to the next.
#[derive(Debug, Clone, Copy, Default)]
pub struct SystemClock;

impl SystemClock {
    pub fn new() -> Self {
        Self
    }
}

impl Clock for SystemClock {
    /// A clock set before 1970 reads as the epoch.
    fn now(&self) -> Duration {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or(Duration::ZERO)
    }

    fn sleep(&self, duration: Duration) {
        std::thread::sleep(duration);
    }
}
