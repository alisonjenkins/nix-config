---
name: review
description: >-
  Use when reviewing a diff, PR, or your own work before committing, including "look over this change", "is this right", or checking for bugs you introduced. Also for auditing an existing codebase against conventions with no diff to anchor against, and for a CVE or advisory audit of a repo's dependencies, which it routes to `security`. Not for replying to review comments or resolving threads on your own PR (see git). Carries the rubric, severity ordering, how to phrase a finding, and how to verify a finding is real before reporting it.
metadata:
  summary: "Use when reviewing a diff, PR, or your own change before committing: 'look over this', 'is this right', audit against conventions."
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
the per-language file for the language under review, and the by-concern files
that apply (`defensive.md`, `concurrency.md`, `security.md`,
`observability.md`, `performance.md`). A convention documented there is not a
style opinion; treat a violation as any other rubric finding, at the severity
the rule implies. Full wording: [rubric.md](rubric.md). For existing code with
no diff, see [codebase-audit.md](codebase-audit.md).

## Rubric

1. **Correctness**: does it do what it claims for the inputs it will see?
2. **Boundaries**: unvalidated untrusted input, swallowed errors, non-idempotent
   or unretried external calls.
3. **Design**: is what this leaves behind easier to change than what it
   replaced? Judged against the `design` skill. Examples in
   [rubric.md](rubric.md).
4. **Scope**: does the diff do more than the change requires?
5. **Reuse**: does this duplicate something the codebase already has?
6. **Simplification**: a materially simpler shape with the same behaviour;
   structural reduction, not stylistic preference.
7. **Efficiency**: only where it matters (loop-invariant work, N+1, unbounded
   buffer).
8. **Test coverage**: is the new behaviour pinned by a test that would fail
   without the change?

## Phrasing a finding

One line, three parts: **where**, **what is wrong**, **what to do**
(worked example in [rubric.md](rubric.md)).

No preamble, no praise sandwich, no restating the code. If nothing is wrong,
say so in one line rather than manufacturing findings.

## Routing

| Reviewing | Read |
|---|---|
| An uncommitted or unpushed diff, including your own | [diff-review.md](diff-review.md) |
| A pull request, with comments to post | [pr-review.md](pr-review.md) |
| An existing codebase or module, with no diff to anchor against — checking it against current conventions | [codebase-audit.md](codebase-audit.md) |
| Unsure what a rubric item covers, which programming files to load, or how to word a finding | [rubric.md](rubric.md) |
| Dependencies rather than code: CVEs and advisories in a Nix closure, a Rust lockfile, or the packages a repo defines | invoke `security` |

Receiving review on a PR of your own is the other direction; that is the
`git` skill's `pr-review-responses.md`, not this one.

The bundled `/code-review` command runs a deeper multi-pass review with
verification; prefer it for a whole branch or PR rather than reimplementing it.
