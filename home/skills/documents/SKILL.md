---
name: documents
description: Producing or reading real documents and written comms — Word (.docx), PDF, PowerPoint (.pptx), Excel (.xlsx), long-form co-authored drafts, and internal announcements. Use when asked for a report, memo, letter, deck, spreadsheet, or template as a file, when extracting or editing content from one, or when drafting an announcement or update for other people to read. Routes to the specialist skill that does the work.
---

# Documents

This family exists so the specialist document skills stay out of the baseline
listing until they are relevant. Each one below is a full skill: **invoke it**
rather than trying to do the work from this page.

| The ask | Invoke |
|---|---|
| Word documents: create, read, edit, find-and-replace, tracked changes, comments, letterheads, tables of contents | `/docx` |
| PDFs: read, extract, split/merge, fill forms | `/pdf` |
| PowerPoint decks: build, edit, extract slides | `/pptx` |
| Excel workbooks: read, write, formulas, formatting | `/xlsx` |
| Long-form writing worked on **with** the user over several turns — specs, essays, proposals | `/doc-coauthoring` |
| Announcements, status updates, and other writing aimed at colleagues | `/internal-comms` |

## Availability

These leaves ship with Claude Code. In another runtime they may not be
installed — check before promising a `.docx`, and say plainly that the format
is unavailable rather than improvising a substitute.

## Choosing

- The **file format asked for** decides the first four. If the user says
  "report" without a format, ask before generating a binary file.
- `doc-coauthoring` is about the *process* (drafting alongside the user), not
  a format — it composes with the format skills rather than replacing them.
- None of these are for source code, config files, or markdown in a repo.
  That is ordinary editing; see the `programming` skill.
