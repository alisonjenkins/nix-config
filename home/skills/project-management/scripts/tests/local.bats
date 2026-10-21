#!/usr/bin/env bats

load helpers

setup() {
  pm_setup
  dir="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$dir"
  cat >"$dir/tasks.md" <<'EOF'
# Tasks
- [X] T001 [P] [US1] Set up repo owner:ali est:30 prio:1
- [ ] T002 Write docs deps:T001,T003 due:2026-11-01T00:00:00Z
- [ ] T003 [US2] Do thing prio:2
- [ ] pm:plan-x Plain item
EOF
  L=(bash "$pm" -b l -d "$dir")
}

@test "the local backend needs -d" {
  run bash "$pm" -b l list
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs -d <dir>"* ]]
}

@test "the local backend reports a missing tasks.md" {
  run bash "$pm" -b l -d "$BATS_TEST_TMPDIR/empty" list
  [ "$status" -eq 1 ]
  [[ "$output" == *"no tasks.md in"* ]]
}

@test "list defaults to open tasks and prints the header" {
  run "${L[@]}" list
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "# backend=local dir=$dir" ]
  [ "${lines[1]}" = "$(printf 'T002\topen\tWrite docs\t\tT001,T003\t2026-11-01T00:00:00Z\t\t')" ]
  [ "${#lines[@]}" -eq 4 ]
}

@test "list --state all and done" {
  run "${L[@]}" list --state all
  [ "${#lines[@]}" -eq 5 ]
  run "${L[@]}" list --state done
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[1]}" == T001* ]]
}

@test "list --assignee and --due-before" {
  run "${L[@]}" list --state all --assignee ali
  [ "${#lines[@]}" -eq 2 ]
  run "${L[@]}" list --due-before 2026-12-01T00:00:00Z
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[1]}" == T002* ]]
}

@test "list rejects a flag the local backend cannot honour" {
  run "${L[@]}" list --label x
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsupported argument '--label' for the local backend"* ]]
}

@test "list rejects a bad --state" {
  run "${L[@]}" list --state bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"--state must be open, done or all"* ]]
}

@test "status counts, blocked and next" {
  run "${L[@]}" status
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "# backend=local dir=$dir" ]
  [ "${lines[1]}" = "open=3 done=1 blocked=1 stale=n/a" ]
  [ "${lines[2]}" = "$(printf 'next\tT003\tDo thing')" ]
}

@test "show prints labelled fields" {
  run "${L[@]}" show T002
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "$(printf 'id\tT002')" ]
  [ "${lines[5]}" = "$(printf 'deps\tT001,T003')" ]
  [ "${lines[6]}" = "$(printf 'due\t2026-11-01T00:00:00Z')" ]
}

@test "show fails for an unknown id" {
  run "${L[@]}" show T404
  [ "$status" -eq 1 ]
  [[ "$output" == *"no task T404"* ]]
}

@test "update flips the checkbox and is idempotent" {
  run "${L[@]}" update T002 --state done
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "updated T002 state=done" ]
  grep -q '^- \[X\] T002 Write docs' "$dir/tasks.md"
  run "${L[@]}" update T002 --state done
  [ "${lines[1]}" = "unchanged T002 state=done" ]
  run "${L[@]}" update T001 --state open
  [ "${lines[1]}" = "updated T001 state=open" ]
  grep -q '^- \[ \] T001 \[P\]' "$dir/tasks.md"
}

@test "update fails for an unknown id, a bad state and unsupported flags" {
  before="$(cat "$dir/tasks.md")"
  run "${L[@]}" update T404 --state done
  [ "$status" -eq 1 ]
  [[ "$output" == *"no task T404"* ]]
  run "${L[@]}" update T002 --state bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"--state must be open or done"* ]]
  run "${L[@]}" update T002 --comment hi
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsupported argument '--comment' for the local backend"* ]]
  run "${L[@]}" update T002
  [ "$status" -eq 1 ]
  [[ "$output" == *"--state is required"* ]]
  [ "$(cat "$dir/tasks.md")" = "$before" ]
}
