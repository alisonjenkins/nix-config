# ADR 0003: Implement `reduce::diff` fully, defer its CLI wiring

## Status

Accepted

## Context

`--mode diff` (baseline-window vs. current-window comparison, e.g. "did
the mix of error types change vs. an hour ago") needs two fetches: the
current `--since` window and a `--baseline` window ending where the
current window begins. Every other mode (`aggregate`/`topn`/`histogram`)
needs exactly one fetch, which is what `main.rs`'s single `query_window()`
+ single `platform::*::fetch()` call currently produces.

Wiring a genuine two-window query changes `QueryArgs`/`emit()`'s shape
(two fetches, two time ranges, a decision on whether both windows share
`--url`/`--query` or need independent flags) — a small CLI design task in
its own right, not a mechanical extension of the existing one-fetch path.

## Decision

Implement and fully test `reduce::diff` (`src/reduce/diff.rs`) — the
counting/comparison logic itself has no dependency on how the two
`Vec<Event>` inputs were obtained. Leave `Mode::Diff` in `main.rs`
returning an explicit "not yet wired into the CLI" error rather than
guessing at the two-window flag design under this task's scope.

`DiffEntry` and `diff()` are marked `#[allow(dead_code)]` (scoped to
exactly those items, not the module) with a comment pointing at this ADR
and the plan's Fast-follow section, since nothing in the binary
constructs or calls them yet. `DiffResult` is re-exported from
`src/reduce/mod.rs` despite also being currently-unconstructed, because
`output.rs`'s `impl ToTable for DiffResult` needs the type name at
compile time.

## Consequences

- `sift ... --mode diff` currently exits with a clear error rather than
  panicking or silently returning wrong results — this was verified
  during Task 10's review.
- The Fast-follow task that wires this up only needs to: (1) design the
  `--baseline`-window fetch (likely a second `platform::*::fetch()` call
  using `query_window()`'s `start` as the new window's end), (2) call
  `reduce::diff(&baseline_events, &current_events, &args.group_by)`, (3)
  remove the two `#[allow(dead_code)]` attributes now that real callers
  exist. No changes to `diff.rs` itself should be needed.
