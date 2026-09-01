# ADR 0002: MVP scope is Loki + Prometheus/Mimir; Datadog and Tempo deferred

## Status

Accepted

## Context

The user's stated platforms are Datadog (current, at work) and the Grafana
LGTM stack plus directly-run Prometheus (personal servers, heavy current
use). Building fetch/parse/reduce support for every platform and every
signal type (logs, metrics, traces) in one pass would multiply the plan's
task count and push the first usable release out significantly.

## Decision

Ship the MVP covering exactly two platforms' two signal types: Loki logs
(`sift lgtm logs`) and Prometheus/Mimir metrics (`sift lgtm metrics`).
Datadog (all signals), Tempo traces, and `diff` mode's CLI wiring (the
`reduce::diff` logic itself is fully implemented — see ADR 0003) are
explicit Fast-follow items, tracked in
`docs/superpowers/plans/2026-09-01-sift-cli.md`, not silently dropped.

Loki + Prometheus/Mimir were chosen as the MVP because personal-server use
is active today ("we need coverage now"), giving a real place to dogfood
the tool immediately, whereas Datadog is a possible future migration
target at work.

## Consequences

- `sift`'s `Platform`/`LgtmSignal` enum in `src/cli.rs` is deliberately
  shaped to grow a `Datadog { signal }` arm later without restructuring
  the `Lgtm { signal }` arm.
- The `observability` skill's `platforms/datadog.md` currently documents
  the `pup` CLI and manual investigation method only — it cannot yet
  point at `sift` for Datadog the way `platforms/grafana-lgtm.md` does
  for Loki/Prometheus. That asymmetry is expected until the Fast-follow
  lands.
- Anyone extending `sift` to Datadog should read this ADR and ADR 0001
  first: the shared reduction layer should not need to change, only a
  new `src/platform/datadog.rs` and a new CLI subcommand arm.
