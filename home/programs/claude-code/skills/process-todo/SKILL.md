---
name: process-todo
description: Process open items from todo.md at the repo root, moving completed items to done.md with ISO8601 UTC timestamps. Use when user runs /process-todo, says "process my todo", "work the todo list", or "update done.md".
argument-hint: "[optional item filter]"
---

# Process todo.md

Work the open items in `todo.md` at the repo root, recording completions in `done.md`. These are personal, per-repo work-queue files driven by text, not chat history.

## 1. Locate files

- Repo root: `git rev-parse --show-toplevel`. If not a git repo, use the current working directory.
- Files: `<root>/todo.md` and `<root>/done.md`.

## 2. Scaffold (only with permission)

If `todo.md` does not exist, **ask the user before creating anything** — never silently scaffold. On approval create:

```markdown
# TODO

# Done

See [done.md](done.md).
```

Then make both files invisible to git **without touching the checked-in `.gitignore`**:

- Append `todo.md` and `done.md` to `<root>/.git/info/exclude`, skipping any line already present.
- Self-heal: if the files already exist but are neither git-tracked (`git ls-files --error-unmatch <file>` fails) nor excluded (`git check-ignore <file>` fails), offer to add the exclude entries.
- If a file IS git-tracked, the repo has deliberately committed it — leave tracking alone and do not add exclude entries.

## 3. Process items

- Work each open item under the `# TODO` section, top to bottom.
- If an argument filter was given, only process items matching it.
- Ambiguous or underspecified item: ask the user, don't guess.
- Empty `# TODO` section: report there is nothing to do and stop.

**Invariant:** top-level section headers in `todo.md` stay in place even when their sections empty out. Remove completed items only — never headers.

## 4. Record completions

For each completed item, remove it from `todo.md` and add an entry to `done.md` under its top heading, **reverse-chronological (newest first)**.

Entry format (exact):

```
- <ISO8601 UTC to the second> — <item text>
```

Example: `- 2026-06-10T14:03:22Z — Rotate the sops age key`

The timestamp comes from `date -u +%Y-%m-%dT%H:%M:%SZ` run at the moment of completion — never fabricated, reused from another entry, or truncated below second precision.

## 5. Compaction

After recording, count the individual timestamped entries in `done.md` (entries inside an existing archive section don't count). If the count exceeds 15:

- Take the **oldest 10** entries.
- Replace them with a single section at the bottom of the file:

```markdown
## Archive (compacted <ISO8601 UTC now>)

<2-5 bullet summary of the archived work, noting the timestamp range it spans>
```

- If an archive section already exists, append the new summary to it (one dated summary block per compaction).
- This leaves at least 6 live entries above the archive.

## 6. GitHub repos: propose fixes via PR

If `gh repo view` succeeds and an item requires code changes:

- Do the work on a branch, not the default branch.
- Propose it as a pull request (delegate to the pr-creator agent).
- Mark the item done only when the work is complete; if the PR is the deliverable, the done.md entry should reference it (e.g. `— Fix flaky retry test (PR #42)`).

## 7. Final report

Brief summary: items completed (with timestamps), items skipped and why, whether compaction ran, any PRs opened.
