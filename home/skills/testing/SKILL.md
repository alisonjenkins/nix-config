---
name: testing
description: How to test — what a good failing test looks like, the TDD loop, when a test is worth writing, mocking policy, and how to verify a change end to end before claiming it works. Routes to per-language guidance for Rust, Python, Nix, and TypeScript/JavaScript. Use when adding tests, fixing a failing test, deciding whether something is testable, or verifying a change.
---

# Testing

## The loop

1. Write the test first, and **watch it fail for the right reason**. A test
   that passes before the implementation exists is testing nothing.
2. Write the smallest implementation that makes it pass.
3. Refactor with the test green.

Discipline detail for the full TDD workflow lives in
`superpowers:test-driven-development` — invoke that skill rather than
restating it here. This file covers what to test and how to judge a test.

## What makes a test worth having

- **It fails when the behaviour breaks, and only then.** A test that also
  fails on unrelated refactors is a maintenance tax, not a safety net.
- **It tests behaviour at a boundary you actually promise**, not internal
  structure. Asserting on a private helper freezes an implementation detail.
- **The failure message identifies the bug.** If you have to attach a debugger
  to understand a red test, the assertion is too coarse.
- **It is deterministic.** No wall-clock, no network, no ordering dependence
  between test cases. Inject the clock and the RNG.

## Mocking policy

Prefer the real thing. Mock only what you cannot run: paid third-party APIs,
hardware, and genuinely slow external systems. A mock that mirrors your own
code's structure will keep passing after that code breaks.

For a client/server system, the honest test drives a real server process and a
real client and asserts on the observable exchange, rather than mocking the
transport on both sides.

## Verification before claiming completion

Never report a change as working on the strength of "the code looks right".
Run the test, quote the result, and say plainly if something was skipped.
Build success is not test success, and a passing test suite you did not run is
not evidence. See `superpowers:verification-before-completion`.

## Per-language routing

| Testing | Read |
|---|---|
| Rust (`cargo test`, `cargo nextest`) | [languages/rust.md](languages/rust.md) |
| Python (`pytest`) | [languages/python.md](languages/python.md) |
| Nix (`nix flake check`, NixOS VM tests) | [languages/nix.md](languages/nix.md) |
| TypeScript / JavaScript | [languages/typescript.md](languages/typescript.md) |
