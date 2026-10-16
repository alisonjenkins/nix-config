# Rubric and standard, in full

`SKILL.md` carries the one-line form of each rubric item and the rule to load
`programming`. Read this when judging a diff and an item's one-liner leaves you
unsure what to look for.

## Standard to judge against

Load the `programming` skill before judging anything: its general rules,
the per-language file for whatever language is under review, and whichever
by-concern files apply to what the code does (`defensive.md` for input and
error paths, `concurrency.md` for anything threaded or async, `security.md`
for untrusted input or secrets, `observability.md` for logging/tracing,
`performance.md` for a claimed optimisation, SIMD, or a benchmark). A
convention documented there (no `unwrap()` outside tests, one error enum
per fallible function, structured log fields, profile-then-benchmark before
a perf change) is not a style opinion; treat a violation as any other
rubric finding, at the severity the rule implies (a missing error-context
propagation is Correctness or Boundaries, not Simplification).

This applies whether the code arrived as a diff or predates the rules; see
[codebase-audit.md](codebase-audit.md) for existing code with no diff to
anchor against.

## Rubric items with examples

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

## Phrasing a finding, worked example

    src/auth.rs:88: expiry check uses `<` so a token expiring exactly now is
    accepted; use `<=`.
