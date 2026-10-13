//! One tool at a time on the device, and a minimum gap between control
//! operations that holds even across separate runs.

use std::fs::{File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::time::Duration;

use nix::errno::Errno;
use nix::fcntl::{Flock, FlockArg};

use crate::error::{HidError, LockError};
use crate::hid::{Clock, HidDevice, CONTROL_GAP};

/// An exclusive advisory lock on a file, held until the value is dropped.
/// The file also records when the last control operation started, so the
/// next run knows how much of the gap is left.
#[derive(Debug)]
pub struct DeviceLock {
    flock: Flock<File>,
    path: PathBuf,
}

impl DeviceLock {
    /// Takes the lock without waiting; [`LockError::Held`] if another holds it.
    pub fn acquire(path: &Path) -> Result<Self, LockError> {
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(path)
            .map_err(|source| LockError::Create {
                path: path.to_path_buf(),
                source,
            })?;

        match Flock::lock(file, FlockArg::LockExclusiveNonblock) {
            Ok(flock) => Ok(Self {
                flock,
                path: path.to_path_buf(),
            }),
            Err((_, Errno::EWOULDBLOCK)) => Err(LockError::Held {
                path: path.to_path_buf(),
            }),
            Err((_, source)) => Err(LockError::Flock {
                path: path.to_path_buf(),
                source,
            }),
        }
    }

    /// Sleeps until at least `min` has passed since the last control
    /// operation, then records now as the start of the next one. Returns how
    /// long it slept.
    ///
    /// A record that cannot be parsed counts as no earlier operation. A record
    /// in the future (the clock jumped back) is waited out for at most `min`.
    pub fn wait_for_gap<C: Clock + ?Sized>(
        &mut self,
        clock: &C,
        min: Duration,
    ) -> Result<Duration, LockError> {
        let waited = match self.read_last()? {
            None => Duration::ZERO,
            Some(last) => {
                let now = clock.now();
                if last > now {
                    min
                } else {
                    min.saturating_sub(now.saturating_sub(last))
                }
            }
        };
        if !waited.is_zero() {
            clock.sleep(waited);
        }
        self.write_last(clock.now())?;
        Ok(waited)
    }

    fn read_last(&mut self) -> Result<Option<Duration>, LockError> {
        let mut text = String::new();
        self.flock
            .seek(SeekFrom::Start(0))
            .and_then(|_| self.flock.read_to_string(&mut text))
            .map_err(|source| self.record_error(source))?;
        Ok(text.trim().parse::<u64>().ok().map(Duration::from_nanos))
    }

    fn write_last(&mut self, at: Duration) -> Result<(), LockError> {
        let nanos = u64::try_from(at.as_nanos()).unwrap_or(u64::MAX);
        self.flock
            .set_len(0)
            .and_then(|()| self.flock.seek(SeekFrom::Start(0)).map(|_| ()))
            .and_then(|()| self.flock.write_all(nanos.to_string().as_bytes()))
            .map_err(|source| self.record_error(source))
    }

    fn record_error(&self, source: std::io::Error) -> LockError {
        LockError::Record {
            path: self.path.clone(),
            source,
        }
    }
}

/// A device whose every operation first waits out [`CONTROL_GAP`] through the
/// lock, so callers cannot forget the spacing.
pub struct SpacedDevice<'a, D: HidDevice, C: Clock + ?Sized> {
    inner: D,
    lock: &'a mut DeviceLock,
    clock: &'a C,
}

impl<'a, D: HidDevice, C: Clock + ?Sized> SpacedDevice<'a, D, C> {
    pub fn new(inner: D, lock: &'a mut DeviceLock, clock: &'a C) -> Self {
        Self { inner, lock, clock }
    }

    pub fn into_inner(self) -> D {
        self.inner
    }

    fn space(&mut self) -> Result<(), HidError> {
        self.lock
            .wait_for_gap(self.clock, CONTROL_GAP)
            .map(|_| ())
            .map_err(|source| HidError::Spacing {
                path: self.inner.path().to_path_buf(),
                source,
            })
    }
}

impl<D: HidDevice, C: Clock + ?Sized> HidDevice for SpacedDevice<'_, D, C> {
    fn path(&self) -> &Path {
        self.inner.path()
    }

    fn get_feature(&mut self, report_id: u8, len: usize) -> Result<Vec<u8>, HidError> {
        self.space()?;
        self.inner.get_feature(report_id, len)
    }

    fn set_feature(&mut self, report: &[u8]) -> Result<(), HidError> {
        self.space()?;
        self.inner.set_feature(report)
    }
}
