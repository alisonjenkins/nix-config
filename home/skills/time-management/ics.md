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
| `--tz <zone>` | +00:00 | zone for `--hours` and `--weekdays`: a fixed offset (`+01:00`) or an IANA name (`Europe/London`) that follows daylight saving |
| `--weekdays a-b` | 1-5 | ISO weekdays to work (1 = Monday) |
| `--chunk <min>` | 90 | longest block a task is cut into |
| `--gap <min>` | 10 | breathing room after every block |
| `--default-est <min>` | 30 | used when a row has no `est` |

## How tasks are placed

1. Only `open` rows count. A row whose `deps` name another open row is placed after the end of that row's last block, whatever its rank. It is a `skip` only when a dependency never gets a slot: the dependency is `unscheduled`, or the `deps` form a cycle.
2. A `due` with no time of day (`2026-10-19`) means the end of that day. Rank by `due` (earliest first, none last), then `prio` (lowest first, none last), then input order.
3. Each task takes the earliest free time. A block is at most `--chunk` minutes and never crosses busy time or the end of the working window, so a long task is split into `chunk k/n` blocks. A free stretch under 15 minutes is skipped unless it finishes the task.
4. A task that ends after its `due` is marked `late` and still scheduled. A task that does not fit in `--days` is `unscheduled` and takes no time.

## The .ics files

Output: one `VEVENT` per block, UTC times, CRLF line endings, lines folded at 75 octets. The `UID` is `tm-<id>-<block>@time-management`, so importing a newer plan updates the same events instead of duplicating them. The file is replaced by a rename and its mode follows your umask, so an existing file's mode is reset. Task ids from different trackers can collide; plan one tracker per file.

Input (`--busy`): `DTSTART`/`DTEND` as UTC, floating or `VALUE=DATE`, and `DURATION`. Events with `STATUS:CANCELLED` or `TRANSP:TRANSPARENT` (shown as free, as holiday and birthday calendars usually are) do not block time. Zone parameters (`TZID`) are ignored and the time is read as UTC, so export busy times in UTC. Recurring events are expanded over the planning horizon: `FREQ` of `DAILY`, `WEEKLY` (with `BYDAY`), `MONTHLY` (with `BYMONTHDAY`) or `YEARLY`, plus `INTERVAL`, `COUNT`, `UNTIL` and `EXDATE`. Any other rule (an ordinal `BYDAY` such as `1MO`, `BYSETPOS`) prints `tm: cannot expand RRULE ...` on stderr and only the first occurrence is planned around, so check stderr. `RDATE` dates are ignored without a warning, and a moved occurrence (`RECURRENCE-ID`) blocks its new time while the original time stays blocked too.

## Limits

- A zone name needs the tz database (`$TZDIR` or `/usr/share/zoneinfo`) and `date` to read it. A day takes the zone's offset at noon, so a clock change inside the working window (a window that spans 02:00) shifts that day by an hour.
- Zone names apply to `--hours` and `--weekdays` only. A `TZID` in a `--busy` file is still read as UTC.
- Nothing is rescheduled: each run plans from `--now` and treats earlier plans as unknown. Pass last time's `.ics` as `--busy` only if you want it kept.
- The google backend is a stub. No Google Calendar tool was reachable on 2026-10-21.
