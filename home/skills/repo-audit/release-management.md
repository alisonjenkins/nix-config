# Release management

Run via `scripts/checks/release-management.sh <target>`.

## Criteria

- Automated release tooling present and wired into CI: `release-please` on
  GitHub (a `.github/workflows/*.yaml` running
  `googleapis/release-please-action`, or a `release-please-config.json`);
  `semantic-release` (or `python-semantic-release`/similar) elsewhere, or on
  GitLab where
  release-please has no native support.
- Commit messages / PR titles follow the convention the tool consumes,
  Conventional Commits (`feat:`, `fix:`, ...). Checked heuristically against
  the last ~50 commits on the default branch, not enforced as a commit-msg
  hook (that is `pre-commit.md`'s territory if the repo adds one).
- Releases actually publish on merge to the default branch: a release-please
  workflow that only opens a release PR nobody merges is a finding. Confirm
  the workflow both opens release PRs and, on their merge, tags/publishes
  (`release-please-action`'s `release_created` output gating a publish step,
  or the tool's own auto-tag).

## GitHub

`gh api repos/{owner}/{repo}/contents/.github/workflows` for a release-please
or semantic-release workflow; `gh release list` to confirm releases were cut
recently (not configured once and abandoned).

## Fixing

`--fix` scaffolds a minimal release-please workflow + config (GitHub) after
confirmation. It never rewrites history to retrofit Conventional Commits;
that is flagged as a finding for the user to address going forward.
