# Auditing an existing codebase

Most existing code predates the current `programming` guidance, and there
is no diff to check against the rules. Unlike `diff-review.md`, there is no
author intent to read against, only the code as it stands, judged against
the conventions that apply now.

## Scope before reading

Pick the boundary before starting (whole repo, one crate/package, one
directory) and say what it is. "Audit the codebase" with no scope yields a
shallow pass over everything or an exhaustive one that never finishes.
Identify the languages present and load each matching per-language file
from `programming`, plus the by-concern files for what the code does (a
service with no threads does not need `concurrency.md`; anything parsing
external input needs `security.md` and `defensive.md`).

## Run the mechanical pass first

Most of a per-language file's "Guard rails" section is a lint or compiler
flag, not a judgment call; run it before reading by hand:

- Rust: `cargo clippy --all-targets -- -D warnings` with the project's
  current `[lints.clippy]` table (or lack of one — a missing guard-rail
  table is itself a finding, see `programming/languages/rust.md`).
- Python: `mypy --strict` (or the project's current mode), `ruff check`.
- TypeScript: `tsc --noEmit` with the project's current `tsconfig.json`
  strictness, the linter.
- Shell: `shellcheck` on every script.

A clean run does not mean the code follows the guidance: a project with no
`[lints.clippy]` table passes `clippy` while full of unguarded `unwrap()`.
It means the *mechanically checkable* half is covered before the manual
pass.

## What to actually look for

Read for the same rubric as any other review (`SKILL.md`), applied to
existing code instead of new lines, weighted toward what a lint cannot catch:

- **Guard rails not yet turned on**: no `[lints.clippy]` deny table, no
  `mypy --strict`, no `noUncheckedIndexedAccess` — one-line additions with
  many downstream findings once enabled; report the gap itself, not just
  the violations it would surface.
- **Error handling**: swallowed errors, a broad catch with no re-raise, a
  library returning `Result`/exceptions with no context at the point they're
  first handled — the `defensive.md` and per-language error-handling idioms.
- **Observability**: a service or long-running process with no structured
  logging, or logging free-text sentences instead of fields, or no
  correlation ID threading a request through multiple functions —
  `observability.md`.
- **Unmeasured performance claims**: a comment or commit claiming
  "optimized" or "faster" with no benchmark, a hand-rolled `time.time()`
  loop instead of a real harness, SIMD or manual vectorization with no
  comment on the aliasing/alignment assumption that makes it sound —
  `performance.md`.
- **Domain primitives collapsed into bare types** — `defensive.md`'s
  "distinct domain concepts" rule and its per-language mechanism.

## Reporting without drowning the reader

An established codebase can produce hundreds of instances of one gap (a
thousand `unwrap()` calls, no crate with a lint table). One finding per
occurrence buries the few urgent ones and makes the report unusable.

- **Group by rule, not by occurrence.** One finding: "no `[lints.clippy]`
  deny table in any of the 6 crates; `rg -c 'unwrap\(\)' src/ | awk -F:
  '{s+=$2} END {print s}'` shows 340 call sites (summed across files) that
  would need triage once it's added" — not 340 findings.
- **Severity still applies** (see `SKILL.md`'s rubric ordering): a systemic
  gap in error handling on a request path ranks above a missing newtype on
  an internal helper.
- **Distinguish "fix now" from "known debt."** Not everything has to be
  fixed in one pass: `programming`'s "don't live with broken windows" means
  not stepping over it silently, not rewriting a legacy codebase in one
  sitting. Say which findings block shipping today and which deserve a
  tracked follow-up, and let the user decide the backlog. Do not silently
  downgrade a real defect to "someday," and do not open a tracking issue on
  your own initiative; the `git` skill's `pr-review-responses.md` "correct
  but out of scope" handling applies here too.
