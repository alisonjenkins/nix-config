# The ics backend

Selected with `-b i`. Pure shell and awk; it needs no network and no credentials.

## Flags

| Flag | Default | Meaning |
|---|---|---|
| `--from <file>` | stdin | `pm list` output; `#` lines are ignored. With neither `--from` nor a pipe, `tm` waits on the terminal |
| `--busy <file.ics>` | none | existing events to plan around; repeatable |
| `--ics <out.ics>` | none | also write the plan as a calendar |
| `--now <ISO8601 UTC>` | current time | planning starts here, rounded up to 5 minutes |
| `--days <n>` | 14 | how many calendar days ahead to plan (at most 366) |
| `--hours HH:MM-HH:MM` | 09:00-17:00 | working window, in the `--tz` offset |
| `--tz +HH:MM` | +00:00 | fixed UTC offset for `--hours` and `--weekdays` |
| `--weekdays a-b` | 1-5 | ISO weekdays to work (1 = Monday) |
| `--chunk <min>` | 90 | longest block a task is cut into |
| `--gap <min>` | 10 | breathing room after every block |
| `--default-est <min>` | 30 | used when a row has no `est` |

## How tasks are placed

1. Only `open` rows count. A row whose `deps` name another open row is a `skip`.
2. A `due` with no time of day (`2026-10-19`) means the end of that day. Rank by `due` (earliest first, none last), then `prio` (lowest first, none last), then input order.
3. Each task takes the earliest free time. A block is at most `--chunk` minutes and never crosses busy time or the end of the working window, so a long task is split into `chunk k/n` blocks. A free stretch under 15 minutes is skipped unless it finishes the task.
4. A task that ends after its `due` is marked `late` and still scheduled. A task that does not fit in `--days` is `unscheduled` and takes no time.

## The .ics files

Output: one `VEVENT` per block, UTC times, CRLF line endings, lines folded at 75 octets. The `UID` is `tm-<id>-<block>@time-management`, so importing a newer plan updates the same events instead of duplicating them. The file is replaced by a rename and its mode follows your umask, so an existing file's mode is reset. Task ids from different trackers can collide; plan one tracker per file.

Input (`--busy`): `DTSTART`/`DTEND` as UTC, floating or `VALUE=DATE`, and `DURATION`. Events with `STATUS:CANCELLED` or `TRANSP:TRANSPARENT` (shown as free, as holiday and birthday calendars usually are) do not block time. Zone parameters (`TZID`) are ignored and the time is read as UTC, so export busy times in UTC. Recurrence rules are not expanded: export the occurrences, not the series.

## Limits

- No daylight saving or named zones; `--tz` is a fixed offset.
- A task is not ordered after the task it depends on; it is only held back while that task is open.
- Nothing is rescheduled: each run plans from `--now` and treats earlier plans as unknown. Pass last time's `.ics` as `--busy` only if you want it kept.
- The google backend is a stub. No Google Calendar tool was reachable on 2026-10-21.
