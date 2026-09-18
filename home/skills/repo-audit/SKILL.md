---
name: repo-audit
description: Use when checking or fixing a git repository's hygiene, covering branch protection, secret scanning and push protection, dependency updates (renovate/dependabot), CI pipeline health, release management (release-please etc.), pre-commit hooks, or a Nix dev shell/packages flake. Works against any repo (path or owner/repo) on any forge (GitHub today, GitLab stubbed) via `scripts/audit.sh`. Carries the audit criteria per topic and the fix-confirmation rule.
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
- `--fix`: after reporting, offer to apply each finding **one at a time**
  with a y/n prompt per change. Never batch-apply without review (mirrors the
  "ask before mutating live infra" rule in `infra`). "n" skips that finding;
  nothing is applied silently.

Without `--fix` it is read-only: reports findings plus the diff it would
apply, touches nothing.

## Working rules

- Idempotent: re-running against an already-compliant repo reports all-pass,
  never re-applies anything.
- Resolve tools (`gh`, `jq`, `git`) through each script's `nix-shell`
  shebang, not ambient `PATH`: these run on machines with no global package
  pool.
- An unsupported forge (GitLab today; no forge at all, e.g. CodeCommit) gets
  an "unsupported forge" report for the forge-dependent topics, not an error.
  Local-only topics (pre-commit, dev-shell) still run.

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
