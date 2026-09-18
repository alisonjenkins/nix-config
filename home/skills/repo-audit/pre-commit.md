# Pre-commit hooks

Run via `scripts/checks/pre-commit.sh <target>`. Local-repo-only, no forge
API, so it runs the same on any forge or none (e.g. CodeCommit-hosted).

## Criteria

- `.pre-commit-config.yaml` (or an equivalent framework, e.g. `lefthook.yml`)
  present.
- Hooks cover the linters/formatters for the ecosystems detected in the repo
  (same detection as `dependency-updates.md`); a Rust repo with only a
  trailing-whitespace hook and no `cargo fmt`/`clippy` hook is a finding.
- Hooks are enforced in CI, not just locally: either pre-commit.ci is enabled
  (badge/config present), or a CI job runs `pre-commit run --all-files` (or
  the lefthook equivalent). A hook living only in a contributor's `.git/hooks`
  after `pre-commit install` is silently skipped by anyone who never ran that
  command, CI included unless it re-installs.

## Fixing

`--fix` scaffolds a minimal `.pre-commit-config.yaml` covering the detected
ecosystems' standard hooks, and/or adds a CI job invoking `pre-commit run
--all-files`, each shown as a diff and confirmed individually.
