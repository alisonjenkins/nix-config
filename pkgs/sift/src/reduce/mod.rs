pub mod aggregate;
pub mod diff;
pub mod histogram;
pub mod topn;

pub use aggregate::{aggregate, AggregateResult};
pub use histogram::{histogram, parse_bucket_duration, HistogramResult};
pub use topn::{topn, TopNResult};

// DiffResult is re-exported because output.rs's ToTable impl needs the
// type name; diff() and DiffEntry are not, since nothing outside
// diff.rs constructs or names them yet — the CLI has no wiring for a
// two-window (baseline + current) query (see main.rs's Mode::Diff arm
// and the sift-cli plan's Fast-follow section). Both are fully
// implemented and tested in diff.rs; only the re-export is deferred.
pub use diff::DiffResult;
