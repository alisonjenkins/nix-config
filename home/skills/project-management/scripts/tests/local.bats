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

@test "list --limit and --offset page the rows" {
  run "${L[@]}" list --limit 2
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 4 ]
  [ "${lines[3]}" = "# more=1 next-offset=2" ]
  run "${L[@]}" list --limit 2 --offset 2
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[1]}" == pm:plan-x* ]]
}

@test "list rejects a bad --limit or --offset" {
  run "${L[@]}" list --limit 0
  [ "$status" -eq 1 ]
  [[ "$output" == *"--limit must be a positive number"* ]]
  run "${L[@]}" list --offset x
  [ "$status" -eq 1 ]
  [[ "$output" == *"--offset must be a number"* ]]
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

make_plan() {
  cat >"$BATS_TEST_TMPDIR/plan.md" <<'EOF'
- [ ] T003 [US2] Do thing prio:2
- [ ] T009 New task est:15
- [ ] pm:new-thing Another
EOF
}

@test "sync-plan dry run reports and changes nothing" {
  make_plan
  before="$(cat "$dir/tasks.md")"
  run "${L[@]}" sync-plan "$BATS_TEST_TMPDIR/plan.md"
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "$(printf 'exists\ttask\tT003\tDo thing')" ]
  [ "${lines[2]}" = "$(printf 'would-create\ttask\tT009\tNew task')" ]
  [ "${lines[3]}" = "$(printf 'would-create\ttask\tpm:new-thing\tAnother')" ]
  [ "$(cat "$dir/tasks.md")" = "$before" ]
}

@test "sync-plan --apply appends only missing tasks and is idempotent" {
  make_plan
  run "${L[@]}" sync-plan "$BATS_TEST_TMPDIR/plan.md" --apply
  [ "${lines[2]}" = "$(printf 'created\ttask\tT009\tNew task')" ]
  grep -q '^- \[ \] T009 New task est:15$' "$dir/tasks.md"
  [ "$(grep -c 'T003' "$dir/tasks.md")" -eq 2 ] # T003 plus the dep reference on T002
  run "${L[@]}" sync-plan "$BATS_TEST_TMPDIR/plan.md" --apply
  [ "${lines[2]}" = "$(printf 'exists\ttask\tT009\tNew task')" ]
}

@test "sync-plan on its own tasks.md changes nothing" {
  before="$(cat "$dir/tasks.md")"
  run "${L[@]}" sync-plan "$dir/tasks.md" --apply
  [ "$status" -eq 0 ]
  [[ "$output" != *"created"* ]]
  [ "$(cat "$dir/tasks.md")" = "$before" ]
}

@test "sync-plan creates tasks.md when the directory has none" {
  make_plan
  run bash "$pm" -b l -d "$BATS_TEST_TMPDIR/fresh" sync-plan "$BATS_TEST_TMPDIR/plan.md" --apply
  [ "$status" -eq 0 ]
  [ "$(grep -c '^- \[ \]' "$BATS_TEST_TMPDIR/fresh/tasks.md")" -eq 3 ]
}

@test "sync-plan rejects GitHub-only options" {
  run "${L[@]}" sync-plan "$dir/tasks.md" --per-task all
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsupported argument '--per-task' for the local backend"* ]]
}

@test "sync-plan dry run does not create the directory" {
  make_plan
  run bash "$pm" -b l -d "$BATS_TEST_TMPDIR/fresh2" sync-plan "$BATS_TEST_TMPDIR/plan.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"would-create"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/fresh2" ]
}

@test "sync-plan creates a duplicate id in the plan only once" {
  printf -- '- [ ] T009 One\n- [ ] T009 One again\n' >"$BATS_TEST_TMPDIR/dup.md"
  run "${L[@]}" sync-plan "$BATS_TEST_TMPDIR/dup.md" --apply
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "$(printf 'created\ttask\tT009\tOne')" ]
  [ "${lines[2]}" = "$(printf 'exists\ttask\tT009\tOne again')" ]
  [ "$(grep -c '^- \[ \] T009' "$dir/tasks.md")" -eq 1 ]
}

@test "the directory can come from --dir= or PM_DIR" {
  run bash "$pm" -b l --dir="$dir" list
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "# backend=local dir=$dir" ]]
  PM_DIR="$dir" run bash "$pm" -b l list
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "# backend=local dir=$dir" ]]
}

@test "status rejects an extra argument" {
  run "${L[@]}" status extra
  [ "$status" -eq 1 ]
  [[ "$output" == *"unexpected argument 'extra'"* ]]
}
