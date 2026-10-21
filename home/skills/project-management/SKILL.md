---
name: project-management
description: >-
  Use when breaking a project into epics and tasks, tracking tasks or progress in GitHub Issues or a markdown tracker, writing a project charter, plan, status report or retro, or checking what is blocked, overdue or next. Runs the `pm` script for compact task lists and status instead of many `gh` calls. Not for writing a feature spec (see speckit-specify), scheduling or calendars (see time-management), or reviewing code.
metadata:
  summary: "Use for project breakdown, ticket tracking (GitHub Issues, markdown) and project docs via the pm script."
---

# Project management

## When to use

Use when planning or tracking work that spans more than one change: breaking a project down, creating or updating tickets, asking what is blocked or next, or writing the charter, plan, status report or retro. For one code feature, use the speckit skills; this skill tracks their tasks (see [tracking.md](tracking.md)).

## Rules

- **Name the tracker on every call.** `pm` keeps no state and detects nothing. Get the tracker from, in order: the user, a ticket URL they pasted, the repo's `CLAUDE.md`, `AGENTS.md` or README. Otherwise ask once, in one line, and reuse the answer. Never infer it from the git remote.
- **Know which verbs change things.** `sync-plan` is a dry run until `--apply`; show the user the dry run before applying, because creating issues is outward-facing. `update` is not a dry run: on GitHub it closes, reopens, labels or comments at once, so run it only for a change the user asked for.
- **Read cheaply.** Run `pm status` first, then `pm list` with filters, then `pm show <id>` for one item. Never fetch bodies in bulk. These reads are mechanical: delegate them to a cheap worker (see the delegation skill) and keep breakdown judgement here.
- **Restate the project in one sentence** (what is wrong today, for whom) before breaking it down.

## Quick reference

`pm` lives in `scripts/` beside this file. Backends: `g` (github, needs `-r owner/name`) and `l` (local, needs `-d <dir>` holding `tasks.md`).

```
pm -b g -r owner/name status
pm -b g -r owner/name list --state open --due-before 2026-12-01T00:00:00Z
pm -b l -d docs/projects/foo show T003
pm -b g -r owner/name update 12 --state done
pm -b g -r owner/name sync-plan specs/002-x/tasks.md            # dry run
pm -b g -r owner/name sync-plan specs/002-x/tasks.md --apply
pm show https://github.com/owner/name/issues/12                 # a URL needs no -b
```

`list` prints `id state title owner deps due est prio`, tab separated, after a `# backend=...` line.

## Routing

| Doing | Read |
|---|---|
| Running pm: verbs, columns, flags, token rules, speckit tasks | [tracking.md](tracking.md) |
| Breaking a project into epics and tasks | [breakdown.md](breakdown.md) |
| Writing a charter, plan, status report or retro | [docs.md](docs.md) |
| Using the GitHub backend (labels, milestones, epics, limits) | [github.md](github.md) |
| Using the local markdown backend | [local.md](local.md) |
