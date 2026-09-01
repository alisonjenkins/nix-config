use crate::event::Event;
use serde::Serialize;
use std::collections::BTreeMap;

// Not yet wired into the CLI (no two-window query support in main.rs
// yet — see reduce/mod.rs's comment and the sift-cli plan's Fast-follow
// section), so nothing in this binary currently constructs these or
// calls diff(). Fully implemented and tested; the dead-code allow is
// scoped to exactly these three items, not the module, so the compiler
// will flag anything genuinely new left unused.
#[allow(dead_code)]
#[derive(Debug, Serialize, PartialEq, Clone)]
pub struct DiffEntry {
    pub key: String,
    pub baseline_count: usize,
    pub current_count: usize,
    pub delta: i64,
}

#[allow(dead_code)]
#[derive(Debug, Serialize, PartialEq)]
pub struct DiffResult {
    pub entries: Vec<DiffEntry>,
}

#[allow(dead_code)]
pub fn diff(baseline: &[Event], current: &[Event], group_by: &str) -> DiffResult {
    let count_by = |events: &[Event]| -> BTreeMap<String, usize> {
        let mut counts: BTreeMap<String, usize> = BTreeMap::new();
        for event in events {
            let key = event
                .labels
                .get(group_by)
                .cloned()
                .unwrap_or_else(|| "<missing>".to_string());
            let entry = counts.entry(key).or_insert(0);
            *entry = entry.saturating_add(1);
        }
        counts
    };

    let baseline_counts = count_by(baseline);
    let current_counts = count_by(current);

    let mut keys: Vec<&String> = baseline_counts
        .keys()
        .chain(current_counts.keys())
        .collect();
    keys.sort();
    keys.dedup();

    let entries = keys
        .into_iter()
        .filter_map(|key| {
            let baseline_count = baseline_counts.get(key).copied().unwrap_or(0);
            let current_count = current_counts.get(key).copied().unwrap_or(0);
            if baseline_count == current_count {
                return None;
            }
            #[allow(clippy::arithmetic_side_effects)] // counts come from Vec::len()-bounded BTreeMap entries, cast to i64 stays far below overflow for any real query result.
            let delta = current_count as i64 - baseline_count as i64;
            Some(DiffEntry {
                key: key.clone(),
                baseline_count,
                current_count,
                delta,
            })
        })
        .collect();

    DiffResult { entries }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]
    use super::*;
    use chrono::Utc;

    fn event_with_label(key: &str, value: &str) -> Event {
        let mut labels = BTreeMap::new();
        labels.insert(key.to_string(), value.to_string());
        Event {
            timestamp: Utc::now(),
            labels,
            value: None,
            body: None,
        }
    }

    #[test]
    fn surfaces_only_keys_whose_count_changed() {
        let baseline = vec![
            event_with_label("error_type", "timeout"),
            event_with_label("error_type", "not_found"),
        ];
        let current = vec![
            event_with_label("error_type", "timeout"),
            event_with_label("error_type", "timeout"),
            event_with_label("error_type", "timeout"),
            event_with_label("error_type", "not_found"),
        ];

        let result = diff(&baseline, &current, "error_type");

        assert_eq!(result.entries.len(), 1);
        assert_eq!(result.entries[0].key, "timeout");
        assert_eq!(result.entries[0].baseline_count, 1);
        assert_eq!(result.entries[0].current_count, 3);
        assert_eq!(result.entries[0].delta, 2);
    }

    #[test]
    fn a_key_present_only_in_current_shows_as_a_new_increase() {
        let baseline: Vec<Event> = vec![];
        let current = vec![event_with_label("error_type", "new_kind")];

        let result = diff(&baseline, &current, "error_type");

        assert_eq!(result.entries.len(), 1);
        assert_eq!(result.entries[0].baseline_count, 0);
        assert_eq!(result.entries[0].current_count, 1);
        assert_eq!(result.entries[0].delta, 1);
    }
}
