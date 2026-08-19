---
name: repo-audit
description: Use when checking or fixing a git repository's hygiene — branch protection, secret scanning and push protection, dependency updates (renovate/dependabot), CI pipeline health, release management (release-please etc.), pre-commit hooks, or a Nix dev shell/packages flake. Works against any repo (path or owner/repo) on any forge (GitHub today, GitLab stubbed) via `scripts/audit.sh`. Carries the audit criteria per topic and the fix-confirmation rule.
---

# Repo audit

Audits (and, on request, fixes) a target repo's hygiene across seven areas.
Forge-agnostic: `scripts/lib/forge.sh` detects GitHub vs GitLab vs unknown and
dispatches; everything else is forge-independent.

## Running it

```
scripts/audit.sh <target> [topic] [--fix]
```

- `<target>`: a local path or `owner/repo`.
- `[topic]`: one of `branch-protection`, `secret-scanning`, `dependency-updates`,
  `ci-pipeline`, `release-management`, `pre-commit`, `dev-shell`. Omit to run
  all seven.
- `--fix`: after reporting, offer to apply each finding — **one at a time**,
  with an explicit y/n prompt per change. Never batch-apply without review;
  this mirrors the "always ask before mutating live infra" rule in the `infra`
  skill. Answering "n" skips that finding and moves on; nothing is applied
  silently.

Default (no `--fix`) is read-only: it reports findings and the diff it would
apply, and touches nothing.

## Working rules

- Idempotent: re-running against an already-compliant repo reports all-pass,
  never re-applies anything.
- Resolve tools (`gh`, `jq`, `git`) through the `nix-shell` shebang on each
  script, not ambient `PATH` — these scripts run on machines with no global
  package pool.
- A repo whose forge isn't supported yet (GitLab today; anything without a
  forge at all, e.g. CodeCommit) gets a clear "unsupported forge" report for
  the forge-dependent topics, not an error. The local-repo-only topics
  (pre-commit, dev-shell) still run regardless of forge.

## Routing

| Auditing | Read |
|---|---|
| Required reviews, status checks, force-push/delete protection | [branch-protection.md](branch-protection.md) |
| Secret scanning, push protection, gitleaks/trufflehog in CI | [secret-scanning.md](secret-scanning.md) |
| renovate.json / dependabot.yml coverage | [dependency-updates.md](dependency-updates.md) |
| Required checks wired to branch protection, workflow permissions, caching | [ci-pipeline.md](ci-pipeline.md) |
| release-please / semantic-release, commit convention, releases actually publish | [release-management.md](release-management.md) |
| `.pre-commit-config.yaml`, enforced in CI not just locally | [pre-commit.md](pre-commit.md) |
| `flake.nix` devShells + packages, `.envrc` | [dev-shell.md](dev-shell.md) |
