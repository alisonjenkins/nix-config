# Dependency updates

Run via `scripts/checks/dependency-updates.sh <target>`.

## Criteria

- `renovate.json` (or `.github/renovate.json5`, etc.) or `.github/
  dependabot.yml` present.
- Config covers the ecosystems detected in the repo: the check scans for
  `go.mod`, `package.json`, `Cargo.toml`, `flake.nix` (flake inputs),
  `requirements.txt`/`pyproject.toml`, Dockerfiles, and GitHub Actions
  versions, then diffs that against the config's `packageRules`/`updates`
  entries. A config that only updates npm in a repo with a Dockerfile is a
  finding.
- Auto-merge-on-green is a **hard requirement**, not a per-repo judgment
  call: without it dependency PRs pile up and get rubber-stamped or ignored,
  defeating the point of automating updates. The config must enable
  `automerge` (Renovate) or the equivalent (Dependabot's `target-branch` /
  GitHub native auto-merge), gated on required status checks passing. That
  only merges safely when `branch-protection.md`'s required-checks criterion
  is also met, so a repo failing that check gets both findings.

## GitHub

Renovate: `renovate.json`/`renovate.json5` at repo root or `.github/`, plus
(informational, best effort) whether the Renovate GitHub App is installed via
`gh api repos/{owner}/{repo}/installation` for the Renovate app ID.

Dependabot: `.github/dependabot.yml`, parsed for `package-ecosystem` entries.

## Fixing

`--fix` scaffolds a minimal `renovate.json` (`{"extends": ["config:recommended",
":automergeAll"]}`) when none exists, adds `"automerge": true` (Renovate) to
a config missing it, or appends a missing ecosystem entry, each shown as a
diff and confirmed before writing.
