use crate::event::Event;
use serde::Serialize;
use std::collections::BTreeMap;

#[derive(Debug, Serialize, PartialEq)]
pub struct AggregateResult {
    pub counts: BTreeMap<String, usize>,
    pub total: usize,
}

pub fn aggregate(events: &[Event], group_by: &str) -> AggregateResult {
    let mut counts: BTreeMap<String, usize> = BTreeMap::new();
    for event in events {
        let key = event
            .labels
            .get(group_by)
            .cloned()
            .unwrap_or_else(|| "<missing>".to_string());
        *counts.entry(key).or_insert(0) += 1;
    }
    let total = events.len();
    AggregateResult { counts, total }
}

#[cfg(test)]
mod tests {
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
    fn groups_events_by_label_value() {
        let events = vec![
            event_with_label("error_type", "timeout"),
            event_with_label("error_type", "timeout"),
            event_with_label("error_type", "not_found"),
        ];

        let result = aggregate(&events, "error_type");

        assert_eq!(result.counts.get("timeout"), Some(&2));
        assert_eq!(result.counts.get("not_found"), Some(&1));
        assert_eq!(result.total, 3);
    }

    #[test]
    fn events_missing_the_label_group_under_a_sentinel() {
        let events = vec![event_with_label("other_key", "x")];

        let result = aggregate(&events, "error_type");

        assert_eq!(result.counts.get("<missing>"), Some(&1));
    }
}
