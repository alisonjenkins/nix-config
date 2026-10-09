use serde_json::json;

use crate::bounds::Report;
use crate::pack::Pack;

/// Collected signals no question uses and `retire:` does not list; a non-empty
/// answer fails the check.
pub fn run(pack: &Pack) -> Report {
    let unused = pack.unused();
    let mut report = Report::new("unused-signals")
        .with("pack_version", json!(pack.version))
        .with("unused", json!(unused.len()));
    report.rows = unused.iter().map(|s| json!({"key": s})).collect();
    report.failed = !unused.is_empty();
    report
}
