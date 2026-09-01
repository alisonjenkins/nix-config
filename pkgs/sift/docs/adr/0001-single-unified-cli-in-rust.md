# ADR 0001: Single unified CLI, shared reduction logic, Rust

## Status

Accepted

## Context

The `observability` skill (design: `docs/superpowers/specs/2026-09-01-observability-skill-design.md`)
needs a way to cut the token cost of pulling Loki/Prometheus/Datadog output
into an LLM context. Options considered:

- Guidance only (tell Claude to query narrowly) — no tooling to build.
- Real wrapper scripts, one per platform, shell-based.
- One unified CLI with shared reduction logic (aggregate/topN/histogram/diff)
  across platforms, implemented as a proper Nix package.

Language candidates for the CLI: Rust, Go, Python, shell.

## Decision

Build one CLI (`sift`) with platform-specific fetch/parse modules
(`src/platform/loki.rs`, `prometheus.rs`, ...) feeding a shared,
platform-agnostic reduction layer (`src/reduce/*`) and shared output
formatting (`src/output.rs`). Implemented in Rust, packaged via
`pkgs/sift` (`rustPlatform.buildRustPackage`, `doCheck = true` runs
`cargo test` in the Nix sandbox).

Rust over Go/Python/shell: static binary with no runtime deps to manage
on every host that needs it, a real type system for the Event/reduction
model, and `cargo test`/`clippy` integrate directly into the existing Nix
build (`doCheck`) with no extra tooling.

One CLI over per-platform scripts: aggregate/topN/histogram/diff apply
identically regardless of source (Loki log lines vs. Prometheus samples);
duplicating that logic per platform would violate DRY and double the
maintenance surface for every new reduction mode.

## Consequences

- New platforms (Datadog, Tempo) plug in as a new `src/platform/*.rs`
  module that produces `Event`s; no changes needed to `src/reduce/*` or
  `src/output.rs`.
- A single binary shape means `--mode`/`--format` flags are consistent
  across `lgtm logs` and `lgtm metrics`, and future `datadog`/`tempo`
  subcommands, rather than each platform script inventing its own flags.
- Rust's stricter error handling (see ADR 0004) has a steeper up-front
  cost per task than shell/Python would, paid once during implementation.
