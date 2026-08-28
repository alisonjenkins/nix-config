# Branch protection & repo settings

Run via `scripts/checks/branch-protection.sh <target>`.

## Criteria

- Required PR reviews on the default branch (at least one approving review):
  **skipped, not failed, on a solo repo (1 collaborator)**. GitHub does not
  count self-approval toward a required review, so
  `required_approving_review_count >= 1` on a single-collaborator repo locks
  that collaborator out of merging anything, including Renovate/Dependabot
  automerge, which has no second identity to approve it either. Required
  status checks are the real gate there instead. The check calls
  `gh api repos/{owner}/{repo}/collaborators` to decide which branch applies,
  found this the hard way applying it to a solo repo.
- Required status checks configured, and the check names actually match a
  **job id** (or `name:`) in the repo's current CI workflows, because a
  required check pointing at a renamed or deleted job is a silent no-op,
  worse than no requirement. Matched against job ids read from the workflow
  YAML, not workflow filenames: a job called `flake-check` living in
  `pr-check.yaml` is a match, not a mismatch; comparing against the filename
  was an earlier bug that flagged a correctly-configured check as stale.
- Force-push disabled on the default branch.
- Branch deletion protection enabled on the default branch.
- Merge-strategy policy (squash / rebase / merge-commit) is **reported, not
  enforced**, because that's a repo-owner judgment call, not a hygiene defect.

## GitHub

`gh api repos/{owner}/{repo}/branches/{branch}/protection`: compare
`required_pull_request_reviews`, `required_status_checks.contexts`,
`allow_force_pushes.enabled` (must be `false`), and repo-level
`delete_branch_on_merge` / branch deletion rules.

Cross-check required status check names against
`gh api repos/{owner}/{repo}/actions/workflows` job names; a mismatch is a
finding even if protection is otherwise configured correctly.

## GitLab

Not implemented in v1: `forge_get_branch_protection` in `lib/gitlab.sh`
returns "not implemented"; the check reports "unsupported forge" for this
topic rather than erroring.

## Fixing

`--fix` calls `forge_set_branch_protection` with the missing settings, one
finding at a time, after an explicit y/n confirmation showing the exact API
payload about to be sent.
