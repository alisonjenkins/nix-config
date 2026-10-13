//! The real device: a `/dev/hidrawN` node driven with the `HIDIOCGFEATURE`
//! and `HIDIOCSFEATURE` ioctls. It works alongside the kernel driver, which
//! binds the same HID device.

use std::fs::{File, OpenOptions};
use std::io;
use std::os::fd::AsRawFd;
use std::path::{Path, PathBuf};

use nix::errno::Errno;

use crate::error::HidError;
use crate::hid::HidDevice;

mod sys {
    // The size in these request numbers is the buffer length, so each call
    // builds its request from the slice it passes.
    nix::ioctl_readwrite_buf!(hidiocgfeature, b'H', 0x07, u8);
    nix::ioctl_readwrite_buf!(hidiocsfeature, b'H', 0x06, u8);
}

#[derive(Debug)]
pub struct HidrawDevice {
    file: File,
    path: PathBuf,
    serial: String,
}

impl HidrawDevice {
    pub fn open(path: &Path) -> Result<Self, HidError> {
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .open(path)
            .map_err(|source| HidError::Open {
                path: path.to_path_buf(),
                source,
            })?;
        Ok(Self {
            file,
            path: path.to_path_buf(),
            serial: UNKNOWN_SERIAL.to_string(),
        })
    }

    /// Records the serial found when the node was discovered.
    #[must_use]
    pub fn with_serial(mut self, serial: &str) -> Self {
        self.serial = serial.to_string();
        self
    }

    fn errno_to_error(&self, errno: Errno, operation: &'static str) -> Result<io::Error, HidError> {
        // ENODEV is what a hidraw node returns once the device is unplugged.
        if errno == Errno::ENODEV {
            return Err(HidError::Disconnected {
                path: self.path.clone(),
                operation,
            });
        }
        Ok(io::Error::from(errno))
    }
}

/// What `serial()` reports when the node was opened without discovery.
pub const UNKNOWN_SERIAL: &str = "unknown";

impl HidDevice for HidrawDevice {
    fn path(&self) -> &Path {
        &self.path
    }

    fn serial(&self) -> String {
        self.serial.clone()
    }

    fn get_feature(&mut self, report_id: u8, len: usize) -> Result<Vec<u8>, HidError> {
        let mut buffer = vec![0u8; len];
        if let Some(first) = buffer.first_mut() {
            *first = report_id;
        }
        // SAFETY: the file descriptor is open for the lifetime of `self`, and
        // the ioctl only writes within `buffer`, whose length is encoded in
        // the request.
        let result = unsafe { sys::hidiocgfeature(self.file.as_raw_fd(), &mut buffer) };
        match result {
            Ok(read) => {
                buffer.truncate(usize::try_from(read).unwrap_or(0));
                Ok(buffer)
            }
            Err(errno) => Err(HidError::GetFeature {
                path: self.path.clone(),
                report_id,
                source: self.errno_to_error(errno, "get_feature")?,
            }),
        }
    }

    fn set_feature(&mut self, report: &[u8]) -> Result<(), HidError> {
        let report_id = report.first().copied().unwrap_or(0);
        // The ioctl takes a mutable buffer even for a write.
        let mut buffer = report.to_vec();
        // SAFETY: as in `get_feature`; the ioctl reads within `buffer`.
        let result = unsafe { sys::hidiocsfeature(self.file.as_raw_fd(), &mut buffer) };
        match result {
            Ok(_) => Ok(()),
            Err(errno) => Err(HidError::SetFeature {
                path: self.path.clone(),
                report_id,
                len: report.len(),
                source: self.errno_to_error(errno, "set_feature")?,
            }),
        }
    }
}
