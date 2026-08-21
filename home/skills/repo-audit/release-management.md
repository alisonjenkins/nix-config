# Release management

Run via `scripts/checks/release-management.sh <target>`.

## Criteria

- Automated release tooling present and wired into CI: `release-please` on
  GitHub (a `.github/workflows/*.yaml` running
  `googleapis/release-please-action`, or a `release-please-config.json`);
  `semantic-release` (or `python-semantic-release`/similar) elsewhere, or on
  GitLab where
  release-please has no native support.
- Commit messages / PR titles conform to the convention the tool consumes —
  Conventional Commits (`feat:`, `fix:`, ...). Checked heuristically against
  recent commit history (last ~50 commits on the default branch), not
  enforced as a commit-msg hook by this check (that's `pre-commit.md`'s
  territory if the repo chooses to add one).
- Releases actually publish on merge to the default branch — a release-please
  workflow that only opens a release PR nobody merges is a finding, not a
  pass. Checked by confirming the workflow both opens release PRs and, on
  their merge, tags/publishes (the `release-please-action` `release_created`
  output gated a follow-up publish step, or the tool's own auto-tag).

## GitHub

`gh api repos/{owner}/{repo}/contents/.github/workflows` for a release-please
or semantic-release workflow; `gh release list` to confirm releases have
actually been cut recently (not just configured once and abandoned).

## GitLab

Not implemented in v1 — `lib/gitlab.sh` stub; check reports "unsupported
forge" for the "did it actually publish" verification (needs the forge API),
but the local file/commit-convention checks still run.

## Fixing

`--fix` scaffolds a minimal release-please workflow + config (GitHub) after
confirmation. It never rewrites commit history to retrofit Conventional
Commits — that's flagged as a finding for the user to address going forward,
not fixed automatically.
