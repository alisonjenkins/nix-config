#!/usr/bin/env bats

load helpers

setup() {
  tm_setup
  rows="$BATS_TEST_TMPDIR/rows.tsv"
  {
    printf '# backend=github repo=owner/name\n'
    printf '1\topen\tWrite docs\t\t\t2026-10-30T00:00:00Z\t60\t2\n'
    printf '2\topen\tShip it\t\t1\t2026-10-22T00:00:00Z\t30\t1\n'
    printf '3\topen\tFix bug\t\t\t2026-10-20T00:00:00Z\t45\t\n'
    printf '4\tdone\tOld thing\t\t\t\t\t\n'
  } >"$rows"
  now=2026-10-19T08:00:00Z
}

@test "-b is required and unknown backends are rejected" {
  run bash "$tm" plan --from "$rows"
  [ "$status" -eq 1 ]
  [[ "$output" == *"-b required: g|google i|ics"* ]]
  run bash "$tm" -b nope plan --from "$rows"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown backend 'nope'"* ]]
}

@test "the google backend is a stub that points at ics" {
  run bash "$tm" -b g plan --from "$rows"
  [ "$status" -eq 1 ]
  [[ "$output" == *"google backend is not implemented; use -b i"* ]]
}

@test "plan prints the header, the slots, skips and a summary" {
  run bash "$tm" -b i plan --from "$rows" --now "$now"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "# backend=ics from=$rows now=$now" ]
  [ "${lines[1]}" = "$(printf 'slot\t3\t2026-10-19T09:00:00Z\t2026-10-19T09:45:00Z\tFix bug\t')" ]
  [[ "$output" == *$'skip\t2\tShip it\tblocked by 1'* ]]
  [ "${lines[$((${#lines[@]} - 1))]}" = "# scheduled=2 chunks=2 late=0 skipped=1 unscheduled=0" ]
}

@test "plan reads stdin when there is no --from" {
  run bash "$tm" -b i plan --now "$now" <"$rows"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "# backend=ics from=stdin now=$now" ]
}

@test "--busy files are planned around, more than one allowed" {
  printf 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nDTSTART:20261019T090000Z\r\nDTEND:20261019T100000Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n' >"$BATS_TEST_TMPDIR/a.ics"
  printf 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nDTSTART:20261019T100000Z\r\nDTEND:20261019T110000Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n' >"$BATS_TEST_TMPDIR/b.ics"
  run bash "$tm" -b i plan --from "$rows" --now "$now" --busy "$BATS_TEST_TMPDIR/a.ics" --busy "$BATS_TEST_TMPDIR/b.ics"
  [ "${lines[1]}" = "$(printf 'slot\t3\t2026-10-19T11:00:00Z\t2026-10-19T11:45:00Z\tFix bug\t')" ]
}

@test "--ics writes a calendar with one event per chunk and prints the plan too" {
  out="$BATS_TEST_TMPDIR/plan.ics"
  run bash "$tm" -b i plan --from "$rows" --now "$now" --ics "$out"
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "$(printf 'slot\t3\t2026-10-19T09:00:00Z\t2026-10-19T09:45:00Z\tFix bug\t')" ]
  [ "$(grep -c 'BEGIN:VEVENT' "$out")" -eq 2 ]
  grep -q 'UID:tm-3-1@time-management' "$out"
  grep -q 'DTSTAMP:20261019T080000Z' "$out"
  grep -q $'\r$' "$out"
}

@test "re-running with the same input writes an identical calendar" {
  bash "$tm" -b i plan --from "$rows" --now "$now" --ics "$BATS_TEST_TMPDIR/1.ics" >/dev/null
  bash "$tm" -b i plan --from "$rows" --now "$now" --ics "$BATS_TEST_TMPDIR/2.ics" >/dev/null
  cmp "$BATS_TEST_TMPDIR/1.ics" "$BATS_TEST_TMPDIR/2.ics"
}

@test "scheduling options reach the scheduler" {
  run bash "$tm" -b i plan --from "$rows" --now "$now" --hours 13:00-15:00 --tz +01:00 --chunk 30 --gap 0 --default-est 20 --days 3 --weekdays 1-1
  [ "$status" -eq 0 ]
  # 13:00 at +01:00 is 12:00Z; the 45 minute task is cut into 30 + 15
  [ "${lines[1]}" = "$(printf 'slot\t3\t2026-10-19T12:00:00Z\t2026-10-19T12:30:00Z\tFix bug\tchunk 1/2')" ]
}

@test "bad input fails before anything is written" {
  out="$BATS_TEST_TMPDIR/never.ics"
  for bad in "--now junk" "--hours 25:00-26:00" "--hours 17:00-09:00" "--hours nine" "--tz 1" "--tz +25:00" "--days 0" "--days 367" "--chunk 0" "--gap -1" "--weekdays 0-9" "--weekdays 5-1" "--default-est 0" "--bogus 1"; do
    # shellcheck disable=SC2086
    run bash "$tm" -b i plan --from "$rows" --ics "$out" $bad
    [ "$status" -eq 1 ] || { echo "accepted: $bad"; return 1; }
  done
  run bash "$tm" -b i plan --from "$BATS_TEST_TMPDIR/missing.tsv" --ics "$out"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot read"* ]]
  run bash "$tm" -b i plan --from "$rows" --busy "$BATS_TEST_TMPDIR/missing.ics" --ics "$out"
  [ "$status" -eq 1 ]
  [ ! -e "$out" ]
}

@test "--ics file mode follows the umask" {
  umask 022
  run bash "$tm" -b i plan --from "$rows" --now "$now" --ics "$BATS_TEST_TMPDIR/umask.ics"
  [ "$status" -eq 0 ]
  [ "$(ls -l "$BATS_TEST_TMPDIR/umask.ics" | cut -c1-10)" = "-rw-r--r--" ]
  umask 077
  run bash "$tm" -b i plan --from "$rows" --now "$now" --ics "$BATS_TEST_TMPDIR/private.ics"
  [ "$(ls -l "$BATS_TEST_TMPDIR/private.ics" | cut -c1-10)" = "-rw-------" ]
}

@test "numbers with leading zeros are decimal, not octal" {
  run bash "$tm" -b i plan --from "$rows" --now "$now" --days 8 --chunk 8 --gap 9
  [ "$status" -eq 0 ]
  want="$output"
  run bash "$tm" -b i plan --from "$rows" --now "$now" --days 08 --chunk 08 --gap 09
  [ "$status" -eq 0 ]
  [ "$output" = "$want" ]
  run bash "$tm" -b i plan --from "$rows" --now "$now" --default-est 08
  [ "$status" -eq 0 ]
  [[ "$output" != *"value too great"* ]]
}

@test "leading zeros do not slip past the limits" {
  run bash "$tm" -b i plan --from "$rows" --now "$now" --days 0400
  [ "$status" -eq 1 ]
  [[ "$output" == *"--days must be at most 366"* ]]
  [[ "$output" != *"value too great"* ]]
  run bash "$tm" -b i plan --from "$rows" --now "$now" --chunk 00
  [ "$status" -eq 1 ]
  [[ "$output" == *"--chunk must be a whole number >= 1"* ]]
}

@test "--ics leaves nothing but the calendar in its directory" {
  mkdir "$BATS_TEST_TMPDIR/out"
  run bash "$tm" -b i plan --from "$rows" --now "$now" --ics "$BATS_TEST_TMPDIR/out/plan.ics"
  [ "$status" -eq 0 ]
  [ "$(ls -A "$BATS_TEST_TMPDIR/out")" = "plan.ics" ]
}

@test "--days accepts the 366 day ceiling" {
  run bash "$tm" -b i plan --from "$rows" --now "$now" --days 366
  [ "$status" -eq 0 ]
}

@test "a flag without a value is an error" {
  run bash "$tm" -b i plan --from
  [ "$status" -eq 1 ]
  [[ "$output" == *"--from needs a value"* ]]
}

@test "the real backends have collision-free aliases" {
  run bash "$scripts_dir/lint-aliases.sh"
  [ "$status" -eq 0 ]
}

@test "every backend implements every verb" {
  local b v
  for b in "$scripts_dir"/backends/*/; do
    for v in plan; do
      [ -f "$b$v.sh" ] || { echo "missing: $b$v.sh"; return 1; }
    done
  done
}
