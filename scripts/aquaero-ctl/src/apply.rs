//! Writing a whole configuration to the device, and putting one back.
//!
//! Every write follows the same steps: read what is there, save it as a
//! backup, write, send any commit reports, read back and compare. No backup
//! means no write, and a write that cannot be confirmed says where the backup
//! is and how to restore it.

use std::path::PathBuf;

use crate::diff::{diff, DiffRun, VolatileSet};
use crate::error::{ApplyError, RestoreError};
use crate::hid::{read_config, HidDevice, CTRL_REPORT_ID};
use crate::identity;
use crate::snapshot::{ConfigBytes, ConfigSnapshot, SnapshotPaths};
use crate::timestamp::UtcTimestamp;

const APPLY_LABEL: &str = "pre-apply";
const RESTORE_LABEL: &str = "pre-restore";

#[derive(Debug, Clone)]
pub struct ApplyOptions {
    /// Where the backup of the previous configuration is saved.
    pub backup_dir: PathBuf,
    /// Reports sent after the configuration write, in order. What the device
    /// needs to keep a change is learned from the vendor software, so this
    /// comes from the firmware profile.
    pub commit_reports: Vec<Vec<u8>>,
}

#[derive(Debug)]
pub enum ApplyReport {
    /// The device already held this configuration; nothing was written and
    /// no backup was made.
    AlreadyApplied,
    Applied {
        backup: SnapshotPaths,
        changes: Vec<DiffRun>,
    },
}

/// What writing `intended` would change. Reads only.
pub fn preview(
    device: &mut dyn HidDevice,
    intended: &ConfigBytes,
) -> Result<Vec<DiffRun>, ApplyError> {
    let current = read_config(device).map_err(|source| ApplyError::Read { source })?;
    Ok(diff(&current, intended, &VolatileSet::none()))
}

pub fn apply_config(
    device: &mut dyn HidDevice,
    intended: &ConfigBytes,
    options: &ApplyOptions,
    now: UtcTimestamp,
) -> Result<ApplyReport, ApplyError> {
    apply_labelled(device, intended, options, now, APPLY_LABEL)
}

/// Writes `snapshot` back, after checking it belongs to this device.
pub fn restore_config(
    device: &mut dyn HidDevice,
    snapshot: &ConfigSnapshot,
    options: &ApplyOptions,
    now: UtcTimestamp,
) -> Result<ApplyReport, RestoreError> {
    let current = read_config(device).map_err(|source| RestoreError::Read { source })?;

    let device_serial = device.serial();
    if snapshot.meta().serial != device_serial {
        return Err(RestoreError::WrongDevice {
            snapshot: snapshot.meta().serial.clone(),
            device: device_serial,
        });
    }
    let device_firmware = identity::data_version(&current);
    if snapshot.meta().firmware != device_firmware {
        return Err(RestoreError::FirmwareMismatch {
            snapshot: snapshot.meta().firmware,
            device: device_firmware,
        });
    }

    apply_labelled(device, snapshot.bytes(), options, now, RESTORE_LABEL)
        .map_err(|source| RestoreError::Apply { source })
}

fn apply_labelled(
    device: &mut dyn HidDevice,
    intended: &ConfigBytes,
    options: &ApplyOptions,
    now: UtcTimestamp,
    label: &str,
) -> Result<ApplyReport, ApplyError> {
    if let Some(&got) = intended.as_slice().first() {
        if got != CTRL_REPORT_ID {
            return Err(ApplyError::InvalidIntended {
                expected: CTRL_REPORT_ID,
                got,
            });
        }
    }

    let current = read_config(device).map_err(|source| ApplyError::Read { source })?;
    let changes = diff(&current, intended, &VolatileSet::none());
    if changes.is_empty() {
        return Ok(ApplyReport::AlreadyApplied);
    }

    // No backup, no write.
    let backup = ConfigSnapshot::new(
        current.clone(),
        device.serial(),
        identity::data_version(&current),
        now,
        label,
    )
    .write_to(&options.backup_dir)
    .map_err(|source| ApplyError::Backup { source })?;

    device
        .set_feature(intended.as_slice())
        .map_err(|source| ApplyError::Write {
            backup: Box::new(backup.clone()),
            source,
        })?;

    for (index, report) in options.commit_reports.iter().enumerate() {
        device
            .set_feature(report)
            .map_err(|source| ApplyError::Commit {
                index,
                backup: Box::new(backup.clone()),
                source,
            })?;
    }

    let read_back = read_config(device).map_err(|source| ApplyError::ReadBack {
        backup: Box::new(backup.clone()),
        source,
    })?;
    let mismatch = diff(intended, &read_back, &VolatileSet::none());
    if !mismatch.is_empty() {
        return Err(ApplyError::Mismatch {
            backup: Box::new(backup),
            runs: mismatch,
        });
    }

    Ok(ApplyReport::Applied { backup, changes })
}
