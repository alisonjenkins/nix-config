//! SessionStart notice: one line when the observability stack is over its disk budget, and
//! one when the newest token review waits to be promoted or dismissed. Every problem reads
//! as "nothing to say", so a session never sees an error.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};

use serde::Deserialize;

use crate::config::xdg;

const GB_TENTH_BYTES: u64 = 100_000_000;

pub fn review_state_dir() -> PathBuf {
    match env::var_os("CC_OBS_REVIEW_STATE_DIR").filter(|value| !value.is_empty()) {
        Some(value) => PathBuf::from(value),
        None => xdg("XDG_STATE_HOME", ".local/state").join("token-review"),
    }
}

pub fn stack_state_dir() -> Option<PathBuf> {
    env::var_os("CC_OBS_STACK_STATE_DIR")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
}

/// Shape written by the observability stack's disk guard. Parsing checks the whole shape;
/// only `state` and the byte counts are read afterwards.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
#[allow(dead_code)]
struct Guard {
    state: String,
    used_bytes: u64,
    cap_bytes: u64,
    updated: String,
    notified: Option<String>,
}

pub fn stack_line(state: &Path) -> Option<String> {
    let text = fs::read_to_string(state.join("guard.json")).ok()?;
    let guard: Guard = serde_json::from_str(&text).ok()?;
    if guard.state != "over" {
        return None;
    }
    let used = gb_one_decimal(guard.used_bytes)?;
    let cap = gb_one_decimal(guard.cap_bytes)?;
    Some(format!(
        "observability stack over its disk budget: {used} of {cap} GB (data kept, ingestion not stopped)"
    ))
}

/// Rounds half up to one decimal place of GB (10^9 bytes), in integer tenths.
fn gb_one_decimal(bytes: u64) -> Option<String> {
    let tenths = bytes
        .saturating_add(GB_TENTH_BYTES / 2)
        .checked_div(GB_TENTH_BYTES)?;
    Some(format!(
        "{}.{}",
        tenths.checked_div(10)?,
        tenths.checked_rem(10)?
    ))
}

pub fn notice_line(state: &Path) -> Option<String> {
    let findings = state.join("findings");
    let newest = fs::read_dir(&findings)
        .ok()?
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.extension().is_some_and(|ext| ext == "md") && path.is_file())
        .max()?;
    let name = newest.file_name()?.to_str()?;
    let marked = ["promoted", "dismissed"]
        .iter()
        .any(|marker| findings.join(format!("{name}.{marker}")).exists());
    if marked {
        return None;
    }
    let text = fs::read_to_string(&newest).ok()?;
    let id = match review_id(&text) {
        Some(id) => id,
        None => newest.file_stem()?.to_str()?.to_owned(),
    };
    Some(format!("token review ready: {id}"))
}

fn review_id(text: &str) -> Option<String> {
    let mut lines = text.lines();
    if lines.next()? != "---" {
        return None;
    }
    for line in lines {
        if line == "---" {
            return None;
        }
        if let Some(value) = line.strip_prefix("review:") {
            let value = value.trim().trim_matches(|c| c == '"' || c == '\'');
            return (!value.is_empty()).then(|| value.to_owned());
        }
    }
    None
}
