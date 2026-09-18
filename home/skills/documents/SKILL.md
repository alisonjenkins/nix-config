---
name: documents
description: Use when asked to produce, read, edit or extract from a real document file, such as a report, memo, letter, deck, spreadsheet or template as .docx, .pdf, .pptx or .xlsx, when drafting long-form writing alongside the user, or when writing an announcement or update aimed at other people. Routes to the specialist skill that does the work. Not for source code or markdown in a repo.
---

# Documents

This family keeps the specialist document skills out of the baseline listing
until relevant. Each entry below is a full skill: **invoke it** rather than
working from this page.

| The ask | Invoke |
|---|---|
| Word documents: create, read, edit, find-and-replace, tracked changes, comments, letterheads, tables of contents | `/docx` |
| PDFs: read, extract, split/merge, fill forms | `/pdf` |
| PowerPoint decks: build, edit, extract slides | `/pptx` |
| Excel workbooks: read, write, formulas, formatting | `/xlsx` |
| Long-form writing worked on **with** the user over several turns: specs, essays, proposals | `/doc-coauthoring` |
| Announcements, status updates, and other writing aimed at colleagues | `/internal-comms` |

## Availability

These leaves ship with Claude Code. Another runtime may lack them: check
before promising a `.docx`, and say the format is unavailable rather than
improvising a substitute.

## Choosing

- The **file format asked for** decides the first four. "Report" with no
  format: ask before generating a binary file.
- `doc-coauthoring` is a *process* (drafting alongside the user), not a
  format; it composes with the format skills.
- None of these cover source code, config files, or markdown in a repo. That
  is ordinary editing; see `programming`.
