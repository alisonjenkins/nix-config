# Pre-commit hooks

Run via `scripts/checks/pre-commit.sh <target>`. Local-repo-only, no forge
API involved, so this runs the same regardless of forge, including against
repos with no forge integration at all (e.g. CodeCommit-hosted).

## Criteria

- `.pre-commit-config.yaml` (or an equivalent framework, e.g. `lefthook.yml`)
  present.
- Configured hooks actually cover the linters/formatters relevant to the
  ecosystems detected in the repo (same ecosystem-detection logic as
  `dependency-updates.md`); a Rust repo with only a trailing-whitespace hook
  and no `cargo fmt`/`clippy` hook is a finding.
- Hooks are enforced in CI too, not just locally optional: either
  pre-commit.ci is enabled (check for its badge/config), or an explicit CI job
  runs `pre-commit run --all-files` (or the lefthook equivalent). A hook that
  only lives in a contributor's local `.git/hooks` after `pre-commit install`
  is not durable, so it's silently skipped by anyone who never ran that
  command, including CI itself unless it's re-installed there too.

## Fixing

`--fix` scaffolds a minimal `.pre-commit-config.yaml` covering the detected
ecosystems' standard hooks, and/or adds a CI job invoking `pre-commit run
--all-files`, each shown as a diff and confirmed individually.
