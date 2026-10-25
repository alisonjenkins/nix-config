//! Payloads are written to a spool directory by the hook, then posted by a
//! separate detached process, so a slow or unreachable collector never delays
//! Claude Code. A file that cannot be sent stays for the next run, up to a day.

use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use crate::config::create_dir;
use crate::error::LedgerError;
use crate::otlp::{Payload, Signal};

/// How long an unsent payload is retried before it is dropped.
const MAX_AGE: Duration = Duration::from_secs(24 * 60 * 60);

/// Each POST has its own timeout, so a spool of N files against a collector that
/// never answers would hold the lock for N times that; stop starting files past this.
const RUN_BUDGET: Duration = Duration::from_secs(30);

const LOCK_NAME: &str = ".lock";

static COUNTER: AtomicU64 = AtomicU64::new(0);

#[derive(Debug, Default)]
pub struct ShipReport {
    pub sent: usize,
    pub expired: usize,
    pub failed: Vec<String>,
    /// Why the run did not look at the spool at all.
    pub skipped: Option<String>,
    /// Why files were left for the next run; not a failure of any file.
    pub deferred: Option<String>,
}

impl ShipReport {
    /// One log line for the whole run, or `None` when it had nothing to do.
    pub fn summary(&self) -> Option<String> {
        if let Some(reason) = &self.skipped {
            return Some(format!("ship: skipped, {reason}"));
        }
        if self.sent == 0 && self.expired == 0 && self.failed.is_empty() && self.deferred.is_none()
        {
            return None;
        }
        let first = self
            .failed
            .first()
            .map(|failure| format!(" first_failure=\"{}\"", failure.replace('\n', " ")))
            .unwrap_or_default();
        let deferred = self
            .deferred
            .as_ref()
            .map(|reason| format!(" deferred=\"{reason}\""))
            .unwrap_or_default();
        Some(format!(
            "ship: sent={} expired={} failed={}{first}{deferred}",
            self.sent,
            self.expired,
            self.failed.len()
        ))
    }
}

fn signal_name(signal: Signal) -> &'static str {
    match signal {
        Signal::Metrics => "metrics",
        Signal::Logs => "logs",
    }
}

pub fn write_spool(dir: &Path, payload: &Payload) -> Result<PathBuf, LedgerError> {
    create_dir(dir)?;
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |elapsed| elapsed.as_nanos());
    let count = COUNTER.fetch_add(1, Ordering::Relaxed);
    let name = format!(
        "{nanos}-{}-{count}.{}.json",
        std::process::id(),
        signal_name(payload.signal)
    );
    let path = dir.join(&name);
    let partial = dir.join(format!(".{name}.partial"));
    fs::write(&partial, payload.body.to_string()).map_err(|source| LedgerError::Write {
        path: partial.clone(),
        source,
    })?;
    fs::rename(&partial, &path).map_err(|source| LedgerError::Write {
        path: path.clone(),
        source,
    })?;
    Ok(path)
}

fn signal_of(name: &str) -> Option<&'static str> {
    if name.ends_with(".metrics.json") {
        Some("metrics")
    } else if name.ends_with(".logs.json") {
        Some("logs")
    } else {
        None
    }
}

pub fn ship_spool(dir: &Path, base_url: &str, timeout: Duration) -> ShipReport {
    ship_spool_within(dir, base_url, timeout, RUN_BUDGET)
}

fn too_old(path: &Path) -> bool {
    fs::metadata(path)
        .and_then(|meta| meta.modified())
        .ok()
        .and_then(|modified| modified.elapsed().ok())
        .is_some_and(|age| age > MAX_AGE)
}

/// Files this run has to act on: payloads to send and anything past its age to drop.
fn list_work(dir: &Path, attempted: &HashSet<PathBuf>) -> Result<Vec<PathBuf>, std::io::Error> {
    let mut files: Vec<PathBuf> = fs::read_dir(dir)?
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| !attempted.contains(path))
        .filter(|path| {
            let Some(name) = path.file_name().map(|n| n.to_string_lossy().into_owned()) else {
                return false;
            };
            name != LOCK_NAME && (signal_of(&name).is_some() || too_old(path))
        })
        .collect();
    files.sort();
    Ok(files)
}

/// `ship_spool` with the run's length given: no file is started once `budget` is spent.
pub fn ship_spool_within(
    dir: &Path,
    base_url: &str,
    timeout: Duration,
    budget: Duration,
) -> ShipReport {
    let mut report = ShipReport::default();
    match fs::metadata(dir) {
        Ok(meta) if meta.is_dir() => {}
        Ok(_) => {
            report
                .failed
                .push(format!("{} is not a directory", dir.display()));
            return report;
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return report,
        Err(error) => {
            report
                .failed
                .push(format!("listing {}: {error}", dir.display()));
            return report;
        }
    }
    // One sender at a time: an overlapping run (Stop then SessionEnd, two sessions)
    // would post the same files twice. The lock dies with the process, so no stale state.
    let lock = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(dir.join(LOCK_NAME));
    let lock = match lock {
        Ok(lock) => lock,
        Err(error) => {
            report
                .failed
                .push(format!("opening {}/{LOCK_NAME}: {error}", dir.display()));
            return report;
        }
    };
    if lock.try_lock().is_err() {
        report.skipped = Some(format!(
            "another sender holds {}/{LOCK_NAME}; its run logs the result",
            dir.display()
        ));
        return report;
    }
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .timeout_global(Some(timeout))
        .build()
        .into();
    let started = Instant::now();
    // Listed after the lock is held and again after each pass until nothing new is left:
    // hooks keep spooling while a sender is mid-POST, and the sender that skipped on the
    // lock will not retry.
    let mut attempted = HashSet::new();
    loop {
        let files = match list_work(dir, &attempted) {
            Ok(files) => files,
            Err(error) => {
                report
                    .failed
                    .push(format!("listing {}: {error}", dir.display()));
                return report;
            }
        };
        if files.is_empty() {
            break;
        }
        for (index, path) in files.iter().enumerate() {
            if started.elapsed() > budget {
                report.deferred = Some(format!(
                    "run budget of {}s spent, {} files left for the next run",
                    budget.as_secs_f32(),
                    files.len().saturating_sub(index)
                ));
                return report;
            }
            attempted.insert(path.clone());
            send_one(&agent, base_url, path, &mut report);
        }
    }
    report
}

fn send_one(agent: &ureq::Agent, base_url: &str, path: &Path, report: &mut ShipReport) {
    let Some(name) = path.file_name().map(|n| n.to_string_lossy().into_owned()) else {
        return;
    };
    if too_old(path) {
        if fs::remove_file(path).is_ok() {
            report.expired = report.expired.saturating_add(1);
        }
        return;
    }
    let Some(signal) = signal_of(&name) else {
        return;
    };
    let body = match fs::read_to_string(path) {
        Ok(body) => body,
        Err(error) => {
            report
                .failed
                .push(format!("reading {}: {error}", path.display()));
            return;
        }
    };
    let url = format!("{}/v1/{signal}", base_url.trim_end_matches('/'));
    match agent
        .post(&url)
        .header("content-type", "application/json")
        .send(body.as_str())
    {
        Ok(_) => {
            if let Err(error) = fs::remove_file(path) {
                report
                    .failed
                    .push(format!("removing sent {}: {error}", path.display()));
            } else {
                report.sent = report.sent.saturating_add(1);
            }
        }
        Err(error) => report
            .failed
            .push(format!("POST {url} for {name}: {error}")),
    }
}
