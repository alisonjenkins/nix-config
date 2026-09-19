---
name: testing
description: Use when adding or changing a test, fixing a failing or flaky test, deciding whether something is testable, or verifying a change by running its tests before saying it works. Not for verifying a fix to already-running software (see debugging). Covers cargo test, pytest, vitest/jest, nix flake check, NixOS VM tests, bats, go test. Carries the TDD loop, mocking policy, property-based testing.
---

# Testing

## The loop

1. Write the test first, and **watch it fail for the right reason**. A test
   that passes before the implementation exists is testing nothing.
2. Write the smallest implementation that makes it pass.
3. Refactor with the test green.

The full TDD workflow lives in `superpowers:test-driven-development`; invoke
that skill. This file covers what to test and how to judge a test.

## What testing is for

**Not finding bugs.** Testing catches bugs; it is *for* design feedback. Hard
to test means something structural: too many collaborators, hidden state, work
fused to I/O. Fix the code, not the test. Elaborate setup is a design finding.
The `design` skill covers what to do about it.

Three consequences:

- **A test is the first user of your code.** Write the call site you wish
  existed, then make it exist. An API that is awkward from a test is awkward
  from everywhere.
- **Design to test.** Testability is a design constraint, not a retrofit.
  Injecting the clock, the RNG and the I/O boundary costs nothing up front and
  is expensive to add later.
- **Find bugs once.** Any bug a human had to find gets a test that would have
  caught it, before the fix lands. Finding it twice means the first fix bought
  nothing.

## What makes a test worth having

- **It fails when the behaviour breaks, and only then.** A test that also
  fails on unrelated refactors is a maintenance tax, not a safety net.
- **It tests behaviour at a boundary you actually promise**, not internal
  structure. Asserting on a private helper freezes an implementation detail.
- **The failure message identifies the bug.** If you have to attach a debugger
  to understand a red test, the assertion is too coarse.
- **It is deterministic.** No wall-clock, no network, no ordering dependence
  between test cases. Inject the clock and the RNG.
- **It covers states, not lines.** Line coverage of two booleans can hit 100%
  while three of their four combinations are never exercised. Ask which states
  and boundaries the test visits (empty, one, many, maximum, error), not what
  percentage the tool reports.

## Mocking policy

Prefer the real thing. Mock only what you cannot run: paid third-party APIs,
hardware, and genuinely slow external systems. A mock that mirrors your own
code's structure will keep passing after that code breaks.

For a client/server system, drive a real server process with a real client and
assert on the observable exchange, rather than mocking the transport on both
sides.

## Verification before claiming completion

Never report a change as working because "the code looks right". Run the test,
quote the result, and say plainly if something was skipped. Build success is
not test success, and a passing suite you did not run is not evidence. See
`superpowers:verification-before-completion`.

| Excuse | Why it doesn't hold |
|---|---|
| "The code looks right, a test would just confirm it" | Looking right and being right are exactly the gap tests exist to catch |
| "I already ran this before the last edit" | The last edit is what's unverified; re-run after every change that could affect the result |

Verifying a fix to *running* software is harder than running a test suite: the
environment must match the one the user runs, and many signals report success
while the fix never applied. The `debugging` family's `verifying-a-fix.md`
covers that case.

## Routing

| Testing | Read |
|---|---|
| Rules that must hold for *all* inputs; parsers, encoders, boundary bugs; checking the suite can go red at all | [property-based.md](property-based.md) |
| Rust (`cargo test`, `cargo nextest`) | [languages/rust.md](languages/rust.md) |
| Python (`pytest`) | [languages/python.md](languages/python.md) |
| Nix (`nix flake check`, NixOS VM tests) | [languages/nix.md](languages/nix.md) |
| TypeScript / JavaScript | [languages/typescript.md](languages/typescript.md) |
| Shell scripts (`bats`, fixture-driven fake CLIs) | [languages/shell.md](languages/shell.md) |
| Go (`go test`, `go test -race`) | [languages/go.md](languages/go.md) |
