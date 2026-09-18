# CI pipeline health

Run via `scripts/checks/ci-pipeline.sh <target>`.

## Criteria

- Every required branch-protection status check (see `branch-protection.md`)
  matches a job in the current CI config, checked both directions: no stale
  required check, no CI job that plainly should be required but isn't.
- Workflow permissions are least-privilege: no `permissions: write-all` at
  the workflow level; jobs that don't need write access declare
  `contents: read` rather than inheriting an org-wide default.
- Basic caching for the ecosystem in use (e.g. `actions/cache` or a
  language-specific cache action for Go modules/npm/Cargo; Nix via a binary
  cache or a `cachix`/self-hosted-push workflow).
- At least one workflow triggers on `pull_request` (or `pull_request_target`).
  CI that is entirely push/tag/schedule/dispatch-triggered can never satisfy a
  required status check on a PR, which silently breaks branch protection and
  Renovate automerge-on-green: they wait forever on a status that never
  reports instead of failing loudly.

## GitHub

Reads `.github/workflows/*.yaml` and `.github/workflows/*.yml`, plus
`gh api repos/{owner}/{repo}/branches/{branch}/protection` for the required
checks list (shared read with `branch-protection.sh`, not re-fetched).

## Fixing

`--fix` proposes `permissions: contents: read` at the workflow level and a
cache step for the detected ecosystem, each shown as a diff and confirmed
individually. It does not add or remove required-status-check entries; that
is `branch-protection.sh`'s job, this check only flags the mismatch.
