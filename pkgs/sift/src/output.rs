use crate::reduce::{AggregateResult, DiffResult, HistogramResult, TopNResult};
use serde::Serialize;

pub trait ToTable {
    fn to_table(&self) -> String;
}

impl ToTable for AggregateResult {
    fn to_table(&self) -> String {
        let mut out = String::new();
        for (key, count) in &self.counts {
            out.push_str(&format!("{count:>8}  {key}\n"));
        }
        out.push_str(&format!("{:>8}  TOTAL\n", self.total));
        out
    }
}

impl ToTable for TopNResult {
    fn to_table(&self) -> String {
        let mut out = String::new();
        for entry in &self.entries {
            out.push_str(&format!("{:>8}  {}\n", entry.count, entry.key));
        }
        out.push_str(&format!("{:>8}  TOTAL (all keys)\n", self.total));
        out
    }
}

impl ToTable for HistogramResult {
    fn to_table(&self) -> String {
        let mut out = String::new();
        for bucket in &self.buckets {
            out.push_str(&format!("{:>8}  {}\n", bucket.count, bucket.bucket_start));
        }
        out
    }
}

impl ToTable for DiffResult {
    fn to_table(&self) -> String {
        let mut out = String::new();
        for entry in &self.entries {
            out.push_str(&format!(
                "{:>+8}  {} (baseline {} -> current {})\n",
                entry.delta, entry.key, entry.baseline_count, entry.current_count
            ));
        }
        out
    }
}

pub fn format_json<T: Serialize>(result: &T) -> Result<String, serde_json::Error> {
    serde_json::to_string_pretty(result)
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]
    use super::*;
    use std::collections::BTreeMap;

    #[test]
    fn aggregate_table_lists_each_key_with_its_count_and_a_total_line() {
        let mut counts = BTreeMap::new();
        counts.insert("timeout".to_string(), 2usize);
        counts.insert("not_found".to_string(), 1usize);
        let result = AggregateResult { counts, total: 3 };

        let table = result.to_table();

        assert!(table.contains("2"));
        assert!(table.contains("timeout"));
        assert!(table.contains("1"));
        assert!(table.contains("not_found"));
        assert!(table.contains("TOTAL"));
    }

    #[test]
    fn format_json_produces_valid_pretty_printed_json() {
        let mut counts = BTreeMap::new();
        counts.insert("timeout".to_string(), 2usize);
        let result = AggregateResult { counts, total: 2 };

        let json = format_json(&result).unwrap();
        let reparsed: serde_json::Value = serde_json::from_str(&json).unwrap();

        assert_eq!(reparsed["total"], 2);
    }
}
