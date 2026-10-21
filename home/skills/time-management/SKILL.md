---
name: time-management
description: >-
  Use when turning a task list into a schedule: ranking tasks by deadline and priority, timeboxing them, planning a week around existing calendar events, or producing an .ics file to import into a calendar. Runs the `tm` script on `pm list` output instead of planning by hand. Not for tracking tickets or breaking a project down (see project-management), writing a feature spec, or booking meetings with other people.
metadata:
  summary: "Use to rank tasks, timebox them around busy calendar time and write the plan as an .ics via the tm script."
---

# Time management

## When to use

Use when the user wants tasks scheduled: "what should I work on this week", "fit these tasks into my calendar", "which of these will miss their deadline". The tasks come from the `project-management` skill's `pm list`; this skill only reads them.

## Rules

- **Get the task rows first.** Run `pm ... list --state open` (see the project-management skill) and pass the output to `tm`. Never type rows by hand: `due`, `est` and `prio` come from the tracker.
- **Ask for existing commitments once.** If the user has a calendar export, pass it with `--busy <file.ics>`. Without it the plan can double-book; say so in the answer.
- **Read the notes, not just the slots.** `late` means the task ends after its due date, `est-default` means the estimate is a 30 minute guess, `skip` means an open dependency blocks it, `unscheduled` means nothing fits in the horizon. Report each one to the user; do not drop them.
- **The plan is a proposal.** `tm` writes only the `--ics` file you name and never changes a tracker or a calendar. Show the plan and let the user import the file.
- **Time zones.** `--tz` is a fixed offset such as `+01:00`. It does not follow daylight saving, so re-run after a clock change and say so when a plan spans one.

## Quick reference

`tm` lives in `scripts/` beside this file. Backends: `i` (ics, works today) and `g` (google, a stub that fails with a clear message).

```
pm -b g -r owner/name list --state open | tm -b i plan
pm -b l -d docs/projects/foo list | tm -b i plan --busy work.ics --ics plan.ics
tm -b i plan --from rows.tsv --hours 09:30-17:30 --tz +01:00 --days 7
```

Output is tab separated after a `# backend=ics ...` line: `slot id start end title notes`, then `skip` and `unscheduled` lines, then a `# scheduled=... late=...` summary. Times are ISO8601 UTC.

## Routing

| Doing | Read |
|---|---|
| Flags, ranking and placement rules, the .ics format, limits | [ics.md](ics.md) |
| Getting the task rows, or changing a ticket | the `project-management` skill |
