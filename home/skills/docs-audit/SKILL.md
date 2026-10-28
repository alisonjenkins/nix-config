---
name: docs-audit
description: >-
  Audit an existing repo's README.md and docs for structure, broken links, orphan pages and missing community files. Use when the user runs /docs-audit, says "audit the docs", "check the README", or "are the docs in good shape". Read-only; rules live in the docs skill.
argument-hint: "[path to repo, default .]"
metadata:
  summary: "Audit a repo's README and docs for structure, broken links, orphan pages, and community files."
---

# Docs audit

Audit an existing repository's README and documentation against structural rules, link integrity, and anti-patterns defined in the docs skill.

## How to run

Run the audit script on the target repository:

```bash
scripts/check.sh <repo-path>
```

If `<repo-path>` is omitted, it defaults to the current working directory (`.`).

## What the script checks

The script performs automated, deterministic checks across the repository:

1. `readme_missing` (HIGH): Verifies a README file exists in root, `.github/`, or `docs/`.
2. `readme_short` (MEDIUM) / `readme_long` (LOW): Flags READMEs with fewer than 10 lines or more than 500 lines.
3. `no_install_or_usage` (MEDIUM): Checks for an install, quickstart, getting started, or usage heading.
4. `no_license` (MEDIUM): Checks for a LICENSE or COPYING file in root, or a License heading in README.
5. `many_badges` (LOW): Flags more than 5 badge images in the README.
6. `fence_no_language` (LOW): Reports code fence opening lines that lack a syntax language tag.
7. `image_no_alt` (MEDIUM): Flags empty markdown image alt text `![]()` and `<img>` tags without alt attributes.
8. `bad_link_text` (LOW): Flags uninformative link text such as "here", "click here", "link", or "this".
9. `broken_relative_link` (HIGH): Validates that relative link targets across all markdown files resolve to existing files.
10. `orphan_doc` (MEDIUM): Finds markdown files under `docs/` that cannot be reached by links from the README.
11. `docs_dir_no_index` (LOW): Flags `docs/` directories with 3 or more markdown files lacking `docs/README.md` when the root README does not link into `docs/`.
12. `missing_community_files` (LOW): Checks for `CONTRIBUTING.md`, `SECURITY.md`, and `CHANGELOG.md` (when git tags exist).
13. `placeholder_text` (LOW): Detects placeholder markers (TODO, TBD, FIXME, lorem ipsum, coming soon).
14. `agent_file_duplication` (MEDIUM/LOW): Verifies CLAUDE.md and AGENTS.md do not duplicate without import, and flags either exceeding 200 lines.
15. `readme_no_docs_link` (LOW): Flags when `docs/` contains markdown files but the README never mentions `docs/`.

## Manual evaluation

After running the script, read its output report. Then inspect the README and documentation directly against `docs/readme.md`, `docs/structure.md`, and `docs/agent-files.md`:

- Is the pitch concrete, on its own line, and under 120 characters?
- Does the quickstart run as written on a clean machine?
- Do documented options and flags match actual code and CLI behavior?
- Is a Documentation section present before License to route readers to deeper docs?
- Are agent instruction files (AGENTS.md, CLAUDE.md) duplicating human docs instead of linking or importing per `agent-files.md`?

## Output format

Present findings ranked by severity, most severe first (HIGH, then MEDIUM, then LOW). Show at most 10 findings.

For each finding, include:
- Where: file path and line number if applicable
- What is wrong: description of the defect
- What to do: actionable fix

## Guardrails

This skill is strictly read-only. Never modify, create, or delete repository files unless the user explicitly requests fixes after reviewing the audit findings.
