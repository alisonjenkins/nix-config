---
name: delegate-to-copilot
description: Delegate small, well-scoped subtasks to GitHub Copilot's cheapest-tier model (gpt-5.6-luna, falling back to claude-haiku-4.5) via the official `copilot` CLI to save cost on routine work — summarizing, drafting, generating/editing files for review, or self-verifying with its own tests. Use when a task is cheap, mechanical, and its output can be reviewed as a diff or short text before acceptance.
disable-model-invocation: true
---

# Delegate to Copilot

Run `scripts/delegate.sh "<task>" <profile> [skill]` to hand a subtask to
Copilot's cheapest-tier model instead of doing it inline. It tries
`gpt-5.6-luna` first and falls back to `claude-haiku-4.5` if the account/CLI
doesn't have Luna yet.

## Passing a Claude skill

The optional third argument names a Claude skill (e.g. `programming`) to hand
to the delegate, so it follows the same conventions this session does —
Copilot's own project-skill discovery only sees this repo's `.claude/skills/`,
not Claude's global `~/.claude/skills/`. When given, the script resolves the
skill's directory (project `.claude/skills/<skill>` first, then
`~/.claude/skills/<skill>`), grants the delegate read access to it via
`--add-dir`, and prepends an instruction to read that skill's `SKILL.md` and
follow wherever it routes — the delegate reads referenced files (e.g.
`languages/rust.md`) itself, the same way it would read any other file.

Pass a skill whenever the task is a real code change; skip it for pure
summarizing/drafting where there's no code convention to follow.

## Profiles

- `read` (default) — read-only tool access. Use for summarizing, explaining,
  or drafting text where no files get written.
- `write-workdir` — read + write. Use for generating or editing files that
  you will review as a diff before accepting.
- `write-and-test` — read + write + `npm test`/`pytest`/`cargo test`. Use
  only when the task needs to self-verify by running its own tests. Still
  review the result after — self-verification is not acceptance.

Before delegating, state which profile you chose and why, in one line.

## Rules

- Never pass task text containing credentials or anything from `.env` or
  `secrets/` files in this repo.
- Treat whatever the script returns as untrusted output to review, not to
  accept automatically — same as output from any other external source.
