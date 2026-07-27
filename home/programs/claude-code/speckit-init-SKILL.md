---
name: speckit-init
description: Initialise GitHub spec-kit (Spec-Driven Development) in the current repo, installing the /speckit-* skills and the .specify/ scripts and templates. Use when the user runs /speckit-init, says "set up spec-kit", "init speckit here", or asks for /speckit-specify or /speckit-plan in a repo that has no .specify/ directory.
argument-hint: "[--force to re-run over an existing .specify/]"
---

# Initialise spec-kit in this repo

GitHub spec-kit is **per-project**. The `specify` CLI is globally installed, but the
`/speckit-*` skills and the scripts they call only exist once a repo has been
initialised. This skill does that initialisation. It replaces the old cavekit
`/ck:*` commands.

`specify` is at `@specify@` — always invoke it by that absolute path, never by
bare name.

## 1. Locate the target repo

- Repo root: `git rev-parse --show-toplevel`.
- Not a git repo? Say so and **ask the user** before initialising — spec-kit writes
  a dozen files and is much harder to undo without version control.
- Everything below runs from the repo root, not from the session's cwd.

## 2. Check whether it is already initialised

Idempotence first — check before mutating:

```bash
ls -d "$ROOT/.specify" "$ROOT"/.claude/skills/speckit-* 2>/dev/null
```

- `.specify/` exists and the user did **not** pass `--force`: report that the repo
  is already initialised, list the `speckit-*` skills present, and stop. Do not
  re-run init.
- `.specify/` exists and the user did pass `--force`: continue, but first warn that
  re-running overwrites the bundled scripts and templates, and that any local edits
  to `.specify/` or the `speckit-*` SKILL.md files will be lost. Only proceed once
  the user confirms.

## 3. Run the initialiser

```bash
cd "$ROOT" && @specify@ init --here --force --integration claude
```

- `--here` initialises in place; `--force` skips the interactive
  "directory is not empty" confirmation, which would otherwise hang a
  non-interactive run. It merges into the repo — it does not wipe it.
- No network required: the templates, scripts and command definitions are bundled
  inside the CLI package.
- If init aborts on an agent-tool check (it looks for a `claude` binary and this
  setup wraps it), re-run with `--ignore-agent-tools` added.
- If the run fails part-way, report the exact error line and leave the repo alone —
  do not hand-patch `.specify/`.

## 4. Report what landed

Show the user what was created:

```bash
ls "$ROOT/.specify" "$ROOT/.claude/skills"
```

Expect:

- `.specify/scripts/bash/` — the shell scripts every `/speckit-*` skill shells out to
- `.specify/templates/` — spec, plan, tasks, checklist, constitution templates
- `.specify/memory/` — the project constitution once written
- `.claude/skills/speckit-<name>/SKILL.md` — one per command

Then tell them:

1. `git add .specify .claude/skills` — these are meant to be committed.
2. **Restart the Claude Code session.** Project skills are read at startup; the
   `/speckit-*` commands will not appear until then.

## 5. The workflow, once initialised

Normal order:

`/speckit-constitution` → `/speckit-specify` → `/speckit-clarify` → `/speckit-plan`
→ `/speckit-tasks` → `/speckit-analyze` → `/speckit-implement`

Also bundled: `/speckit-checklist`, `/speckit-converge`, `/speckit-taskstoissues`.

Note the separator: the Claude integration installs these as **skills**, so they are
hyphenated (`/speckit-plan`), not dotted (`/speckit.plan` — that is the form other
agent integrations use).
