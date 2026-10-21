#!/usr/bin/env bats

load helpers

# ics_out: slot lines on stdin -> an .ics with CRLF line endings.
ics_out() {
  LC_ALL=C awk -v now=1792540800 -f "$scripts_dir/lib/time.awk" -f "$scripts_dir/lib/ics-out.awk"
}

setup() {
  tm_setup
}

slot() { printf 'slot\t%s\t%s\t%s\t%s\t%s\n' "$@"; }

@test "an empty plan is still a valid calendar" {
  run ics_out </dev/null
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//time-management//tm//EN\r\nCALSCALE:GREGORIAN\r\nEND:VCALENDAR\r')" ]
}

@test "a slot becomes a VEVENT with a stable UID, UTC times and DTSTAMP from now" {
  run ics_out < <(slot 12 2026-10-21T09:00:00Z 2026-10-21T10:00:00Z "Write docs" "")
  [[ "$output" == *$'BEGIN:VEVENT\r'* ]]
  [[ "$output" == *$'UID:tm-12-1@time-management\r'* ]]
  [[ "$output" == *$'DTSTAMP:20261021T000000Z\r'* ]]
  [[ "$output" == *$'DTSTART:20261021T090000Z\r'* ]]
  [[ "$output" == *$'DTEND:20261021T100000Z\r'* ]]
  [[ "$output" == *$'SUMMARY:12 Write docs\r'* ]]
  [[ "$output" == *$'END:VEVENT\r'* ]]
}

@test "chunks of one task get numbered UIDs and summaries" {
  run ics_out < <(slot 7 2026-10-21T09:00:00Z 2026-10-21T10:30:00Z Big "chunk 1/2"; slot 7 2026-10-22T09:00:00Z 2026-10-22T09:30:00Z Big "chunk 2/2,late")
  [[ "$output" == *$'UID:tm-7-1@time-management\r'* ]]
  [[ "$output" == *$'UID:tm-7-2@time-management\r'* ]]
  [[ "$output" == *$'SUMMARY:7 Big (1/2)\r'* ]]
  [[ "$output" == *$'SUMMARY:7 Big (2/2)\r'* ]]
  [[ "$output" == *$'DESCRIPTION:chunk 2/2\\,late\r'* ]]
}

@test "text is escaped" {
  run ics_out < <(slot 1 2026-10-21T09:00:00Z 2026-10-21T10:00:00Z 'a, b; c \ d' "")
  [[ "$output" == *$'SUMMARY:1 a\\, b\\; c \\\\ d\r'* ]]
}

@test "long lines are folded at 75 octets with a leading space" {
  title="$(printf 'word%.0s ' $(seq 1 30))"
  out="$(slot 1 2026-10-21T09:00:00Z 2026-10-21T10:00:00Z "$title" "" | ics_out)"
  # every line is at most 75 octets plus the CR
  printf '%s\n' "$out" | LC_ALL=C awk 'length($0) > 76 { bad = 1 } END { exit bad }'
  # unfolding gives the full summary back
  unfolded="$(printf '%s\n' "$out" | awk '{ sub(/\r$/, ""); if (/^ /) buf = buf substr($0, 2); else { if (NR > 1) print buf; buf = $0 } } END { print buf }')"
  [[ "$unfolded" == *"SUMMARY:1 $title"* ]]
}

@test "folding never splits a multibyte character" {
  title="$(printf 'é%.0s' $(seq 1 60))"
  out="$(slot 1 2026-10-21T09:00:00Z 2026-10-21T10:00:00Z "$title" "" | LC_ALL=C ics_out)"
  unfolded="$(printf '%s\n' "$out" | awk '{ sub(/\r$/, ""); if (/^ /) buf = buf substr($0, 2); else { if (NR > 1) print buf; buf = $0 } } END { print buf }')"
  [[ "$unfolded" == *"SUMMARY:1 $title"* ]]
  # a continuation line may not start on a UTF-8 continuation byte (0x80-0xBF)
  printf '%s\n' "$out" | LC_ALL=C awk 'BEGIN { for (c = 128; c < 192; c++) cont[sprintf("%c", c)] = 1 }
    /^ / && (substr($0, 2, 1) in cont) { bad = 1 } END { exit bad }'
  [ "$(printf '%s\n' "$out" | grep -c '^ ')" -ge 1 ]
}

@test "lines that are not slots are ignored" {
  run ics_out < <(printf '# backend=x\nskip\t1\tT\tblocked by 2\n'; slot 3 2026-10-21T09:00:00Z 2026-10-21T10:00:00Z Three "")
  [ "$(printf '%s\n' "$output" | grep -c 'BEGIN:VEVENT')" -eq 1 ]
}
