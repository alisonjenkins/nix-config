//! Error types. One enum per fallible operation, with a variant per failure
//! site carrying the path, offset or length that identifies it.

use std::io;
use std::path::PathBuf;

use thiserror::Error;

use crate::diff::DiffRun;
use crate::snapshot::SnapshotPaths;

/// Failures talking to the device through a [`crate::hid::HidDevice`].
#[derive(Debug, Error)]
pub enum HidError {
    #[error("cannot open {path}")]
    Open {
        path: PathBuf,
        #[source]
        source: io::Error,
    },

    #[error("{path}: reading feature report {report_id:#04x} failed")]
    GetFeature {
        path: PathBuf,
        report_id: u8,
        #[source]
        source: io::Error,
    },

    #[error("{path}: writing feature report {report_id:#04x} ({len} bytes) failed")]
    SetFeature {
        path: PathBuf,
        report_id: u8,
        len: usize,
        #[source]
        source: io::Error,
    },

    #[error("{path}: feature report {report_id:#04x} was {got} bytes, expected {expected}")]
    ShortRead {
        path: PathBuf,
        report_id: u8,
        expected: usize,
        got: usize,
    },

    #[error("{path}: the report starts with id {got:#04x}, expected {expected:#04x}")]
    UnexpectedReportId {
        path: PathBuf,
        expected: u8,
        got: u8,
    },

    #[error("{path}: the device disappeared during {operation}")]
    Disconnected {
        path: PathBuf,
        operation: &'static str,
    },

    #[error("{path}: the configuration report is not valid")]
    InvalidConfig {
        path: PathBuf,
        #[source]
        source: SnapshotError,
    },

    #[error("{path}: cannot space device operations")]
    Spacing {
        path: PathBuf,
        #[source]
        source: LockError,
    },
}

/// Failures applying a configuration to the device. Every variant that can
/// follow a changed device carries the backup and says how to restore it.
#[derive(Debug, Error)]
pub enum ApplyError {
    #[error("cannot read the device's current configuration")]
    Read {
        #[source]
        source: HidError,
    },

    #[error("the configuration to write starts with report id {got:#04x}, not {expected:#04x}")]
    InvalidIntended { expected: u8, got: u8 },

    #[error("cannot save a backup first, so nothing was written")]
    Backup {
        #[source]
        source: SnapshotError,
    },

    #[error(
        "writing the configuration failed. The previous configuration is saved at {}; to put it back run: aquaero-ctl restore {}",
        backup.bin.display(),
        backup.bin.display()
    )]
    Write {
        backup: Box<SnapshotPaths>,
        #[source]
        source: HidError,
    },

    #[error(
        "commit report {index} failed after the configuration was written. The previous configuration is saved at {}; to put it back run: aquaero-ctl restore {}",
        backup.bin.display(),
        backup.bin.display()
    )]
    Commit {
        index: usize,
        backup: Box<SnapshotPaths>,
        #[source]
        source: HidError,
    },

    #[error(
        "the configuration was written but could not be read back, so it is not verified. The previous configuration is saved at {}; to put it back run: aquaero-ctl restore {}",
        backup.bin.display(),
        backup.bin.display()
    )]
    ReadBack {
        backup: Box<SnapshotPaths>,
        #[source]
        source: HidError,
    },

    #[error(
        "the device did not keep the configuration it was given: {}. The previous configuration is saved at {}; to put it back run: aquaero-ctl restore {}",
        describe_mismatch(runs),
        backup.bin.display(),
        backup.bin.display()
    )]
    Mismatch {
        backup: Box<SnapshotPaths>,
        /// Intended bytes as `before`, what the device holds as `after`.
        runs: Vec<DiffRun>,
    },
}

fn describe_mismatch(runs: &[DiffRun]) -> String {
    runs.iter()
        .map(|run| {
            format!(
                "at {:#06x} expected {}, device holds {}",
                run.offset,
                crate::diff::hex(&run.before),
                crate::diff::hex(&run.after)
            )
        })
        .collect::<Vec<_>>()
        .join("; ")
}

/// Failures restoring a snapshot.
#[derive(Debug, Error)]
pub enum RestoreError {
    #[error("cannot read the device to check the snapshot belongs to it")]
    Read {
        #[source]
        source: HidError,
    },

    #[error("the snapshot is from device {snapshot}, the connected device is {device}")]
    WrongDevice { snapshot: String, device: String },

    #[error("the snapshot is from firmware {snapshot}, the device runs {device}")]
    FirmwareMismatch { snapshot: u32, device: u32 },

    #[error("cannot restore the snapshot")]
    Apply {
        #[source]
        source: ApplyError,
    },
}

/// Failures of the read-only dump.
#[derive(Debug, Error)]
pub enum DumpError {
    #[error("cannot read the configuration from the device")]
    Read {
        #[source]
        source: HidError,
    },

    #[error("cannot save the snapshot")]
    Save {
        #[source]
        source: SnapshotError,
    },
}

/// Failures finding the device under `/sys/class/hidraw`.
#[derive(Debug, Error)]
pub enum SelectError {
    /// No aquaero is connected. Callers decide whether that is an error.
    #[error("no aquaero is connected")]
    Absent,

    #[error("more than one aquaero is connected ({}); pick one with --serial", devices.join(", "))]
    Ambiguous { devices: Vec<String> },

    #[error("no aquaero with serial {wanted}; connected: {}", present.join(", "))]
    SerialNotFound {
        wanted: String,
        present: Vec<String>,
    },

    #[error("cannot read {path}")]
    Sysfs {
        path: PathBuf,
        #[source]
        source: io::Error,
    },
}

/// Failures taking the device lock or spacing control operations.
#[derive(Debug, Error)]
pub enum LockError {
    #[error("another aquaero-ctl already holds {path}")]
    Held { path: PathBuf },

    #[error("cannot create or open the lock file {path}")]
    Create {
        path: PathBuf,
        #[source]
        source: io::Error,
    },

    #[error("cannot lock {path}")]
    Flock {
        path: PathBuf,
        #[source]
        source: nix::errno::Errno,
    },

    #[error("cannot read or write the last-operation time in {path}")]
    Record {
        path: PathBuf,
        #[source]
        source: io::Error,
    },
}

/// Failures when building, storing or loading a [`crate::snapshot::ConfigSnapshot`].
#[derive(Debug, Error)]
pub enum SnapshotError {
    #[error("configuration is {got} bytes, expected {expected}")]
    Length { got: usize, expected: usize },

    #[error("{path}: sha256 of the bytes is {actual}, the sidecar says {expected}")]
    HashMismatch {
        path: PathBuf,
        expected: String,
        actual: String,
    },

    #[error("cannot read {path}")]
    Read {
        path: PathBuf,
        #[source]
        source: io::Error,
    },

    #[error("cannot write {path}")]
    Write {
        path: PathBuf,
        #[source]
        source: io::Error,
    },

    #[error("cannot parse the metadata in {path}")]
    MetaParse {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },

    #[error("cannot serialise the snapshot metadata")]
    MetaSerialize {
        #[source]
        source: serde_json::Error,
    },

    #[error("redacting {len} bytes at offset {offset} runs past the end of the configuration")]
    RedactRange { offset: usize, len: usize },
}
