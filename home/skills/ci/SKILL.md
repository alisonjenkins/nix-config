---
name: ci
description: >-
  Use when setting up, changing or speeding up a CI pipeline: GitHub Actions workflows, the PR check, required status checks, how tests run in CI, retries and flaky CI jobs, caching (actions/cache, sccache, Nix binary cache), path filters, running only affected tests, sharding, and incremental mutation testing in CI. Not for fixing one flaky test's code (see testing) or auditing branch protection (see repo-audit).
metadata:
  summary: "Use when setting up or speeding up CI: GitHub Actions, PR checks, caching, path filters, affected tests, flaky CI jobs, mutation testing in CI."
---

# CI

A CI pipeline exists to answer one question per change: is it safe to merge?
Every rule below serves one of three properties:

1. **Trustworthy.** Red means broken and green means fine. A check that is
   sometimes red for no reason teaches people to re-run until green, and then
   it proves nothing.
2. **Fast.** Feedback arrives while the author still has the change in their
   head. Under ~10 min for the PR check is a good target.
3. **Cheap.** It does not repeat work whose answer cannot have changed.

When they conflict, trust wins. Skipping work is only allowed when the skip
is provably safe. When in doubt, run it.

## Rules that hold everywhere

- **CI runs the same entrypoint a developer runs locally.** One command
  (`just check`, `make test`, a script under `.github/scripts/`) holds the
  logic. The workflow YAML only sets up the machine and calls it. Logic
  buried in YAML cannot be run, tested or bisected locally.
- **The gate's own logic is code, with tests.** A path filter or affected-test
  selector that skips too much fails silently. Test it like any other code
  (see `testing`).
- **One required check per branch.** Branch protection requires a single
  aggregator job that always reports, whatever was skipped. Requiring each
  job by name breaks when a job is skipped or renamed (see `repo-audit`'s
  `branch-protection.md`).
- **Every job has a timeout**, and so does every test that awaits I/O. A hang
  must fail fast and say where it hung, not burn the job limit.
- **Cancel superseded runs** (`concurrency:` with `cancel-in-progress: true`
  on PR workflows, never on the default branch's deploy).
- **A failure names its cause.** Print each section's log as it finishes, not
  all at the end, so a timeout still shows what passed.
- **Least privilege.** `permissions: contents: read` at the workflow level;
  grant writes per job. Fork PRs get no secrets and no cache writes.
- **Measure before optimising.** Read the job timings of a recent run, then
  cut the largest section. Record the before and after numbers.

## Routing

| Working on | Read |
|---|---|
| What the PR check runs, test commands in CI, ordering, timeouts, sharding, reporting | [running-tests.md](running-tests.md) |
| Flaky jobs, retries, quarantine, infra failures vs test failures | [reliability.md](reliability.md) |
| Cache keys, dependency and build caches, sccache, Nix binary cache, cache poisoning | [caching.md](caching.md) |
| Path filters, only running affected tests, skipping unchanged work, incremental mutation testing | [scoping.md](scoping.md) |

## Related skills

- `testing`: how to write the tests CI runs, per language, and fixing one
  flaky test's code.
- `repo-audit`: audits branch protection, workflow permissions and basic
  caching across a repo. `/ci-audit` audits a repo's CI against this skill.
- `infra`: anything CI deploys.
- `debugging`: a CI failure that does not reproduce locally.
