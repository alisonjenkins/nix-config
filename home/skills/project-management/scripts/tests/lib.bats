#!/usr/bin/env bats

load helpers

setup() {
  pm_setup
  # shellcheck source=/dev/null
  source "$scripts_dir/lib/common.sh"
  source "$scripts_dir/lib/tsv.sh"
  source "$scripts_dir/lib/tasks-md.sh"
  tasks="$BATS_TEST_TMPDIR/tasks.md"
  cat >"$tasks" <<'EOF'
# Tasks
- [X] T001 [P] [US1] Set up repo owner:ali est:30 prio:1
- [ ] T002 Write docs deps:T001,T003 due:2026-11-01T00:00:00Z
- [ ] T003 [US2] Do thing with `code` prio:2
- [ ] pm:plan-x Plain item
- [ ] not a task line
text
EOF
}

@test "pm_page slices rows and names the next offset" {
  run pm_page 3 0 < <(seq 7)
  [ "$output" = "$(printf '1\n2\n3\n# more=4 next-offset=3')" ]
  run pm_page 3 6 < <(seq 7)
  [ "$output" = "7" ]
}

@test "pm_page prints no footer for an exact fit, a past-the-end offset or no paging" {
  run pm_page 7 0 < <(seq 7)
  [ "${#lines[@]}" -eq 7 ]
  run pm_page 3 99 < <(seq 7)
  [ -z "$output" ]
  run pm_page "" 0 < <(seq 7)
  [ "${#lines[@]}" -eq 7 ]
}

@test "pm_page treats a leading-zero offset as decimal" {
  run pm_page 2 08 < <(seq 10)
  [ "$output" = "$(printf '9\n10')" ]
}

@test "pm_page_check accepts positive limits and numeric offsets only" {
  run pm_page_check "" 0
  [ "$status" -eq 0 ]
  run pm_page_check 5 08
  [ "$status" -eq 0 ]
  run pm_page_check 0 0
  [ "$status" -eq 1 ]
  [[ "$output" == *"--limit must be a positive number"* ]]
  run pm_page_check x 0
  [ "$status" -eq 1 ]
  run pm_page_check 5 -1
  [ "$status" -eq 1 ]
  [[ "$output" == *"--offset must be a number"* ]]
}

@test "tasks_md_tsv parses ids, markers, fields and titles" {
  run tasks_md_tsv "$tasks"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(printf 'T001\tdone\tSet up repo\tali\t\t\t30\t1')" ]
  [ "${lines[1]}" = "$(printf 'T002\topen\tWrite docs\t\tT001,T003\t2026-11-01T00:00:00Z\t\t')" ]
  [ "${lines[2]}" = "$(printf 'T003\topen\tDo thing with `code`\t\t\t\t\t2')" ]
  [ "${lines[3]}" = "$(printf 'pm:plan-x\topen\tPlain item\t\t\t\t\t')" ]
  [ "${#lines[@]}" -eq 4 ]
}

@test "tasks_md_raw keeps the original line" {
  run tasks_md_raw "$tasks"
  [ "${lines[0]}" = "$(printf 'T001\t- [X] T001 [P] [US1] Set up repo owner:ali est:30 prio:1')" ]
}

@test "pm_status_from_tsv counts, finds blocked and picks next" {
  run bash -c "source '$scripts_dir/lib/tasks-md.sh'; source '$scripts_dir/lib/tsv.sh'; tasks_md_tsv '$tasks' | pm_status_from_tsv n/a"
  [ "${lines[0]}" = "open=3 done=1 blocked=1 stale=n/a" ]
  [ "${lines[1]}" = "$(printf 'next\tT003\tDo thing with `code`')" ]
}

@test "pm_filter_tsv filters by state, assignee and due date and keeps # lines" {
  rows="$(printf '# backend=x\n'; tasks_md_tsv "$tasks")"
  run bash -c "source '$scripts_dir/lib/tsv.sh'; printf '%s\n' '$rows' | pm_filter_tsv done '' ''"
  [ "${lines[0]}" = "# backend=x" ]
  [ "${#lines[@]}" -eq 2 ]
  run bash -c "source '$scripts_dir/lib/tsv.sh'; printf '%s\n' '$rows' | pm_filter_tsv all ali ''"
  [ "${#lines[@]}" -eq 2 ]
  run bash -c "source '$scripts_dir/lib/tsv.sh'; printf '%s\n' '$rows' | pm_filter_tsv open '' 2026-12-01T00:00:00Z"
  [[ "${lines[1]}" == T002* ]]
  [ "${#lines[@]}" -eq 2 ]
}

@test "pm_row_to_kv labels the eight columns" {
  run bash -c "source '$scripts_dir/lib/tasks-md.sh'; source '$scripts_dir/lib/tsv.sh'; tasks_md_tsv '$tasks' | awk 'NR==2' | pm_row_to_kv"
  [ "${lines[0]}" = "$(printf 'id\tT002')" ]
  [ "${lines[4]}" = "$(printf 'deps\tT001,T003')" ]
  [ "${#lines[@]}" -eq 8 ]
}

@test "tasks_md_set_state flips the box, keeps mode, reports a missing id" {
  chmod 640 "$tasks"
  tasks_md_set_state "$tasks" T002 done
  grep -q '^- \[X\] T002 Write docs' "$tasks"
  tasks_md_set_state "$tasks" T001 open
  grep -q '^- \[ \] T001 \[P\]' "$tasks"
  [ "$(stat -c %a "$tasks" 2>/dev/null || stat -f %Lp "$tasks")" = "640" ]
  run tasks_md_set_state "$tasks" T999 done
  [ "$status" -eq 3 ]
}

@test "tasks_md_append adds a line even when the file lacks a final newline" {
  printf '%s' '- [ ] T001 One' >"$BATS_TEST_TMPDIR/n.md"
  tasks_md_append "$BATS_TEST_TMPDIR/n.md" '- [ ] T002 Two'
  [ "$(wc -l <"$BATS_TEST_TMPDIR/n.md" | tr -d ' ')" = "2" ]
  [ "$(tail -n1 "$BATS_TEST_TMPDIR/n.md")" = "- [ ] T002 Two" ]
}

@test "tasks_md_tsv handles a task with no title and does not confuse T001 with T0010" {
  printf -- '- [ ] T001\n- [ ] T0010 Ten\n' >"$BATS_TEST_TMPDIR/e.md"
  run tasks_md_tsv "$BATS_TEST_TMPDIR/e.md"
  [ "${lines[0]}" = "$(printf 'T001\topen\t\t\t\t\t\t')" ]
  [ "${lines[1]}" = "$(printf 'T0010\topen\tTen\t\t\t\t\t')" ]
  tasks_md_set_state "$BATS_TEST_TMPDIR/e.md" T001 done
  grep -q '^- \[X\] T001$' "$BATS_TEST_TMPDIR/e.md"
  grep -q '^- \[ \] T0010 Ten$' "$BATS_TEST_TMPDIR/e.md"
}

@test "tasks_md_tsv and tasks_md_set_state tolerate CRLF line endings" {
  printf -- '- [ ] T001 One prio:2\r\n- [ ] T002\r\n' >"$BATS_TEST_TMPDIR/c.md"
  run tasks_md_tsv "$BATS_TEST_TMPDIR/c.md"
  [ "${lines[0]}" = "$(printf 'T001\topen\tOne\t\t\t\t\t2')" ]
  [ "${lines[1]}" = "$(printf 'T002\topen\t\t\t\t\t\t')" ]
  tasks_md_set_state "$BATS_TEST_TMPDIR/c.md" T002 done
  grep -q '^- \[X\] T002' "$BATS_TEST_TMPDIR/c.md"
}

@test "tasks_md_set_state rejects a bad state and leaves no temp file behind" {
  run tasks_md_set_state "$tasks" T999 done
  [ "$status" -eq 3 ]
  run tasks_md_set_state "$tasks" T001 donee
  [ "$status" -eq 2 ]
  [ -z "$(ls "$BATS_TEST_TMPDIR" | grep 'tasks.md.')" ]
}
