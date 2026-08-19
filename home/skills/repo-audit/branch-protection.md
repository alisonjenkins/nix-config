# Branch protection & repo settings

Run via `scripts/checks/branch-protection.sh <target>`.

## Criteria

- Required PR reviews on the default branch (at least one approving review).
- Required status checks configured, and the check names actually match jobs
  that exist in the repo's current CI workflow — a required check pointing at
  a renamed or deleted job is a silent no-op, worse than no requirement.
- Force-push disabled on the default branch.
- Branch deletion protection enabled on the default branch.
- Merge-strategy policy (squash / rebase / merge-commit) is **reported, not
  enforced** — that's a repo-owner judgment call, not a hygiene defect.

## GitHub

`gh api repos/{owner}/{repo}/branches/{branch}/protection` — compare
`required_pull_request_reviews`, `required_status_checks.contexts`,
`allow_force_pushes.enabled` (must be `false`), and repo-level
`delete_branch_on_merge` / branch deletion rules.

Cross-check required status check names against
`gh api repos/{owner}/{repo}/actions/workflows` job names — a mismatch is a
finding even if protection is otherwise configured correctly.

## GitLab

Not implemented in v1 — `forge_get_branch_protection` in `lib/gitlab.sh`
returns "not implemented"; the check reports "unsupported forge" for this
topic rather than erroring.

## Fixing

`--fix` calls `forge_set_branch_protection` with the missing settings, one
finding at a time, after an explicit y/n confirmation showing the exact API
payload about to be sent.
