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
