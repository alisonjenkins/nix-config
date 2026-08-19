# Dependency updates

Run via `scripts/checks/dependency-updates.sh <target>`.

## Criteria

- `renovate.json` (or `.github/renovate.json5`, etc.) or `.github/
  dependabot.yml` present.
- Config covers the ecosystems actually detected in the repo — the check
  scans for `go.mod`, `package.json`, `Cargo.toml`, `flake.nix` (nix flake
  inputs), `requirements.txt`/`pyproject.toml`, Dockerfiles, and GitHub
  Actions versions, then diffs that against what the config's `packageRules`/
  `updates` entries actually cover. A config that only updates npm in a repo
  that also has a Dockerfile is a finding.
- Auto-merge-on-green policy is **reported, not enforced** — how much trust to
  extend to automated updates is a per-repo judgment call.

## GitHub

Renovate: presence of `renovate.json`/`renovate.json5` at repo root or
`.github/`, plus (informational) whether the Renovate GitHub App is installed
— `gh api repos/{owner}/{repo}/installation` for the Renovate app ID, best
effort, not fatal if unreadable.

Dependabot: `.github/dependabot.yml`, parsed for `package-ecosystem` entries.

## GitLab

File-presence and ecosystem-coverage checks are forge-independent and run
unchanged. GitLab's built-in dependency scanning status is a separate,
unimplemented check in v1 (`lib/gitlab.sh` stub).

## Fixing

`--fix` scaffolds a minimal `renovate.json` (`{"extends": ["config:recommended"]}`,
matching this repo's own `renovate.json`) or appends a missing ecosystem entry
to an existing config, with the diff shown and confirmed before writing.
