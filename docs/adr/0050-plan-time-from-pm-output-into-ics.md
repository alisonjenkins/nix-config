# 0050. Plan time from pm output and write an ics file

- Status: Accepted
- Date: 2026-10-21

## Context

`pm list` carries `due`, `est` and `prio`, but nothing turned them into a schedule, so the user planned by hand and double-booked. A sibling skill was promised in the project-management spec. No Google Calendar tooling was reachable from the agent environment on this date: no MCP connector, no gateway tool, no `gcalcli`.

Read first: `docs/superpowers/specs/2026-10-21-time-management-skill-design.md`.

## Decision

`time-management` ships a `tm` script with one verb, `plan`, and the same backend-per-directory shape as `pm` (ADR 0049). The `ics` backend reads `pm list` rows and busy `.ics` files, ranks and places tasks, and writes an `.ics`. The `google` backend is a stub that fails with a clear message.

`tm` never calls `pm`: rows arrive on stdin or `--from`, so it works with every tracker backend and the two skills install independently. The cost is a few duplicated helpers (`common.sh`, `lint-aliases.sh`) instead of a cross-skill import that breaks when only one skill is installed.

The scheduler is awk, not bash loops or a new runtime, because it is date arithmetic over small tables and awk is already a dependency of `pm`. `--tz` is a fixed offset and recurrence rules are not expanded: both need a time zone database or an RRULE engine, and the user's calendar can export UTC occurrences.

## Consequences

- A plan is a proposal in a file. Nothing is written to a tracker or a calendar, so there is nothing to undo.
- Re-importing a newer plan updates events through stable UIDs (`tm-<id>-<block>@time-management`), but tasks removed from the plan stay in the calendar until the user deletes them.
- Daylight saving, named zones and live Google Calendar access are follow-ups, tracked in `PENDING.md`.
