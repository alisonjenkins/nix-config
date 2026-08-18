---
name: review
description: Use when reviewing a diff, a pull request, or your own work before committing or handing it over — including "look over this change", "is this right", or checking for bugs you introduced. Carries the rubric for judging a diff, severity ordering, how to phrase a finding so it is actionable, and how to verify a finding is real before reporting it.
---

# Review

## Before reporting anything

A finding must be **verified**, not merely plausible. For each candidate,
construct the concrete failure: the inputs or state, and the wrong output or
crash that follows. If you cannot construct it, you have a question, not a
finding — ask it as a question.

Ranked most severe first. Correctness beats style, always.

## Rubric

1. **Correctness** — does it do what it claims for the inputs it will actually
   see? Off-by-one, wrong operator, unhandled `None`/`Err`, inverted
   condition, resource leak, race.
2. **Boundaries** — untrusted input parsed without validation, errors
   swallowed, external calls that are not idempotent or not retried.
3. **Design** — is what this leaves behind easier to change than what it
   replaced? Logic placed where the data was convenient rather than where the
   responsibility is, a boolean parameter that switches behaviour, a caller
   that has to know the callee's internal states, new global or shared mutable
   state, a vendor's types leaking into domain code. Judged against the
   `design` skill, not restated here.
4. **Scope** — does the diff do more than the change requires? Unrelated
   refactors, silently widened behaviour, dead code left behind.
5. **Reuse** — does this duplicate something the codebase already has?
6. **Simplification** — is there a materially simpler shape with the same
   behaviour? Not stylistic preference; structural reduction.
7. **Efficiency** — only where it matters: work inside a loop that belongs
   outside it, an N+1 query, an unbounded buffer.
8. **Test coverage** — is the new behaviour actually pinned by a test that
   would fail without the change?

## Phrasing a finding

One line, three parts: **where**, **what is wrong**, **what to do**.

    src/auth.rs:88 — expiry check uses `<` so a token expiring exactly now is
    accepted; use `<=`.

No preamble, no praise sandwich, no restating the code. If nothing is wrong,
say so in one line rather than manufacturing findings.

## Routing

| Reviewing | Read |
|---|---|
| An uncommitted or unpushed diff, including your own | [diff-review.md](diff-review.md) |
| A pull request, with comments to post | [pr-review.md](pr-review.md) |

The bundled `/code-review` command runs a deeper multi-pass review with
verification; prefer it for a whole branch or PR rather than reimplementing it.
