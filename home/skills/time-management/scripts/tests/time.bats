#!/usr/bin/env bats

load helpers

# t_awk '<expr>': print an awk expression using lib/time.awk.
t_awk() {
  awk -f "$scripts_dir/lib/time.awk" -f <(printf 'BEGIN { print %s }\n' "$1")
}

setup() {
  tm_setup
}

@test "iso2epoch parses extended UTC timestamps" {
  run t_awk 'iso2epoch("1970-01-01T00:00:00Z")'
  [ "$output" = "0" ]
  run t_awk 'iso2epoch("2026-10-21T14:30:15Z")'
  [ "$output" = "1792593015" ]
}

@test "iso2epoch parses ics basic form, floating time and bare dates" {
  run t_awk 'iso2epoch("20261021T143015Z")'
  [ "$output" = "1792593015" ]
  run t_awk 'iso2epoch("20261021T143015")'
  [ "$output" = "1792593015" ]
  run t_awk 'iso2epoch("2026-10-21")'
  [ "$output" = "1792540800" ]
  run t_awk 'iso2epoch("20261021")'
  [ "$output" = "1792540800" ]
}

@test "iso2epoch handles leap days and returns -1 for junk" {
  run t_awk 'iso2epoch("2028-02-29T00:00:00Z")'
  [ "$output" = "1835395200" ]
  run t_awk 'iso2epoch("not a date")'
  [ "$output" = "-1" ]
  run t_awk 'iso2epoch("")'
  [ "$output" = "-1" ]
}

@test "iso2epoch rejects days that do not exist in the month" {
  run t_awk 'iso2epoch("2026-02-31T00:00:00Z")'
  [ "$output" = "-1" ]
  run t_awk 'iso2epoch("2026-04-31")'
  [ "$output" = "-1" ]
  run t_awk 'iso2epoch("2027-02-29")'
  [ "$output" = "-1" ]
  run t_awk 'iso2epoch("2026-12-31")'
  [ "$output" = "1798675200" ]
}

@test "epoch2iso round-trips" {
  run t_awk 'epoch2iso(1792593015)'
  [ "$output" = "2026-10-21T14:30:15Z" ]
  run t_awk 'epoch2iso(iso2epoch("2028-02-29T23:59:00Z"))'
  [ "$output" = "2028-02-29T23:59:00Z" ]
}

@test "weekday is 1 for Monday through 7 for Sunday" {
  run t_awk 'weekday(iso2epoch("2026-10-19T12:00:00Z"))'
  [ "$output" = "1" ]
  run t_awk 'weekday(iso2epoch("2026-10-25T12:00:00Z"))'
  [ "$output" = "7" ]
}
