//! The read-only `dump` operation: save the device's configuration as a snapshot.

use std::path::PathBuf;

use crate::error::DumpError;
use crate::hid::{read_config, HidDevice};
use crate::identity;
use crate::snapshot::{ConfigSnapshot, SnapshotPaths};
use crate::timestamp::UtcTimestamp;

#[derive(Debug, Clone)]
pub struct DumpOptions {
    pub out_dir: PathBuf,
    pub label: String,
    /// Hide the serial in the metadata so the snapshot can be committed. The
    /// serial is not part of the stored bytes.
    pub redact_serial: bool,
}

/// Reads the configuration and writes it under `out_dir`. Only reads from the
/// device; nothing is written if the read fails.
pub fn dump(
    device: &mut dyn HidDevice,
    options: &DumpOptions,
    now: UtcTimestamp,
) -> Result<SnapshotPaths, DumpError> {
    let bytes = read_config(device).map_err(|source| DumpError::Read { source })?;

    let mut snapshot = ConfigSnapshot::new(
        bytes.clone(),
        device.serial(),
        identity::data_version(&bytes),
        now,
        &options.label,
    );
    if options.redact_serial {
        snapshot.redact_serial();
    }

    snapshot
        .write_to(&options.out_dir)
        .map_err(|source| DumpError::Save { source })
}
