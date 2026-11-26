---
name: ci-audit
description: >-
  Audit an existing repo's CI pipeline against the ci skill and propose fixes: how tests run, flaky jobs and retries, caching, path filters and affected tests, incremental mutation testing, timeouts and the required check. Use when the user runs /ci-audit, says "audit the CI", or "audit our CI pipeline and propose fixes". Read-only until the user approves a fix; rules live in the ci skill.
argument-hint: "[path to repo, default .]"
metadata:
  summary: "Audit a repo's CI pipeline against the ci skill and propose fixes: tests, flaky jobs, caching, path filters, mutation testing."
---

# CI audit

Audit a repository's CI against the `ci` skill, then propose fixes as diffs.
Load the `ci` skill first: its four topic files are the rule set this audit
checks against.

## How to run

1. **Find the pipeline.** Target is the argument, or `.` when omitted.
   Read every workflow (`.github/workflows/*.y*ml`, `.gitlab-ci.yml`,
   `.forgejo/workflows/`), every script they call, the task runner
   (`justfile`, `Makefile`, `package.json` scripts, `flake.nix` checks) and
   any test runner config (`.config/nextest.toml`, `stryker.conf.*`,
   `pytest.ini`, `vitest.config.*`).
2. **Run the mechanical checks.** `repo-audit`'s
   `scripts/audit.sh <target> ci-pipeline` reports workflow permissions and
   missing caching; add `branch-protection` when the target is on a forge
   and `gh` is signed in. Use their findings as input, not as the whole audit.
3. **Read recent runs when available.** With `gh` signed in, list the last
   ~20 runs of the PR workflow (`gh run list --workflow <file> --limit 20
   --json conclusion,databaseId,headSha,attempt,startedAt,updatedAt`).
   Note the median duration (`updatedAt` minus `startedAt`), the slowest
   job (`gh run view <id> --json jobs`), and any run that failed then
   passed on the same `headSha` or on a later `attempt` (a flake). Skip this step offline and say so in the report.
4. **Check each area below** against its `ci` topic file.
5. **Write the report** in the format below, then stop and wait.

## What to check

| Area | Rule file | Look for |
|---|---|---|
| Entry point | `ci` SKILL.md | Logic in YAML that a developer cannot run locally; CI and local using different commands. |
| Required check | `ci` SKILL.md | Branch protection requiring many job names, or a gated job that never reports. |
| Running tests | `running-tests.md` | No job or step timeouts; watch-mode runners; floating toolchains; no machine-readable results; `fail-fast` hiding matrix results; superseded runs not cancelled. |
| Reliability | `reliability.md` | Retry loops or suite-wide auto-retry around tests; `continue-on-error` on test steps; skipped tests with no owner or issue; infra failures recorded as test failures. |
| Caching | `caching.md` | Keys without a lockfile hash; keys on the commit SHA; whole `target/` caches without a sweep; `actions/cache` of `/nix/store`; cache writes reachable from fork PRs; `pull_request_target` running PR code. |
| Scoping | `scoping.md` | Everything runs on a docs-only change; workflow-level `paths:` on a required check; a gate that skips on unknown paths; no scheduled full run behind a gate. |
| Mutation testing | `scoping.md` | No mutation testing at all; full mutation runs on every PR; per-PR runs without a clean baseline; no periodic full run. |

Only report what the evidence shows. When a check needs data you do not
have (run history, branch protection), say which data is missing rather
than guessing.

## Output format

Rank findings by impact, most severe first: HIGH (a red or green that can
lie: masked failures, retries hiding flakes, unsafe caches, skips that miss
code), then MEDIUM (wasted minutes on every PR), then LOW (hygiene). Show at
most 10 findings.

For each finding:

- **Where:** file and line, or the workflow and job name.
- **What is wrong:** one sentence, with the evidence (a line quoted, a run
  timing).
- **Rule:** the `ci` topic file it breaks.
- **Proposed fix:** a unified diff, or the exact command, small enough to
  review on its own. Give an estimate of minutes saved per run when the fix
  is a speed-up and the run history supports one.

End with the median PR-check duration (when known) and which three fixes
would cut it most.

## Guardrails

- Read-only until the user approves. Never edit, commit or push as part of
  the audit itself.
- After the report, ask which fixes to apply. Apply each approved fix as its
  own change, following the repo's commit rules (load `git` before
  committing).
- Never change branch protection, secrets, runner settings or other forge
  settings directly. Propose them, and leave the change to the user.
- Do not re-run CI jobs to test a flake theory without the user's yes; each
  run costs runner time.
