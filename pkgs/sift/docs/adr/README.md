# Architecture Decision Records — sift

Lightweight (MADR-style) ADRs for load-bearing decisions made while
designing and implementing `sift`. Scoped to this package, not the whole
repo — see `docs/superpowers/specs/2026-09-01-observability-skill-design.md`
and `docs/superpowers/plans/2026-09-01-sift-cli.md` for the design spec
and implementation plan these decisions came out of.

- [0001: Single unified CLI, shared reduction logic, Rust](0001-single-unified-cli-in-rust.md)
- [0002: MVP scope is Loki + Prometheus/Mimir; Datadog and Tempo deferred](0002-lgtm-first-scope.md)
- [0003: Implement `reduce::diff` fully, defer its CLI wiring](0003-diff-mode-logic-without-cli-wiring.md)
- [0004: Deny unwrap/expect/panic; one error enum per fallible function in the platform/reduce layers](0004-strict-error-handling-and-lint-policy.md)
- [0005: Preserve sub-second timestamp precision per platform](0005-subsecond-timestamp-precision.md)
- [0006: Resolve LGTM credentials via secretspec, never as a raw CLI value](0006-secretspec-credential-resolution.md)
- [0007: TTL'd local caching for resolved credentials, zeroized in memory](0007-credential-caching-and-memory-hygiene.md)
