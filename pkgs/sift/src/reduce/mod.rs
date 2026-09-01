pub mod aggregate;
pub mod topn;

pub use aggregate::{aggregate, AggregateResult};
pub use topn::{topn, TopNEntry, TopNResult};
