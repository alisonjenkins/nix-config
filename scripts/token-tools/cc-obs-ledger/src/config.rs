//! Where the tool keeps state and finds the collector.

use std::env;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::thread;
use std::time::Duration;

use serde::Deserialize;
use time::format_description::well_known::Rfc3339;
use time::OffsetDateTime;

use crate::error::LedgerError;

pub fn home_dir() -> PathBuf {
    env::var_os("HOME").map(PathBuf::from).unwrap_or_default()
}

pub fn xdg(var: &str, fallback: &str) -> PathBuf {
    match env::var_os(var).filter(|value| !value.is_empty()) {
        Some(value) => PathBuf::from(value),
        None => home_dir().join(fallback),
    }
}

pub fn state_dir() -> PathBuf {
    xdg("XDG_STATE_HOME", ".local/state").join("cc-obs-ledger")
}

pub fn endpoints_path() -> PathBuf {
    match env::var_os("CC_OBS_ENDPOINTS").filter(|value| !value.is_empty()) {
        Some(value) => PathBuf::from(value),
        None => xdg("XDG_CONFIG_HOME", ".config").join("cc-obs/endpoints.json"),
    }
}

/// The part of the module's `endpoints.json` this tool reads.
#[derive(Debug, Deserialize)]
pub struct Endpoints {
    pub host: String,
    pub urls: Urls,
}

#[derive(Debug, Deserialize)]
pub struct Urls {
    #[serde(rename = "otlpHttp")]
    pub otlp_http: String,
}

pub fn load_endpoints(path: &Path) -> Result<Endpoints, LedgerError> {
    let text = fs::read_to_string(path).map_err(|source| LedgerError::Read {
        path: path.to_owned(),
        source,
    })?;
    serde_json::from_str(&text).map_err(|source| LedgerError::ParseFile {
        path: path.to_owned(),
        source,
    })
}

pub fn create_dir(path: &Path) -> Result<(), LedgerError> {
    fs::create_dir_all(path).map_err(|source| LedgerError::CreateDir {
        path: path.to_owned(),
        source,
    })
}

const KEY_BYTES: usize = 32;

static TEMP_COUNTER: AtomicU64 = AtomicU64::new(0);

enum KeyState {
    Missing,
    Short,
    Ready(Vec<u8>),
}

fn inspect_key(path: &Path) -> Result<KeyState, LedgerError> {
    match fs::read(path) {
        Ok(key) if key.len() >= KEY_BYTES => Ok(KeyState::Ready(key)),
        Ok(_) => Ok(KeyState::Short),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(KeyState::Missing),
        Err(source) => Err(LedgerError::Read {
            path: path.to_owned(),
            source,
        }),
    }
}

/// A short file may be a publisher mid-write, so wait briefly before calling it partial.
const SHORT_KEY_RETRIES: u32 = 5;
const SHORT_KEY_RETRY_DELAY: Duration = Duration::from_millis(20);

fn inspect_key_settled(path: &Path) -> Result<KeyState, LedgerError> {
    let mut state = inspect_key(path)?;
    for _ in 0..SHORT_KEY_RETRIES {
        if !matches!(state, KeyState::Short) {
            break;
        }
        thread::sleep(SHORT_KEY_RETRY_DELAY);
        state = inspect_key(path)?;
    }
    Ok(state)
}

fn random_key() -> Result<[u8; KEY_BYTES], LedgerError> {
    use std::io::Read;

    let mut random = [0u8; KEY_BYTES];
    fs::File::open("/dev/urandom")
        .and_then(|mut file| file.read_exact(&mut random))
        .map_err(|source| LedgerError::Read {
            path: PathBuf::from("/dev/urandom"),
            source,
        })?;
    Ok(random)
}

/// Publishes the complete temp file at the final path without overwriting it.
pub type Publish = dyn Fn(&Path, &Path) -> std::io::Result<()>;

/// The per-host key for tool-input hashes, created on first use with mode 0600.
pub fn load_or_create_key(state: &Path) -> Result<Vec<u8>, LedgerError> {
    load_or_create_key_with(state, &|temp, path| fs::hard_link(temp, path))
}

/// Concurrent hooks race to publish a complete temp file with `publish` (`hard_link`
/// cannot overwrite) and the losers adopt the winner's key. Where `publish` fails for
/// another reason, such as a filesystem without hard links, the key is written
/// directly with an exclusive create. Only a readable key shorter than 32 bytes is
/// replaced; an unreadable one is an error.
pub fn load_or_create_key_with(state: &Path, publish: &Publish) -> Result<Vec<u8>, LedgerError> {
    let path = state.join("hmac.key");
    if let KeyState::Ready(key) = inspect_key_settled(&path)? {
        return Ok(key);
    }
    create_dir(state)?;
    let random = random_key()?;
    let temp = temp_path(&path);
    write_new(&temp, &random).map_err(|source| LedgerError::Write {
        path: temp.clone(),
        source,
    })?;
    let published = match publish(&temp, &path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => Err(error),
        Err(_) => write_new(&path, &random),
    };
    let result = match published {
        Ok(()) => Ok(random.to_vec()),
        Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
            match inspect_key_settled(&path) {
                Ok(KeyState::Ready(winner)) => Ok(winner),
                Ok(KeyState::Missing | KeyState::Short) => fs::rename(&temp, &path)
                    .map(|()| random.to_vec())
                    .map_err(|source| LedgerError::Write {
                        path: path.clone(),
                        source,
                    }),
                Err(error) => Err(error),
            }
        }
        Err(source) => Err(LedgerError::Write {
            path: path.clone(),
            source,
        }),
    };
    let _ = fs::remove_file(&temp);
    result
}

fn write_new(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    use std::os::unix::fs::OpenOptionsExt;

    let mut file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(path)?;
    file.write_all(bytes)?;
    file.sync_all()
}

fn temp_path(path: &Path) -> PathBuf {
    let name = path
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_default();
    path.with_file_name(format!(
        ".{name}.{}.{}.tmp",
        std::process::id(),
        TEMP_COUNTER.fetch_add(1, Ordering::Relaxed)
    ))
}

/// Replaces `path` with `bytes` so a crash leaves the old or the new content, never a partial file.
pub fn write_atomic(path: &Path, bytes: &[u8]) -> Result<(), LedgerError> {
    write_atomic_with(path, bytes, &write_new)
}

pub fn write_atomic_with(
    path: &Path,
    bytes: &[u8],
    write_temp: &dyn Fn(&Path, &[u8]) -> std::io::Result<()>,
) -> Result<(), LedgerError> {
    let temp = temp_path(path);
    let result = write_temp(&temp, bytes).and_then(|()| fs::rename(&temp, path));
    if result.is_err() {
        let _ = fs::remove_file(&temp);
    }
    result.map_err(|source| LedgerError::Write {
        path: path.to_owned(),
        source,
    })
}

/// Appends one line to the local log. Failures here are ignored: logging must
/// never be the reason a hook fails.
pub fn log_line(state: &Path, message: &str) {
    log_line_capped(state, message, LOG_MAX_BYTES);
}

/// The log is rotated to `ledger.log.1` past this size, so it cannot grow without bound.
const LOG_MAX_BYTES: u64 = 1024 * 1024;

/// `log_line` with the rotation size given.
pub fn log_line_capped(state: &Path, message: &str, max_bytes: u64) {
    let now = OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .unwrap_or_else(|_| "unknown-time".to_owned());
    if create_dir(state).is_err() {
        return;
    }
    let log = state.join("ledger.log");
    if fs::metadata(&log).is_ok_and(|meta| meta.len() >= max_bytes) {
        let _ = fs::rename(&log, state.join("ledger.log.1"));
    }
    let Ok(mut file) = fs::OpenOptions::new().create(true).append(true).open(&log) else {
        return;
    };
    let _ = writeln!(file, "{now} {message}");
}
