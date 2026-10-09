//! Payloads are written to a spool directory by the hook, then posted by a
//! separate detached process, so a slow or unreachable collector never delays
//! Claude Code. A file that cannot be sent stays for the next run, up to a day.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use crate::config::create_dir;
use crate::error::LedgerError;
use crate::otlp::{Payload, Signal};

/// How long an unsent payload is retried before it is dropped.
const MAX_AGE: Duration = Duration::from_secs(24 * 60 * 60);

const LOCK_NAME: &str = ".lock";

static COUNTER: AtomicU64 = AtomicU64::new(0);

#[derive(Debug, Default)]
pub struct ShipReport {
    pub sent: usize,
    pub expired: usize,
    pub failed: Vec<String>,
}

impl ShipReport {
    /// One log line for the whole run, or `None` when it had nothing to do.
    pub fn summary(&self) -> Option<String> {
        if self.sent == 0 && self.expired == 0 && self.failed.is_empty() {
            return None;
        }
        let first = self
            .failed
            .first()
            .map(|failure| format!(" first_failure=\"{}\"", failure.replace('\n', " ")))
            .unwrap_or_default();
        Some(format!(
            "ship: sent={} expired={} failed={}{first}",
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
    let mut report = ShipReport::default();
    let Ok(entries) = fs::read_dir(dir) else {
        return report;
    };
    // One sender at a time: an overlapping run (Stop then SessionEnd, two sessions)
    // would post the same files twice. The lock dies with the process, so no stale state.
    let lock = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(dir.join(LOCK_NAME));
    let Ok(lock) = lock else {
        report
            .failed
            .push(format!("opening {}/{LOCK_NAME}", dir.display()));
        return report;
    };
    if lock.try_lock().is_err() {
        return report;
    }
    let mut files: Vec<PathBuf> = entries.filter_map(Result::ok).map(|e| e.path()).collect();
    files.sort();

    let agent: ureq::Agent = ureq::Agent::config_builder()
        .timeout_global(Some(timeout))
        .build()
        .into();
    for path in files {
        let Some(name) = path.file_name().map(|n| n.to_string_lossy().into_owned()) else {
            continue;
        };
        if name == LOCK_NAME {
            continue;
        }
        let too_old = fs::metadata(&path)
            .and_then(|meta| meta.modified())
            .ok()
            .and_then(|modified| modified.elapsed().ok())
            .is_some_and(|age| age > MAX_AGE);
        if too_old {
            if fs::remove_file(&path).is_ok() {
                report.expired = report.expired.saturating_add(1);
            }
            continue;
        }
        let Some(signal) = signal_of(&name) else {
            continue;
        };
        let body = match fs::read_to_string(&path) {
            Ok(body) => body,
            Err(error) => {
                report
                    .failed
                    .push(format!("reading {}: {error}", path.display()));
                continue;
            }
        };
        let url = format!("{}/v1/{signal}", base_url.trim_end_matches('/'));
        match agent
            .post(&url)
            .header("content-type", "application/json")
            .send(body.as_str())
        {
            Ok(_) => {
                if let Err(error) = fs::remove_file(&path) {
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
    report
}
