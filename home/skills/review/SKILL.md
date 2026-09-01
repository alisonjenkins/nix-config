---
name: review
description: Use when reviewing a diff, a pull request, or your own work before committing or handing it over, including "look over this change", "is this right", or checking for bugs you introduced. Also use when auditing an existing codebase or module against current conventions — "review this codebase", "does this project follow our standards", "check this against the programming skill" — with no diff to anchor against. Carries the rubric for judging code (including conformance with the `programming` skill's language and by-concern guidance), severity ordering, how to phrase a finding so it is actionable, and how to verify a finding is real before reporting it.
---

# Review

## Before reporting anything

A finding must be **verified**, not merely plausible. For each candidate,
construct the concrete failure: the inputs or state, and the wrong output or
crash that follows. If you cannot construct it, you have a question, not a
finding; ask it as a question.

Ranked most severe first. Correctness beats style, always.

## Standard to judge against

Load the `programming` skill before judging anything: its general rules,
the per-language file for whatever language is under review, and whichever
by-concern files apply to what the code does (`defensive.md` for input and
error paths, `concurrency.md` for anything threaded or async, `security.md`
for untrusted input or secrets, `observability.md` for logging/tracing,
`performance.md` for a claimed optimisation, SIMD, or a benchmark). A
convention documented there — no `unwrap()` outside tests, one error enum
per fallible function, structured log fields, profile-then-benchmark before
a perf change — is not a style opinion to weigh against taste; treat a
violation of it the same as any other rubric finding, at the severity the
violated rule implies (a missing error-context propagation is Correctness or
Boundaries, not Simplification).

This applies whether the code under review arrived as a diff or already
existed before these rules were written — see
[codebase-audit.md](codebase-audit.md) for reviewing existing code with no
diff to anchor against.

## Rubric

1. **Correctness**: does it do what it claims for the inputs it will actually
   see? Off-by-one, wrong operator, unhandled `None`/`Err`, inverted
   condition, resource leak, race.
2. **Boundaries**: untrusted input parsed without validation, errors
   swallowed, external calls that are not idempotent or not retried.
3. **Design**: is what this leaves behind easier to change than what it
   replaced? Logic placed where the data was convenient rather than where the
   responsibility is, a boolean parameter that switches behaviour, a caller
   that has to know the callee's internal states, new global or shared mutable
   state, a vendor's types leaking into domain code. Judged against the
   `design` skill, not restated here.
4. **Scope**: does the diff do more than the change requires? Unrelated
   refactors, silently widened behaviour, dead code left behind.
5. **Reuse**: does this duplicate something the codebase already has?
6. **Simplification**: is there a materially simpler shape with the same
   behaviour? Not stylistic preference; structural reduction.
7. **Efficiency**: only where it matters: work inside a loop that belongs
   outside it, an N+1 query, an unbounded buffer.
8. **Test coverage**: is the new behaviour actually pinned by a test that
   would fail without the change?

## Phrasing a finding

One line, three parts: **where**, **what is wrong**, **what to do**.

    src/auth.rs:88: expiry check uses `<` so a token expiring exactly now is
    accepted; use `<=`.

No preamble, no praise sandwich, no restating the code. If nothing is wrong,
say so in one line rather than manufacturing findings.

## Routing

| Reviewing | Read |
|---|---|
| An uncommitted or unpushed diff, including your own | [diff-review.md](diff-review.md) |
| A pull request, with comments to post | [pr-review.md](pr-review.md) |
| An existing codebase or module, with no diff to anchor against — checking it against current conventions | [codebase-audit.md](codebase-audit.md) |

Receiving review on a PR of your own is the other direction; that is the
`git` skill's `pr-review-responses.md`, not this one.

The bundled `/code-review` command runs a deeper multi-pass review with
verification; prefer it for a whole branch or PR rather than reimplementing it.
