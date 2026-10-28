# time-management skill design

Date: 2026-10-21. Status: approved by the user in conversation.

## Problem

`pm list` says what is due and how long it takes (`due`, `est`, `prio`), but nothing turns that into a plan for the week. The user plans by hand, so deadlines slip and calendars get double-booked. This skill ranks open tasks, fits them into working hours around existing commitments, and writes the result as an `.ics` file.

Sibling of `project-management` (ADR 0049). It reads `pm list` output and never calls `pm`, so any tracker backend works.

## Interface

`tm` is a script beside `SKILL.md`. Like `pm`, it holds no state and the caller names the backend on every call: `-b i` (ics) or `-b g` (google, a stub that fails with "not implemented, use -b i").

```bash
tm -b i plan [--from FILE|-] [--busy FILE]... [--ics OUT]
             [--now ISO] [--days 14] [--hours 09:00-17:00] [--tz +00:00]
             [--weekdays 1-5] [--chunk 90] [--gap 10] [--default-est 30]
```

- `--from` is `pm list` output (`-` or no flag reads stdin). Header and `#` lines are ignored.
- `--busy` is an `.ics` of existing commitments, repeatable. `VEVENT` blocks with `DTSTART`/`DTEND` in UTC (`Z`), floating, or `VALUE=DATE` form become blocked intervals; `DURATION` is honoured. Recurrence rules are not expanded (documented limit).
- `--tz` is a fixed UTC offset applied to `--hours` and `--weekdays`. Named zones and DST are out of scope for v1.
- `--now` defaults to the current UTC time; tests pass it for determinism.

## Algorithm

1. Keep rows with state `open`. A row whose `deps` name another open row is reported as `skip` (blocked), not scheduled.
2. Rank by `due` ascending (no due last), then `prio` ascending (no prio last), then input order.
3. A missing `est` becomes `--default-est` minutes and the row is flagged `est-default`.
4. Walk the working windows for the next `--days` days, starting at `--now` rounded up to 5 minutes. Free time is the window minus busy intervals minus already placed chunks, each placed chunk padded by `--gap` minutes.
5. Per task in rank order, place chunks of at most `--chunk` minutes in the earliest free time. A free stretch shorter than 15 minutes is skipped unless it finishes the task. A chunk is never split across busy time.
6. A task whose last chunk ends after its `due` is marked `late`, never dropped. A task that finds no room in `--days` is reported as `unscheduled`.

## Output

stdout, tab separated, header first:

```text
# backend=ics from=<file|stdin> now=<ISO>
slot	<id>	<start ISO>	<end ISO>	<title>	<notes>
skip	<id>	<title>	blocked by <ids>
unscheduled	<id>	<title>	no room in <n> days
# scheduled=<tasks> chunks=<n> late=<n> skipped=<n> unscheduled=<n>
```

`notes` is a comma list of `chunk k/n`, `est-default`, `late`.

`--ics OUT` writes one `VEVENT` per chunk: CRLF line endings, text escaped, lines folded at 75 octets, `UID` of `tm-<id>-<k>@time-management` so re-importing updates events instead of duplicating them, `DTSTAMP` from `--now`. The skill writes nowhere except `OUT`, and never changes a tracker.

## Layout

```text
home/skills/time-management/
  SKILL.md  triggers.json  ics.md
  scripts/tm
  scripts/lib/{common.sh,time.awk,schedule.awk,ics.awk}
  scripts/backends/{ics,google}/{alias,plan.sh}
  scripts/lint-aliases.sh
  scripts/tests/*.bats
flake-modules/skills-time-management-tests.nix
```

All times are ISO8601 UTC. Bash 3.2 and POSIX awk only, no new dependencies.

## Out of scope for v1

Recurrence expansion, named time zones and DST, writing to or reading from Google Calendar, rescheduling an existing plan, ordering a task after the task it depends on.
