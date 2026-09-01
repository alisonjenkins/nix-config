# Auditing an existing codebase

Most existing code predates whatever `programming` skill guidance is current
today — the rules did not exist when it was written, so "check the diff
against the rules" does not apply; there is no diff. The job here is
different from `diff-review.md`: there is no author intent to read the
change against, only the code as it stands, judged against the conventions
that apply now.

## Scope before reading

Pick the boundary explicitly before starting — a whole repo, one crate/
package, one directory — and say what it is. "Audit the codebase" with no
scope produces either a shallow pass over everything or an exhaustive pass
that never finishes; neither is useful. Identify which languages are present
and load the matching per-language file(s) from `programming` for each, plus
the by-concern files relevant to what the code actually does (a service with
no threads does not need `concurrency.md`; anything parsing external input
needs `security.md` and `defensive.md`).

## Run the mechanical pass first

Most of what a per-language file's "Guard rails" section asks for is a lint
or compiler flag, not a judgment call — run it before reading anything by
hand:

- Rust: `cargo clippy --all-targets -- -D warnings` with the project's
  current `[lints.clippy]` table (or lack of one — a missing guard-rail
  table is itself a finding, see `programming/languages/rust.md`).
- Python: `mypy --strict` (or the project's current mode), `ruff check`.
- TypeScript: `tsc --noEmit` with the project's current `tsconfig.json`
  strictness, the linter.
- Shell: `shellcheck` on every script.

A clean run does not mean the code follows the guidance — a project with no
`[lints.clippy]` table passes `clippy` cleanly while being full of
unguarded `unwrap()`. It means the *mechanically checkable* half is covered
before you spend a manual pass rediscovering it by hand.

## What to actually look for

Read for the same rubric as any other review (`SKILL.md`), applied to
existing code instead of new lines, weighted toward what a lint cannot catch:

- **Guard rails not yet turned on**: no `[lints.clippy]` deny table, no
  `mypy --strict`, no `noUncheckedIndexedAccess` — these are one-line
  additions with potentially many downstream findings once enabled; report
  the gap itself as a finding, not just the violations it would surface.
- **Error handling**: swallowed errors, a broad catch with no re-raise, a
  library returning `Result`/exceptions with no context at the point they're
  first handled — the `defensive.md` and per-language error-handling idioms.
- **Observability**: a service or long-running process with no structured
  logging, or logging free-text sentences instead of fields, or no
  correlation ID threading a request through multiple functions —
  `observability.md`.
- **Unmeasured performance claims**: a comment or commit message claiming
  something is "optimized" or "faster" with no accompanying benchmark, a
  hand-rolled `time.time()` timing loop instead of a real harness, SIMD or
  manual vectorization with no comment explaining the aliasing/alignment
  assumption that makes it sound — `performance.md`.
- **Domain primitives collapsed into bare types**: two same-typed function
  parameters that mean different things (`customer_id: str, order_id: str`)
  with nothing stopping them being swapped — `defensive.md`'s "distinct
  domain concepts" rule and its per-language mechanism.

## Reporting without drowning the reader

An established codebase can easily produce hundreds of instances of the same
gap (a thousand `unwrap()` calls, no crate has a lint table). Reporting each
occurrence as a separate finding buries the few that are genuinely urgent
under noise and makes the report unusable.

- **Group by rule, not by occurrence.** One finding: "no `[lints.clippy]`
  deny table in any of the 6 crates; `rg -c 'unwrap\(\)' src/` shows 340
  call sites that would need triage once it's added" — not 340 findings.
- **Severity still applies** (see `SKILL.md`'s rubric ordering): a systemic
  gap in error handling on a request path ranks above a missing newtype on
  an internal helper.
- **Distinguish "fix now" from "known debt."** Not everything found has to
  be fixed in the same pass — `programming`'s "don't live with broken
  windows" means not stepping over it silently, not that a legacy codebase
  must be rewritten in one sitting. Say which findings block shipping
  something today versus which are worth a tracked follow-up, and let the
  user decide the backlog; do not silently downgrade a real defect to
  "someday," and do not open a tracking issue on your own initiative — the
  same "correct but out of scope" handling the `git` skill's
  `pr-review-responses.md` uses for review findings applies here too.
