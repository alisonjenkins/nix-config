# Dependency updates

Run via `scripts/checks/dependency-updates.sh <target>`.

## Criteria

- `renovate.json` (or `.github/renovate.json5`, etc.) or `.github/
  dependabot.yml` present.
- Config covers the ecosystems actually detected in the repo: the check
  scans for `go.mod`, `package.json`, `Cargo.toml`, `flake.nix` (nix flake
  inputs), `requirements.txt`/`pyproject.toml`, Dockerfiles, and GitHub
  Actions versions, then diffs that against what the config's `packageRules`/
  `updates` entries actually cover. A config that only updates npm in a repo
  that also has a Dockerfile is a finding.
- Auto-merge-on-green is a **hard requirement**, not a per-repo judgment call,
  because without it, dependency PRs pile up and get rubber-stamped or
  ignored, which defeats the point of automating updates at all. The config
  must enable `automerge` (Renovate) or auto-merge equivalent (Dependabot's
  `target-branch`/GitHub's native auto-merge), gated on required status checks
  actually passing: this only merges safely when `branch-protection.md`'s
  required-checks criterion is also met, so a repo failing that check gets
  both findings, not just one.

## GitHub

Renovate: presence of `renovate.json`/`renovate.json5` at repo root or
`.github/`, plus (informational) whether the Renovate GitHub App is installed,
checked via `gh api repos/{owner}/{repo}/installation` for the Renovate app
ID, best effort, not fatal if unreadable.

Dependabot: `.github/dependabot.yml`, parsed for `package-ecosystem` entries.

## GitLab

File-presence and ecosystem-coverage checks are forge-independent and run
unchanged. GitLab's built-in dependency scanning status is a separate,
unimplemented check in v1 (`lib/gitlab.sh` stub).

## Fixing

`--fix` scaffolds a minimal `renovate.json` (`{"extends": ["config:recommended",
":automergeAll"]}`) when none exists, or offers to add
`"automerge": true` (Renovate) to an existing config that's missing it, or
appends a missing ecosystem entry, each shown as a diff and confirmed before
writing.
