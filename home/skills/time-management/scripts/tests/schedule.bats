#!/usr/bin/env bats

load helpers

# sched [-v k=v ...]: schedule $BATS_TEST_TMPDIR/tasks.tsv, now = Monday 2026-10-19 08:00Z.
# Awk variables: now days hs he tz wdmin wdmax chunk gap defest busyfile (minutes, except now).
epoch() {
  awk -f "$scripts_dir/lib/time.awk" -f <(printf 'BEGIN { print iso2epoch("%s") }\n' "$1")
}

sched() {
  awk -v now="$(epoch 2026-10-19T08:00:00Z)" \
    "$@" -f "$scripts_dir/lib/time.awk" -f "$scripts_dir/lib/schedule.awk" "$BATS_TEST_TMPDIR/tasks.tsv"
}

# task <id> <title> [state] [deps] [due] [est] [prio]: append a row.
task() {
  printf '%s\t%s\t%s\t\t%s\t%s\t%s\t%s\n' "$1" "${3:-open}" "$2" "${4:-}" "${5:-}" "${6:-}" "${7:-}" >>"$BATS_TEST_TMPDIR/tasks.tsv"
}

slot() { printf 'slot\t%s\t%s\t%s\t%s\t%s' "$@"; }

setup() {
  tm_setup
  : >"$BATS_TEST_TMPDIR/tasks.tsv"
}

@test "one task goes into the first free working slot" {
  task 1 "Write docs" open "" "" 60
  run sched
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(slot 1 2026-10-19T09:00:00Z 2026-10-19T10:00:00Z 'Write docs' '')" ]
  [ "${lines[1]}" = "# scheduled=1 chunks=1 late=0 skipped=0 unscheduled=0" ]
}

@test "ranking is due date, then prio, then input order; no due goes last" {
  task A "No due" open "" "" 30 1
  task B "Due later" open "" 2026-10-30T00:00:00Z 30
  task C "Due soon" open "" 2026-10-22T00:00:00Z 30
  task D "Due soon, better prio" open "" 2026-10-22T00:00:00Z 30 1
  task E "Due soon, same prio" open "" 2026-10-22T00:00:00Z 30 1
  run sched
  [[ "${lines[0]}" == slot$'\t'D$'\t'* ]]
  [[ "${lines[1]}" == slot$'\t'E$'\t'* ]]
  [[ "${lines[2]}" == slot$'\t'C$'\t'* ]]
  [[ "${lines[3]}" == slot$'\t'B$'\t'* ]]
  [[ "${lines[4]}" == slot$'\t'A$'\t'* ]]
}

@test "back-to-back tasks are separated by the gap" {
  task 1 One open "" "" 60
  task 2 Two open "" "" 60
  run sched
  [ "${lines[1]}" = "$(slot 2 2026-10-19T10:10:00Z 2026-10-19T11:10:00Z Two '')" ]
}

@test "a long task is cut into chunks of at most --chunk minutes" {
  task 1 Big open "" "" 200
  run sched
  [ "${lines[0]}" = "$(slot 1 2026-10-19T09:00:00Z 2026-10-19T10:30:00Z Big 'chunk 1/3')" ]
  [ "${lines[1]}" = "$(slot 1 2026-10-19T10:40:00Z 2026-10-19T12:10:00Z Big 'chunk 2/3')" ]
  [ "${lines[2]}" = "$(slot 1 2026-10-19T12:20:00Z 2026-10-19T12:40:00Z Big 'chunk 3/3')" ]
}

@test "busy time is planned around" {
  printf '2026-10-19T09:00:00Z\t2026-10-19T10:00:00Z\n' >"$BATS_TEST_TMPDIR/busy.tsv"
  task 1 One open "" "" 60
  run sched -v busyfile="$BATS_TEST_TMPDIR/busy.tsv"
  [ "${lines[0]}" = "$(slot 1 2026-10-19T10:00:00Z 2026-10-19T11:00:00Z One '')" ]
}

@test "a task is split across the day boundary rather than across busy time" {
  printf '2026-10-19T09:00:00Z\t2026-10-19T16:00:00Z\n' >"$BATS_TEST_TMPDIR/busy.tsv"
  task 1 One open "" "" 90
  run sched -v busyfile="$BATS_TEST_TMPDIR/busy.tsv"
  [ "${lines[0]}" = "$(slot 1 2026-10-19T16:00:00Z 2026-10-19T17:00:00Z One 'chunk 1/2')" ]
  [ "${lines[1]}" = "$(slot 1 2026-10-20T09:00:00Z 2026-10-20T09:30:00Z One 'chunk 2/2')" ]
}

@test "a free stretch under 15 minutes is skipped" {
  printf '2026-10-19T09:00:00Z\t2026-10-19T16:50:00Z\n' >"$BATS_TEST_TMPDIR/busy.tsv"
  task 1 One open "" "" 60
  run sched -v busyfile="$BATS_TEST_TMPDIR/busy.tsv"
  [ "${lines[0]}" = "$(slot 1 2026-10-20T09:00:00Z 2026-10-20T10:00:00Z One '')" ]
}

@test "weekends are skipped" {
  task 1 One open "" "" 120
  run sched -v now="$(epoch 2026-10-23T16:00:00Z)"
  [ "${lines[0]}" = "$(slot 1 2026-10-23T16:00:00Z 2026-10-23T17:00:00Z One 'chunk 1/2')" ]
  [ "${lines[1]}" = "$(slot 1 2026-10-26T09:00:00Z 2026-10-26T10:00:00Z One 'chunk 2/2')" ]
}

@test "the start is rounded up to 5 minutes" {
  task 1 One open "" "" 30
  run sched -v now="$(epoch 2026-10-19T10:02:00Z)"
  [ "${lines[0]}" = "$(slot 1 2026-10-19T10:05:00Z 2026-10-19T10:35:00Z One '')" ]
}

@test "a task that ends after its due date is marked late, not dropped" {
  task 1 One open "" 2026-10-19T09:30:00Z 60
  run sched
  [ "${lines[0]}" = "$(slot 1 2026-10-19T09:00:00Z 2026-10-19T10:00:00Z One late)" ]
  [ "${lines[1]}" = "# scheduled=1 chunks=1 late=1 skipped=0 unscheduled=0" ]
}

@test "a date-only due date means the end of that day" {
  task 1 Today open "" 2026-10-19 60
  task 2 Yesterday open "" 2026-10-18 60
  run sched
  [[ "${lines[0]}" == slot$'\t'2$'\t'*late ]]
  [ "${lines[1]}" = "$(slot 1 2026-10-19T10:10:00Z 2026-10-19T11:10:00Z Today '')" ]
}

@test "a row with no est gets the default and says so" {
  task 1 One
  run sched
  [ "${lines[0]}" = "$(slot 1 2026-10-19T09:00:00Z 2026-10-19T09:30:00Z One est-default)" ]
}

@test "a task blocked by an open task is skipped; done rows and done deps are ignored" {
  task 1 First
  task 2 Second open 1 "" 30
  task 3 Third open 4 "" 30
  task 4 Fourth done
  run sched
  [[ "$output" == *$'skip\t2\tSecond\tblocked by 1'* ]]
  [[ "$output" == *$'slot\t3\t'* ]]
  [[ "$output" != *$'\t4\t'* ]]
  [[ "$output" == *"skipped=1"* ]]
}

@test "a task with no room in the horizon is unscheduled and takes no time" {
  task 1 Huge open "" "" 6000
  task 2 Small open "" "" 30
  run sched -v days=2
  [[ "$output" == *$'unscheduled\t1\tHuge\tno room in 2 days'* ]]
  [[ "$output" == *$'slot\t2\t2026-10-19T09:00:00Z\t'* ]]
  [[ "$output" == *"unscheduled=1" ]]
}

@test "a UTC offset moves the working window" {
  task 1 One open "" "" 60
  run sched -v tz=60
  [ "${lines[0]}" = "$(slot 1 2026-10-19T08:00:00Z 2026-10-19T09:00:00Z One '')" ]
}

@test "custom hours, weekdays, chunk and gap are honoured" {
  task 1 One open "" "" 100
  run sched -v hs=600 -v he=720 -v chunk=60 -v gap=0
  [ "${lines[0]}" = "$(slot 1 2026-10-19T10:00:00Z 2026-10-19T11:00:00Z One 'chunk 1/2')" ]
  [ "${lines[1]}" = "$(slot 1 2026-10-19T11:00:00Z 2026-10-19T11:40:00Z One 'chunk 2/2')" ]
}

@test "slots print in time order even when a lower-ranked task fits earlier" {
  printf '2026-10-19T09:10:00Z\t2026-10-19T17:00:00Z\n' >"$BATS_TEST_TMPDIR/busy.tsv"
  task 1 Urgent open "" 2026-10-19T00:00:00Z 60
  task 2 Quick open "" 2026-10-30T00:00:00Z 10
  run sched -v busyfile="$BATS_TEST_TMPDIR/busy.tsv"
  [ "${lines[0]}" = "$(slot 2 2026-10-19T09:00:00Z 2026-10-19T09:10:00Z Quick '')" ]
  [[ "${lines[1]}" == slot$'\t'1$'\t'2026-10-20T09:00:00Z* ]]
}
