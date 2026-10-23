#!/usr/bin/env bats

load helpers

# busy <file>: busy intervals from an .ics as "start<TAB>end" ISO lines.
busy() {
  awk -f "$scripts_dir/lib/time.awk" -f "$scripts_dir/lib/busy.awk" "$1"
}

setup() {
  tm_setup
  cal="$BATS_TEST_TMPDIR/cal.ics"
}

# mk <lines...>: write an .ics with CRLF endings around the given VEVENT body lines.
mk() {
  { printf 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\n'
    printf '%s\r\n' "$@"
    printf 'END:VCALENDAR\r\n'; } >"$cal"
}

@test "a UTC event becomes one interval" {
  mk BEGIN:VEVENT DTSTART:20261021T090000Z DTEND:20261021T100000Z SUMMARY:Standup END:VEVENT
  run busy "$cal"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '2026-10-21T09:00:00Z\t2026-10-21T10:00:00Z')" ]
}

@test "folded lines are unfolded before parsing" {
  mk BEGIN:VEVENT 'SUMMARY:A very long' ' title' 'DTSTART:2026102' ' 1T090000Z' DTEND:20261021T093000Z END:VEVENT
  run busy "$cal"
  [ "$output" = "$(printf '2026-10-21T09:00:00Z\t2026-10-21T09:30:00Z')" ]
}

@test "parameters such as TZID are ignored and the time is read as UTC" {
  mk BEGIN:VEVENT 'DTSTART;TZID=Europe/London:20261021T090000' 'DTEND;TZID=Europe/London:20261021T100000' END:VEVENT
  run busy "$cal"
  [ "$output" = "$(printf '2026-10-21T09:00:00Z\t2026-10-21T10:00:00Z')" ]
}

@test "an all-day event blocks the whole day, and defaults to one day without DTEND" {
  mk BEGIN:VEVENT DTSTART\;VALUE=DATE:20261022 DTEND\;VALUE=DATE:20261024 END:VEVENT \
    BEGIN:VEVENT DTSTART\;VALUE=DATE:20261030 END:VEVENT
  run busy "$cal"
  [ "${lines[0]}" = "$(printf '2026-10-22T00:00:00Z\t2026-10-24T00:00:00Z')" ]
  [ "${lines[1]}" = "$(printf '2026-10-30T00:00:00Z\t2026-10-31T00:00:00Z')" ]
}

@test "DURATION is honoured" {
  mk BEGIN:VEVENT DTSTART:20261021T090000Z DURATION:PT1H30M END:VEVENT \
    BEGIN:VEVENT DTSTART:20261022T090000Z DURATION:P1DT2H END:VEVENT
  run busy "$cal"
  [ "${lines[0]}" = "$(printf '2026-10-21T09:00:00Z\t2026-10-21T10:30:00Z')" ]
  [ "${lines[1]}" = "$(printf '2026-10-22T09:00:00Z\t2026-10-23T11:00:00Z')" ]
}

@test "a timed event with no end, a bad time and non-events are ignored" {
  mk BEGIN:VEVENT DTSTART:20261021T090000Z END:VEVENT \
    BEGIN:VEVENT DTSTART:garbage DTEND:20261021T100000Z END:VEVENT \
    BEGIN:VTODO DTSTART:20261021T090000Z DTEND:20261021T100000Z END:VTODO
  run busy "$cal"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "cancelled and transparent events do not block time" {
  mk BEGIN:VEVENT DTSTART:20261020T090000Z DTEND:20261020T170000Z STATUS:CANCELLED END:VEVENT \
    BEGIN:VEVENT DTSTART\;VALUE=DATE:20261021 TRANSP:TRANSPARENT END:VEVENT \
    BEGIN:VEVENT DTSTART:20261022T090000Z DTEND:20261022T100000Z STATUS:CONFIRMED TRANSP:OPAQUE END:VEVENT
  run busy "$cal"
  [ "$output" = "$(printf '2026-10-22T09:00:00Z\t2026-10-22T10:00:00Z')" ]
}

@test "properties inside a VALARM do not change the event" {
  mk BEGIN:VEVENT DTSTART:20261019T090000Z DURATION:PT2H BEGIN:VALARM TRIGGER:-PT15M DURATION:PT5M REPEAT:1 END:VALARM END:VEVENT
  run busy "$cal"
  [ "$output" = "$(printf '2026-10-19T09:00:00Z\t2026-10-19T11:00:00Z')" ]
}

@test "events come out in file order, unsorted" {
  mk BEGIN:VEVENT DTSTART:20261021T130000Z DTEND:20261021T140000Z END:VEVENT \
    BEGIN:VEVENT DTSTART:20261021T090000Z DTEND:20261021T100000Z END:VEVENT
  run busy "$cal"
  [ "${lines[0]}" = "$(printf '2026-10-21T13:00:00Z\t2026-10-21T14:00:00Z')" ]
}

# busyw <file> <from> <to>: like busy, with the recurrence window in ISO8601 UTC.
busyw() {
  awk -v hfrom="$(epoch "$2")" -v hto="$(epoch "$3")" \
    -f "$scripts_dir/lib/time.awk" -f "$scripts_dir/lib/busy.awk" "$1"
}

epoch() {
  awk -f "$scripts_dir/lib/time.awk" -f <(printf 'BEGIN { print iso2epoch("%s") }\n' "$1")
}

rr() { printf '%s\t%s' "$1" "$2"; }

@test "a daily rule with COUNT expands to that many occurrences" {
  mk BEGIN:VEVENT DTSTART:20261019T090000Z DTEND:20261019T093000Z RRULE:FREQ=DAILY\;COUNT=3 END:VEVENT
  run busyw "$cal" 2026-10-01T00:00:00Z 2026-12-01T00:00:00Z
  [ "${#lines[@]}" -eq 3 ]
  [ "${lines[0]}" = "$(rr 2026-10-19T09:00:00Z 2026-10-19T09:30:00Z)" ]
  [ "${lines[2]}" = "$(rr 2026-10-21T09:00:00Z 2026-10-21T09:30:00Z)" ]
}

@test "a weekly rule honours BYDAY" {
  mk BEGIN:VEVENT DTSTART:20261019T090000Z DTEND:20261019T100000Z RRULE:FREQ=WEEKLY\;BYDAY=MO,WE\;COUNT=4 END:VEVENT
  run busyw "$cal" 2026-10-01T00:00:00Z 2026-12-01T00:00:00Z
  [ "${#lines[@]}" -eq 4 ]
  [ "${lines[0]}" = "$(rr 2026-10-19T09:00:00Z 2026-10-19T10:00:00Z)" ]
  [ "${lines[1]}" = "$(rr 2026-10-21T09:00:00Z 2026-10-21T10:00:00Z)" ]
  [ "${lines[2]}" = "$(rr 2026-10-26T09:00:00Z 2026-10-26T10:00:00Z)" ]
  [ "${lines[3]}" = "$(rr 2026-10-28T09:00:00Z 2026-10-28T10:00:00Z)" ]
}

@test "INTERVAL skips periods and a weekly rule defaults to the start weekday" {
  mk BEGIN:VEVENT DTSTART:20261021T090000Z DTEND:20261021T100000Z RRULE:FREQ=WEEKLY\;INTERVAL=2\;COUNT=3 END:VEVENT
  run busyw "$cal" 2026-10-01T00:00:00Z 2026-12-31T00:00:00Z
  [ "${lines[0]}" = "$(rr 2026-10-21T09:00:00Z 2026-10-21T10:00:00Z)" ]
  [ "${lines[1]}" = "$(rr 2026-11-04T09:00:00Z 2026-11-04T10:00:00Z)" ]
  [ "${lines[2]}" = "$(rr 2026-11-18T09:00:00Z 2026-11-18T10:00:00Z)" ]
}

@test "a monthly rule skips months that lack the day" {
  mk BEGIN:VEVENT DTSTART:20260131T090000Z DTEND:20260131T100000Z RRULE:FREQ=MONTHLY\;COUNT=3 END:VEVENT
  run busyw "$cal" 2026-01-01T00:00:00Z 2026-12-31T00:00:00Z
  [ "${lines[1]}" = "$(rr 2026-03-31T09:00:00Z 2026-03-31T10:00:00Z)" ]
  [ "${lines[2]}" = "$(rr 2026-05-31T09:00:00Z 2026-05-31T10:00:00Z)" ]
}

@test "a monthly rule honours BYMONTHDAY" {
  mk BEGIN:VEVENT DTSTART:20261001T090000Z DTEND:20261001T100000Z RRULE:FREQ=MONTHLY\;BYMONTHDAY=1,15\;COUNT=4 END:VEVENT
  run busyw "$cal" 2026-10-01T00:00:00Z 2027-12-31T00:00:00Z
  [ "${lines[1]}" = "$(rr 2026-10-15T09:00:00Z 2026-10-15T10:00:00Z)" ]
  [ "${lines[2]}" = "$(rr 2026-11-01T09:00:00Z 2026-11-01T10:00:00Z)" ]
}

@test "a yearly rule repeats on the same date" {
  mk BEGIN:VEVENT DTSTART\;VALUE=DATE:20261105 RRULE:FREQ=YEARLY\;COUNT=2 END:VEVENT
  run busyw "$cal" 2026-01-01T00:00:00Z 2029-01-01T00:00:00Z
  [ "${lines[0]}" = "$(rr 2026-11-05T00:00:00Z 2026-11-06T00:00:00Z)" ]
  [ "${lines[1]}" = "$(rr 2027-11-05T00:00:00Z 2027-11-06T00:00:00Z)" ]
}

@test "UNTIL ends a series, with a date or a time" {
  mk BEGIN:VEVENT DTSTART:20261019T090000Z DTEND:20261019T100000Z RRULE:FREQ=DAILY\;UNTIL=20261021T090000Z END:VEVENT \
    BEGIN:VEVENT DTSTART:20261019T120000Z DTEND:20261019T130000Z RRULE:FREQ=DAILY\;UNTIL=20261020 END:VEVENT
  run busyw "$cal" 2026-10-01T00:00:00Z 2026-12-01T00:00:00Z
  [ "${#lines[@]}" -eq 5 ]
}

@test "EXDATE removes single occurrences" {
  mk BEGIN:VEVENT DTSTART:20261019T090000Z DTEND:20261019T100000Z RRULE:FREQ=DAILY\;COUNT=3 EXDATE:20261020T090000Z END:VEVENT
  run busyw "$cal" 2026-10-01T00:00:00Z 2026-12-01T00:00:00Z
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[1]}" = "$(rr 2026-10-21T09:00:00Z 2026-10-21T10:00:00Z)" ]
}

@test "an endless rule stops at the window, and earlier occurrences are not printed" {
  mk BEGIN:VEVENT DTSTART:20260105T090000Z DTEND:20260105T100000Z RRULE:FREQ=WEEKLY END:VEVENT
  run busyw "$cal" 2026-10-19T00:00:00Z 2026-11-02T00:00:00Z
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "$(rr 2026-10-19T09:00:00Z 2026-10-19T10:00:00Z)" ]
  [ "${lines[1]}" = "$(rr 2026-10-26T09:00:00Z 2026-10-26T10:00:00Z)" ]
}

@test "a rule this parser cannot expand warns and keeps the first occurrence" {
  mk BEGIN:VEVENT DTSTART:20261019T090000Z DTEND:20261019T100000Z RRULE:FREQ=MONTHLY\;BYDAY=1MO END:VEVENT
  run busyw "$cal" 2026-10-01T00:00:00Z 2026-12-01T00:00:00Z
  [[ "$output" == *"tm: cannot expand RRULE FREQ=MONTHLY;BYDAY=1MO"* ]]
  [[ "$output" == *"$(rr 2026-10-19T09:00:00Z 2026-10-19T10:00:00Z)"* ]]
}
