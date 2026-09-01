use chrono::{DateTime, Utc};
use std::collections::BTreeMap;

/// A single unit of observability data — a log line, a metric sample —
/// normalized to one shape so the reduction engine doesn't need to know
/// which platform or signal type produced it.
#[derive(Debug, Clone, PartialEq)]
pub struct Event {
    pub timestamp: DateTime<Utc>,
    /// Grouping dimensions: Loki stream labels, Prometheus metric
    /// labels, or fields parsed out of a log line.
    pub labels: BTreeMap<String, String>,
    /// A numeric sample value, when this event represents a metric
    /// point rather than a log line.
    pub value: Option<f64>,
    /// The raw log line text, when this event represents a log rather
    /// than a metric point.
    pub body: Option<String>,
}
