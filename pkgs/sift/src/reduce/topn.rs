use crate::event::Event;
use serde::Serialize;
use std::collections::BTreeMap;

#[derive(Debug, Serialize, PartialEq, Clone)]
pub struct TopNEntry {
    pub key: String,
    pub count: usize,
}

#[derive(Debug, Serialize, PartialEq)]
pub struct TopNResult {
    pub entries: Vec<TopNEntry>,
    pub total: usize,
}

pub fn topn(events: &[Event], group_by: &str, n: usize) -> TopNResult {
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
    let total = events.len();

    let mut entries: Vec<TopNEntry> = counts
        .into_iter()
        .map(|(key, count)| TopNEntry { key, count })
        .collect();
    entries.sort_by(|a, b| b.count.cmp(&a.count).then_with(|| a.key.cmp(&b.key)));
    entries.truncate(n);

    TopNResult { entries, total }
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
    fn returns_the_n_most_frequent_keys_in_descending_order() {
        let events = vec![
            event_with_label("service", "a"),
            event_with_label("service", "a"),
            event_with_label("service", "a"),
            event_with_label("service", "b"),
            event_with_label("service", "b"),
            event_with_label("service", "c"),
        ];

        let result = topn(&events, "service", 2);

        assert_eq!(
            result.entries,
            vec![
                TopNEntry { key: "a".to_string(), count: 3 },
                TopNEntry { key: "b".to_string(), count: 2 },
            ]
        );
        assert_eq!(result.total, 6);
    }

    #[test]
    fn ties_break_by_key_for_deterministic_output() {
        let events = vec![
            event_with_label("service", "b"),
            event_with_label("service", "a"),
        ];

        let result = topn(&events, "service", 2);

        assert_eq!(result.entries[0].key, "a");
        assert_eq!(result.entries[1].key, "b");
    }
}
