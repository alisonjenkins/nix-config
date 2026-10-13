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
