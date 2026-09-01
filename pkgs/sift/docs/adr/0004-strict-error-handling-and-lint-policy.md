# ADR 0004: Deny unwrap/expect/panic; one error enum per fallible function in the platform/reduce layers

## Status

Accepted

## Context

`sift` runs unattended as part of an investigation workflow — a panic mid-
query loses whatever partial reduction context existed and gives the
caller (Claude, mid-investigation) a bare stack trace instead of an
actionable message. The `programming` skill's Rust guidance calls for
error types defined per fallible function, one enum variant per distinct
failure site, so a caller can match on exactly what went wrong without
string-matching a message.

Early in implementation, `LokiError` used `#[from] reqwest::Error]` to
collapse the "request failed" and "response body read failed" sites into
one variant — a code-review finding (not self-caught) that made the
context loss concrete: both failure modes reported identically, so a
caller couldn't tell a connection failure from a truncated read.

## Decision

`Cargo.toml` carries a `[lints.clippy]` deny table: `unwrap_used`,
`expect_used`, `unwrap_in_result`, `panic`, `indexing_slicing`,
`arithmetic_side_effects`, `unreachable`, `todo`, `unimplemented`,
`get_unwrap`. Every fallible function in the platform and reduction
layers (`src/platform/*.rs`, `src/reduce/*.rs`) gets its own `thiserror`
enum with one variant per call site that can fail (`LokiError`,
`PrometheusError`, `HistogramError`, ...) — no `#[from]` collapsing two
distinct sites that happen to share an underlying error type.

`src/main.rs`'s CLI-glue functions (`query_window`, `run_loki`,
`run_prometheus`, `emit`) are the one deliberate exception: they collapse
every error into `Result<_, String>` because their only consumer is the
top-level `eprintln`-and-exit-code handler in `main()` — there is no
caller left to match on a variant. Introducing an enum there would add
ceremony without a corresponding caller to benefit from it. The policy
applies to every layer with a real caller to serve; the outermost
display boundary is exempt by design, not by oversight.

Arithmetic uses checked/saturating alternatives
(`saturating_add`/`checked_mul`/`checked_sub_signed`/`div_euclid`/
`rem_euclid`) since the deny lint only fires on operator syntax, not
method calls. `#[allow(...)]` is scoped narrowly (a single function, or a
`#[cfg(test)] mod tests` block) with a comment justifying why the
excluded case is provably safe, never applied at module or crate scope.

## Consequences

- A query failure surfaces as a specific, matchable variant
  (`LokiError::Status { status, body }` vs. `RequestFailed` vs.
  `ResponseReadFailed` vs. `MalformedTimestamp`) instead of a generic
  "something went wrong."
- New platform modules (Datadog, per ADR 0002) must follow the same
  per-site-enum shape from the start — `prometheus.rs` did this
  proactively once the pattern was established for `loki.rs`, and that
  precedent should hold for future platforms.
- `#[cfg(test)] mod tests` blocks are the one place `unwrap`/`expect`
  are allowed, via a scoped `#![allow(clippy::unwrap_used,
  clippy::expect_used, clippy::indexing_slicing[, clippy::panic])]` at
  the top of the test module — assertion failures there are the point,
  not a defect.
