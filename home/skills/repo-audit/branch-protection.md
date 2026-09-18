# Branch protection & repo settings

Run via `scripts/checks/branch-protection.sh <target>`.

## Criteria

- Required PR reviews on the default branch (at least one approving review):
  **skipped, not failed, on a solo repo (1 collaborator)**. GitHub does not
  count self-approval, so `required_approving_review_count >= 1` on a
  single-collaborator repo locks that collaborator out of merging anything,
  Renovate/Dependabot automerge included (no second identity to approve).
  Required status checks are the real gate there. The check calls
  `gh api repos/{owner}/{repo}/collaborators` to decide which branch applies.
- Required status checks configured, and the names match a **job id** (or
  `name:`) in the current CI workflows: a required check pointing at a
  renamed or deleted job is a silent no-op, worse than no requirement.
  Matched against job ids in the workflow YAML, not filenames: a job
  `flake-check` in `pr-check.yaml` is a match.
- Force-push disabled on the default branch.
- Branch deletion protection enabled on the default branch.
- Merge-strategy policy (squash / rebase / merge-commit) is **reported, not
  enforced**: a repo-owner judgment call, not a hygiene defect.

## GitHub

`gh api repos/{owner}/{repo}/branches/{branch}/protection`: compare
`required_pull_request_reviews`, `required_status_checks.contexts`,
`allow_force_pushes.enabled` (must be `false`), and repo-level
`delete_branch_on_merge` / branch deletion rules.

Cross-check required status check names against
`gh api repos/{owner}/{repo}/actions/workflows` job names; a mismatch is a
finding even if protection is otherwise configured correctly.

## Fixing

`--fix` calls `forge_set_branch_protection` with the missing settings, one
finding at a time, after an explicit y/n confirmation showing the exact API
payload about to be sent.
