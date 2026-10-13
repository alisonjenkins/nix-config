//! A snapshot of the device's stored configuration: the raw bytes plus
//! metadata, kept as `<stem>.bin` and `<stem>.json`.

use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::error::SnapshotError;
use crate::timestamp::UtcTimestamp;

/// Size of the configuration report, including its leading report id byte.
pub const CONFIG_LEN: usize = 0xa93;

const REDACTED_SERIAL: &str = "REDACTED";
const DEFAULT_LABEL: &str = "snapshot";
const MAX_LABEL_LEN: usize = 48;

/// Exactly [`CONFIG_LEN`] bytes of configuration; no other length can exist.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConfigBytes(Vec<u8>);

impl ConfigBytes {
    pub fn new(bytes: Vec<u8>) -> Result<Self, SnapshotError> {
        if bytes.len() != CONFIG_LEN {
            return Err(SnapshotError::Length {
                got: bytes.len(),
                expected: CONFIG_LEN,
            });
        }
        Ok(Self(bytes))
    }

    pub fn as_slice(&self) -> &[u8] {
        &self.0
    }

    /// Lower-case hex SHA-256 of the bytes.
    pub fn sha256_hex(&self) -> String {
        let digest = Sha256::digest(&self.0);
        digest.iter().map(|b| format!("{b:02x}")).collect()
    }
}

/// What the sidecar `.json` holds.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SnapshotMeta {
    pub serial: String,
    pub firmware: u32,
    /// ISO 8601 UTC, e.g. `2026-10-13T09:50:12Z`.
    pub taken_at: String,
    pub label: String,
    pub sha256: String,
    pub length: usize,
    pub tool_version: String,
}

/// Where a snapshot was written.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SnapshotPaths {
    pub bin: PathBuf,
    pub json: PathBuf,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConfigSnapshot {
    bytes: ConfigBytes,
    meta: SnapshotMeta,
    stem: String,
}

impl ConfigSnapshot {
    pub fn new(
        bytes: ConfigBytes,
        serial: String,
        firmware: u32,
        taken_at: UtcTimestamp,
        label: &str,
    ) -> Self {
        let label = normalise_label(label);
        let stem = format!("{}-{}", taken_at.compact(), label);
        let meta = SnapshotMeta {
            serial,
            firmware,
            taken_at: taken_at.iso(),
            label,
            sha256: bytes.sha256_hex(),
            length: CONFIG_LEN,
            tool_version: env!("CARGO_PKG_VERSION").to_string(),
        };
        Self { bytes, meta, stem }
    }

    pub fn bytes(&self) -> &ConfigBytes {
        &self.bytes
    }

    pub fn meta(&self) -> &SnapshotMeta {
        &self.meta
    }

    /// `20261013T095012Z-baseline`: sorts in time order.
    pub fn file_stem(&self) -> String {
        self.stem.clone()
    }

    /// Hides the serial number in the metadata.
    pub fn redact_serial(&mut self) {
        self.meta.serial = REDACTED_SERIAL.to_string();
    }

    /// Zeroes `len` bytes at `offset` and updates the hash, so the snapshot
    /// stays valid. The caller supplies where the serial number lives.
    pub fn redact_range(&mut self, offset: usize, len: usize) -> Result<(), SnapshotError> {
        let range = offset
            .checked_add(len)
            .and_then(|end| self.bytes.0.get_mut(offset..end))
            .ok_or(SnapshotError::RedactRange { offset, len })?;
        range.fill(0);
        self.meta.sha256 = self.bytes.sha256_hex();
        Ok(())
    }

    /// Writes `<stem>.bin` and `<stem>.json` into `dir`, creating it if
    /// needed. An existing snapshot of the same name is never overwritten.
    pub fn write_to(&self, dir: &Path) -> Result<SnapshotPaths, SnapshotError> {
        fs::create_dir_all(dir).map_err(|source| SnapshotError::Write {
            path: dir.to_path_buf(),
            source,
        })?;
        let paths = SnapshotPaths {
            bin: dir.join(format!("{}.bin", self.stem)),
            json: dir.join(format!("{}.json", self.stem)),
        };
        let json = serde_json::to_string_pretty(&self.meta)
            .map_err(|source| SnapshotError::MetaSerialize { source })?;

        create_new(&paths.bin, self.bytes.as_slice())?;
        create_new(&paths.json, json.as_bytes())?;
        Ok(paths)
    }

    /// Reads a snapshot from its `.bin`, using the `.json` beside it. The
    /// length is checked before the hash so a truncated file says so.
    pub fn read(bin: &Path) -> Result<Self, SnapshotError> {
        let json_path = bin.with_extension("json");
        let json = fs::read_to_string(&json_path).map_err(|source| SnapshotError::Read {
            path: json_path.clone(),
            source,
        })?;
        let meta: SnapshotMeta =
            serde_json::from_str(&json).map_err(|source| SnapshotError::MetaParse {
                path: json_path,
                source,
            })?;

        let raw = fs::read(bin).map_err(|source| SnapshotError::Read {
            path: bin.to_path_buf(),
            source,
        })?;
        let bytes = ConfigBytes::new(raw)?;

        let actual = bytes.sha256_hex();
        if actual != meta.sha256 {
            return Err(SnapshotError::HashMismatch {
                path: bin.to_path_buf(),
                expected: meta.sha256,
                actual,
            });
        }

        let stem = bin
            .file_stem()
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or_default();
        Ok(Self { bytes, meta, stem })
    }
}

fn create_new(path: &Path, contents: &[u8]) -> Result<(), SnapshotError> {
    let write_err = |source| SnapshotError::Write {
        path: path.to_path_buf(),
        source,
    };
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .map_err(write_err)?;
    file.write_all(contents).map_err(write_err)
}

/// Reduces a label to lower-case letters, digits and single dashes, so it is
/// safe in a file name. An empty result becomes `snapshot`.
pub fn normalise_label(label: &str) -> String {
    let mut out = String::new();
    for c in label.chars() {
        let c = c.to_ascii_lowercase();
        if c.is_ascii_alphanumeric() {
            out.push(c);
        } else if !out.ends_with('-') {
            out.push('-');
        }
    }
    let trimmed = out.trim_matches('-');
    let limited: String = trimmed.chars().take(MAX_LABEL_LEN).collect();
    let limited = limited.trim_matches('-');
    if limited.is_empty() {
        DEFAULT_LABEL.to_string()
    } else {
        limited.to_string()
    }
}
