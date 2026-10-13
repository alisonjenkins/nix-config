//! An in-memory aquaero for tests: it stores a configuration, answers the
//! feature reports the tool uses, records when each operation happened, and
//! can be told to fail in the ways a real device can.

use std::io;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;

use crate::error::HidError;
use crate::hid::{Clock, HidDevice, CTRL_REPORT_ID, SECONDARY_REPORT_ID, SECONDARY_REPORT_LEN};
use crate::snapshot::{ConfigBytes, CONFIG_LEN};

/// A clock that only moves when [`Clock::sleep`] is called.
#[derive(Debug, Default)]
pub struct ManualClock {
    nanos: AtomicU64,
}

impl ManualClock {
    pub fn new() -> Self {
        Self::default()
    }
}

impl Clock for ManualClock {
    fn now(&self) -> Duration {
        Duration::from_nanos(self.nanos.load(Ordering::SeqCst))
    }

    fn sleep(&self, duration: Duration) {
        let nanos = u64::try_from(duration.as_nanos()).unwrap_or(u64::MAX);
        self.nanos.fetch_add(nanos, Ordering::SeqCst);
    }
}

/// A way for the fake to misbehave.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Fault {
    /// The next configuration write fails and changes nothing.
    RejectNextWrite,
    /// The next read returns only this many bytes.
    ShortReadNext { bytes: usize },
    /// After this many more operations, every operation reports a disconnect.
    DisconnectAfter { ops: usize },
    /// The next accepted write is stored with one byte flipped, so the read
    /// back differs from what was written.
    DriftAfterNextWrite { offset: usize },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OpKind {
    Get,
    Set,
}

/// One operation the fake served.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct OpRecord {
    pub kind: OpKind,
    pub report_id: u8,
    pub at: Duration,
}

#[derive(Debug)]
pub struct FakeDevice {
    path: PathBuf,
    config: ConfigBytes,
    clock: Arc<ManualClock>,
    ops: Vec<OpRecord>,
    secondary: Vec<Vec<u8>>,
    writes_applied: usize,
    reject_next_write: bool,
    short_read_next: Option<usize>,
    disconnect_after: Option<usize>,
    drift_after_write: Option<usize>,
}

impl FakeDevice {
    pub fn new(config: ConfigBytes, clock: Arc<ManualClock>) -> Self {
        Self {
            path: PathBuf::from("/dev/fake-hidraw0"),
            config,
            clock,
            ops: Vec::new(),
            secondary: Vec::new(),
            writes_applied: 0,
            reject_next_write: false,
            short_read_next: None,
            disconnect_after: None,
            drift_after_write: None,
        }
    }

    pub fn inject(&mut self, fault: Fault) {
        match fault {
            Fault::RejectNextWrite => self.reject_next_write = true,
            Fault::ShortReadNext { bytes } => self.short_read_next = Some(bytes),
            Fault::DisconnectAfter { ops } => self.disconnect_after = Some(ops),
            Fault::DriftAfterNextWrite { offset } => self.drift_after_write = Some(offset),
        }
    }

    /// The configuration as stored right now.
    pub fn config(&self) -> ConfigBytes {
        self.config.clone()
    }

    /// Configuration writes the device accepted.
    pub fn writes_applied(&self) -> usize {
        self.writes_applied
    }

    pub fn secondary_reports(&self) -> &[Vec<u8>] {
        &self.secondary
    }

    pub fn ops(&self) -> &[OpRecord] {
        &self.ops
    }

    /// Time between each operation and the one before it.
    pub fn observed_gaps(&self) -> Vec<Duration> {
        self.ops
            .iter()
            .zip(self.ops.iter().skip(1))
            .map(|(earlier, later)| later.at.saturating_sub(earlier.at))
            .collect()
    }

    fn begin_op(&mut self, operation: &'static str) -> Result<(), HidError> {
        match self.disconnect_after {
            Some(0) => {
                return Err(HidError::Disconnected {
                    path: self.path.clone(),
                    operation,
                })
            }
            Some(remaining) => self.disconnect_after = Some(remaining.saturating_sub(1)),
            None => {}
        }
        Ok(())
    }

    fn record(&mut self, kind: OpKind, report_id: u8) {
        self.ops.push(OpRecord {
            kind,
            report_id,
            at: self.clock.now(),
        });
    }

    fn set_error(&self, report_id: u8, len: usize, source: io::Error) -> HidError {
        HidError::SetFeature {
            path: self.path.clone(),
            report_id,
            len,
            source,
        }
    }
}

impl HidDevice for FakeDevice {
    fn path(&self) -> &Path {
        &self.path
    }

    fn get_feature(&mut self, report_id: u8, len: usize) -> Result<Vec<u8>, HidError> {
        self.begin_op("get_feature")?;
        self.record(OpKind::Get, report_id);

        if report_id != CTRL_REPORT_ID {
            return Err(HidError::GetFeature {
                path: self.path.clone(),
                report_id,
                source: io::Error::new(io::ErrorKind::Unsupported, "report not served by the fake"),
            });
        }
        let take = self.short_read_next.take().unwrap_or(len);
        Ok(self.config.as_slice().iter().take(take).copied().collect())
    }

    fn set_feature(&mut self, report: &[u8]) -> Result<(), HidError> {
        self.begin_op("set_feature")?;
        let report_id = report.first().copied().unwrap_or(0);
        self.record(OpKind::Set, report_id);

        match report_id {
            CTRL_REPORT_ID => {
                if report.len() != CONFIG_LEN {
                    return Err(self.set_error(
                        report_id,
                        report.len(),
                        io::Error::new(io::ErrorKind::InvalidInput, "wrong report length"),
                    ));
                }
                if self.reject_next_write {
                    self.reject_next_write = false;
                    return Err(self.set_error(
                        report_id,
                        report.len(),
                        io::Error::other("write rejected by the fake"),
                    ));
                }
                let mut stored = report.to_vec();
                if let Some(offset) = self.drift_after_write.take() {
                    if let Some(byte) = stored.get_mut(offset) {
                        *byte ^= 0xff;
                    }
                }
                self.config =
                    ConfigBytes::new(stored).map_err(|source| HidError::InvalidConfig {
                        path: self.path.clone(),
                        source,
                    })?;
                self.writes_applied = self.writes_applied.saturating_add(1);
                Ok(())
            }
            SECONDARY_REPORT_ID => {
                if report.len() != SECONDARY_REPORT_LEN {
                    return Err(self.set_error(
                        report_id,
                        report.len(),
                        io::Error::new(io::ErrorKind::InvalidInput, "wrong report length"),
                    ));
                }
                self.secondary.push(report.to_vec());
                Ok(())
            }
            other => Err(self.set_error(
                other,
                report.len(),
                io::Error::new(io::ErrorKind::Unsupported, "report not served by the fake"),
            )),
        }
    }
}
