//! Byte-position comparison of two configurations.

use std::collections::BTreeSet;

use crate::snapshot::ConfigBytes;

/// Positions that change without anyone touching a setting (counters,
/// timestamps), found by comparing two reads of an untouched device.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct VolatileSet(BTreeSet<usize>);

impl VolatileSet {
    pub fn none() -> Self {
        Self::default()
    }

    pub fn from_untouched_pair(first: &ConfigBytes, second: &ConfigBytes) -> Self {
        Self(
            first
                .as_slice()
                .iter()
                .zip(second.as_slice())
                .enumerate()
                .filter(|(_, (a, b))| a != b)
                .map(|(offset, _)| offset)
                .collect(),
        )
    }

    pub fn contains(&self, offset: usize) -> bool {
        self.0.contains(&offset)
    }
}

/// A run of adjacent differing bytes that share the same volatility.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DiffRun {
    pub offset: usize,
    pub before: Vec<u8>,
    pub after: Vec<u8>,
    pub volatile: bool,
}

impl DiffRun {
    fn ends_at(&self) -> usize {
        self.offset.saturating_add(self.before.len())
    }
}

/// How much differs, for the summary line.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DiffSummary {
    pub runs: usize,
    pub bytes: usize,
    pub volatile_bytes: usize,
}

pub fn summarize(runs: &[DiffRun]) -> DiffSummary {
    let bytes_where = |keep: fn(&DiffRun) -> bool| {
        runs.iter()
            .filter(|r| keep(r))
            .fold(0usize, |total, r| total.saturating_add(r.before.len()))
    };
    DiffSummary {
        runs: runs.len(),
        bytes: bytes_where(|_| true),
        volatile_bytes: bytes_where(|r| r.volatile),
    }
}

fn hex(bytes: &[u8]) -> String {
    bytes
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect::<Vec<_>>()
        .join(" ")
}

fn plural<'a>(n: usize, one: &'a str, many: &'a str) -> &'a str {
    if n == 1 {
        one
    } else {
        many
    }
}

/// One line per run, `0x0064  00 -> 42`, then a summary line.
pub fn render_text(runs: &[DiffRun]) -> String {
    if runs.is_empty() {
        return "no differences\n".to_string();
    }
    let mut out = String::new();
    for run in runs {
        out.push_str(&format!(
            "{:#06x}  {} -> {}{}\n",
            run.offset,
            hex(&run.before),
            hex(&run.after),
            if run.volatile { "  (volatile)" } else { "" }
        ));
    }
    let s = summarize(runs);
    out.push_str(&format!(
        "{} {}, {} {}{}\n",
        s.runs,
        plural(s.runs, "run", "runs"),
        s.bytes,
        plural(s.bytes, "byte differs", "bytes differ"),
        if s.volatile_bytes > 0 {
            format!(" ({} volatile)", s.volatile_bytes)
        } else {
            String::new()
        }
    ));
    out
}

pub fn to_json(runs: &[DiffRun]) -> serde_json::Value {
    let s = summarize(runs);
    serde_json::json!({
        "runs": runs.iter().map(|r| serde_json::json!({
            "offset": r.offset,
            "before": r.before,
            "after": r.after,
            "volatile": r.volatile,
        })).collect::<Vec<_>>(),
        "differing_bytes": s.bytes,
        "volatile_bytes": s.volatile_bytes,
    })
}

/// Every position where `before` and `after` differ, grouped into runs.
/// Adjacent bytes with different volatility land in separate runs.
pub fn diff(before: &ConfigBytes, after: &ConfigBytes, volatile: &VolatileSet) -> Vec<DiffRun> {
    let mut runs: Vec<DiffRun> = Vec::new();

    for (offset, (&b, &a)) in before
        .as_slice()
        .iter()
        .zip(after.as_slice())
        .enumerate()
        .filter(|(_, (b, a))| b != a)
    {
        let is_volatile = volatile.contains(offset);
        match runs.last_mut() {
            Some(run) if run.ends_at() == offset && run.volatile == is_volatile => {
                run.before.push(b);
                run.after.push(a);
            }
            _ => runs.push(DiffRun {
                offset,
                before: vec![b],
                after: vec![a],
                volatile: is_volatile,
            }),
        }
    }
    runs
}
