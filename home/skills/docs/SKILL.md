---
name: docs
description: >-
  Use when writing, restructuring or auditing a repository's documentation: README.md, quickstart, install and usage sections, "write a README", "document this project", "the docs are stale", "what should the README say". Not for polishing prose (see writing) or .docx/.pdf/.pptx deliverables (see documents).
metadata:
  summary: "Use when writing, restructuring or auditing a repo's docs: README.md, quickstart, install and usage sections."
---

# Docs

## When to use

Use this skill when creating, updating or reviewing repository documentation that a stranger reads to adopt, run or contribute to a project. A README is the entry door and router for that reader.

## Principles that hold for every doc

- Name the reader and their goal before writing a line. A README's reader is a stranger deciding in under a minute whether to use the project.
- The entry doc routes; it does not teach. Link out to tutorial, how-to, reference and explanation material (the Diataxis four types) instead of inlining it.
- One source of truth. Link to the canonical place; never copy text that will drift. Generate reference material (CLI help, option tables) instead of hand-writing it.
- Every command shown must run as written. Test on a clean checkout or say it is untested.
- State status and purpose explicitly: why this exists, how mature it is, what it is not.
- Prose quality follows the `writing` skill. This skill owns structure and content, not sentences.
- Human docs and agent instruction files (AGENTS.md, CLAUDE.md) are different files for different readers. See readme.md.

## Routing

| Doing | Read |
|---|---|
| Writing, restructuring or auditing a README.md | [readme.md](readme.md) |
| Laying out a repo's docs: root files, docs/ tree, ADRs, changelog | [structure.md](structure.md) |

## Related

See `writing` for prose, `documents` for office files, and `git/commit-messages.md` for commit text.
