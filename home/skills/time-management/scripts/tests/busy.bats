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

@test "events come out in file order, unsorted" {
  mk BEGIN:VEVENT DTSTART:20261021T130000Z DTEND:20261021T140000Z END:VEVENT \
    BEGIN:VEVENT DTSTART:20261021T090000Z DTEND:20261021T100000Z END:VEVENT
  run busy "$cal"
  [ "${lines[0]}" = "$(printf '2026-10-21T13:00:00Z\t2026-10-21T14:00:00Z')" ]
}
