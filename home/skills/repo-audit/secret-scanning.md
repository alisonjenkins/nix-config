# Secret scanning & push protection

Run via `scripts/checks/secret-scanning.sh <target>`.

## Criteria: all required, none optional

- Forge-native secret scanning enabled on the repo.
- Forge-native push protection enabled (blocks a push that contains a
  detected secret, not just alerts after the fact).
- A CI-level scanner (gitleaks, trufflehog, or equivalent) as a required job.
  A **hard requirement**: forge-native scanning covers known secret formats;
  a CI scanner catches repo-specific patterns and runs where forge-native
  scanning is unavailable (private repos on some plans, self-hosted forges).
  Missing it fails the check.

## GitHub

`gh api repos/{owner}/{repo}` → `security_and_analysis.secret_scanning.status`
and `secret_scanning_push_protection.status`, both must be `enabled`.

CI scanner presence: grep workflow YAML under `.github/workflows/` for a
gitleaks or trufflehog action/step, and confirm that job is in the required
status checks list (cross-references `branch-protection.md`).

## Fixing

`--fix` enables forge-native scanning/push-protection via API where
supported, with per-change confirmation. It does **not** auto-write a CI
scanner job (too repo-specific to template safely): it prints the minimal
gitleaks/trufflehog step and asks for confirmation before writing the
workflow file.
