# CI pipeline health

Run via `scripts/checks/ci-pipeline.sh <target>`.

## Criteria

- Every required branch-protection status check (see `branch-protection.md`)
  corresponds to a job that actually exists in the current CI config — checked
  both directions: no stale required check, and no CI job that plainly should
  be required but isn't.
- Workflow permissions are least-privilege: no default `permissions:
  write-all` at the workflow level; jobs that don't need write access declare
  `contents: read` explicitly rather than inheriting an org-wide default.
- Basic caching present for the ecosystem in use (e.g. `actions/cache` or a
  language-specific cache action for Go modules/npm/Cargo; Nix builds caching
  via a binary cache or `cachix`/`niks3`-style push, matching this repo's own
  `build-and-cache.yaml` pattern).
- At least one workflow triggers on `pull_request` (or `pull_request_target`).
  A repo whose CI is entirely push/tag/schedule/dispatch-triggered — this
  repo's own state before `pr-check.yaml` was added — can never satisfy a
  required status check on a PR, which silently breaks both branch protection
  and Renovate automerge-on-green: they'd wait forever on a status that never
  reports, not fail loudly. Caught this the hard way while wiring up
  `dependency-updates.md`'s automerge requirement.

## GitHub

Reads `.github/workflows/*.yaml` and `.github/workflows/*.yml`, plus
`gh api repos/{owner}/{repo}/branches/{branch}/protection` for the required
checks list (shared read with `branch-protection.sh`, not re-fetched).

## GitLab

`.gitlab-ci.yml` equivalent checks (job names, `permissions`-equivalent via
CI/CD job token scoping) — v1 stub, reports "unsupported forge" for the
GitLab-specific pieces; the file-presence/caching heuristics that only need
the YAML (not a forge API) still run.

## Fixing

`--fix` proposes adding `permissions: contents: read` at the workflow level
and adding a cache step for the detected ecosystem, each shown as a diff and
confirmed individually. It does not add or remove required-status-check
entries itself — that's `branch-protection.sh`'s job; this check only flags
the mismatch.
