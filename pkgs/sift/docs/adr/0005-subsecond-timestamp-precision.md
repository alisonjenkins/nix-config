# ADR 0005: Preserve sub-second timestamp precision per platform

## Status

Accepted

## Context

Loki's `/loki/api/v1/query_range` returns timestamps as nanosecond-precision
strings (e.g. `"1735689600123456789"`); Prometheus/Mimir's
`/api/v1/query_range` returns them as fractional-second floats (e.g.
`1735689600.123`). A naive parse (integer-seconds-only, or float-to-i64
truncation) silently discards sub-second precision — invisible in a table
of aggregate counts, but corrupts anything that buckets by time
(`histogram` mode) or orders events within the same second.

This was caught for Loki by a task reviewer, not self-caught during
implementation; the same precision-loss risk existed in `prometheus.rs`
and was fixed proactively there once the pattern was known, rather than
waiting for a second review finding.

## Decision

`src/platform/loki.rs`'s `parse_query_range_response` splits the
nanosecond string into whole-second and remainder-nanosecond parts using
`div_euclid`/`rem_euclid` (avoiding the `arithmetic_side_effects` deny
lint's operator-syntax trigger — see ADR 0004) and builds the `Event`
timestamp from both parts.

`src/platform/prometheus.rs`'s `parse_query_range_response` splits the
float seconds via `.trunc()`/`.fract() * 1_000_000_000.0` under a
narrowly `#[allow(clippy::arithmetic_side_effects)]`-scoped block,
justified by the bounded input range (a real query timestamp).

Both modules carry a `preserves_sub_second_timestamp_precision` regression
test.

## Consequences

- `Event.timestamp` itself carries the platform's native sub-second
  resolution end to end. `histogram` mode's bucketing
  (`src/reduce/histogram.rs`) currently buckets at whole-second
  granularity (`DateTime::timestamp()`, `Duration::as_secs()`) regardless
  of that stored precision — a real gap, not yet Fast-follow-tracked, for
  anyone building a sub-second histogram on top of `Event`.
- Any new platform module (Fast-follow: Datadog, Tempo) must check its
  API's native timestamp format for the same class of precision loss
  before assuming integer-seconds parsing is sufficient — this ADR is the
  pointer for why that check matters here.
