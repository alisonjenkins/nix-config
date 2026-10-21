#!/usr/bin/env bats

load helpers

setup() {
  pm_setup
  install_fake_gh
  fx="$FAKE_GH_FIXTURES"
  cat >"$fx/list.json" <<'EOF'
[
 {"number":1,"title":"Set up repo","state":"OPEN","assignees":[{"login":"ali"}],
  "labels":[{"name":"est:30"},{"name":"prio:1"}],"milestone":{"dueOn":"2026-11-01T00:00:00Z"},
  "updatedAt":"2020-01-01T00:00:00Z","body":"deps: #2, #3\nmore"},
 {"number":2,"title":"Write docs","state":"CLOSED","assignees":[],"labels":[],
  "milestone":null,"updatedAt":"2020-01-01T00:00:00Z","body":null},
 {"number":3,"title":"Third","state":"OPEN","assignees":[],"labels":[],
  "milestone":null,"updatedAt":"2099-01-01T00:00:00Z","body":""}
]
EOF
  G=(bash "$pm" -b g -r owner/name)
}

@test "the github backend needs a valid -r" {
  run bash "$pm" -b g list
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs -r owner/name"* ]]
  run bash "$pm" -b g -r nope list
  [ "$status" -eq 1 ]
  [[ "$output" == *"-r must be owner/name"* ]]
}

@test "list defaults to open issues" {
  run "${G[@]}" list
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "# backend=github repo=owner/name" ]
  [ "${lines[1]}" = "$(printf '1\topen\tSet up repo\tali\t2,3\t2026-11-01T00:00:00Z\t30\t1')" ]
  [ "${lines[2]}" = "$(printf '3\topen\tThird\t\t\t\t\t')" ]
  [ "${#lines[@]}" -eq 3 ]
  grep -q 'issue list -R owner/name --state open --limit 200 --json' "$fx/calls.log"
}

@test "list --state done maps to closed and --state all keeps both" {
  run "${G[@]}" list --state done
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[1]}" == 2* ]]
  grep -q -- '--state closed' "$fx/calls.log"
  run "${G[@]}" list --state all
  [ "${#lines[@]}" -eq 4 ]
}

@test "list passes label, milestone and assignee to gh and filters by due date" {
  run "${G[@]}" list --label bug --milestone M1 --assignee ali
  grep -q -- '--label bug' "$fx/calls.log"
  grep -q -- '--milestone M1' "$fx/calls.log"
  grep -q -- '--assignee ali' "$fx/calls.log"
  run "${G[@]}" list --due-before 2026-12-01T00:00:00Z
  [ "${#lines[@]}" -eq 2 ]
  run "${G[@]}" list --due-before 2026-01-01T00:00:00Z
  [ "${#lines[@]}" -eq 1 ]
}

@test "list warns when the result hit the cap" {
  jq -n '[range(0;200) | {number:., title:"t", state:"OPEN", assignees:[], labels:[], milestone:null, updatedAt:"2099-01-01T00:00:00Z", body:""}]' >"$fx/list.json"
  run "${G[@]}" list
  [[ "$output" == *"results truncated at 200 issues"* ]]
}

@test "list --assignee leaves the assignee filter to gh" {
  run "${G[@]}" list --assignee @me
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  grep -q -- '--assignee @me' "$fx/calls.log"
}

@test "status counts, stale, blocked and next" {
  run "${G[@]}" status
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "# backend=github repo=owner/name" ]
  [ "${lines[1]}" = "open=2 done=1 blocked=1 stale=1" ]
  [ "${lines[2]}" = "$(printf 'next\t3\tThird')" ]
}

make_view() { # make_view <state> <body-lines>
  jq -n --arg st "$1" --argjson n "$2" '{
    number:1, title:"Set up repo", state:$st, assignees:[{login:"ali"}],
    labels:[{name:"est:30"},{name:"prio:1"}], milestone:{dueOn:"2026-11-01T00:00:00Z"},
    updatedAt:"2020-01-01T00:00:00Z", url:"https://github.com/owner/name/issues/1",
    body:([range(0;$n) | "line \(.+1)"] | join("\n"))
  }' >"$fx/view.json"
}

@test "show prints labelled fields, url and a truncated body" {
  make_view OPEN 30
  run "${G[@]}" show 1
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "$(printf 'id\t1')" ]
  [ "${lines[2]}" = "$(printf 'state\topen')" ]
  [[ "$output" == *"url"*"https://github.com/owner/name/issues/1"* ]]
  [[ "$output" == *"line 20"* ]]
  [[ "$output" != *"line 21"* ]]
  [[ "$output" == *"truncated (30 lines); use --full"* ]]
}

@test "show --full prints the whole body" {
  make_view OPEN 30
  run "${G[@]}" show 1 --full
  [[ "$output" == *"line 30"* ]]
  [[ "$output" != *"truncated"* ]]
}

@test "show needs a numeric id" {
  run "${G[@]}" show abc
  [ "$status" -eq 1 ]
  [[ "$output" == *"need an issue number"* ]]
}

@test "update --state done closes an open issue" {
  make_view OPEN 1
  run "${G[@]}" update 1 --state done
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "updated 1 state=done" ]
  grep -q '^issue close 1 -R owner/name' "$fx/calls.log"
}

@test "update --state done on a closed issue changes nothing" {
  make_view CLOSED 1
  run "${G[@]}" update 1 --state done
  [ "${lines[1]}" = "unchanged 1" ]
  refute_mutated
}

@test "update --state open reopens a closed issue" {
  make_view CLOSED 1
  run "${G[@]}" update 1 --state open
  [ "${lines[1]}" = "updated 1 state=open" ]
  grep -q '^issue reopen 1 -R owner/name' "$fx/calls.log"
}

@test "update adds and removes labels and comments" {
  run "${G[@]}" update 1 --label blocked --unlabel ready --comment "waiting on 2"
  [ "${lines[1]}" = "updated 1 +blocked -ready comment" ]
  grep -q '^issue edit 1 -R owner/name --add-label blocked' "$fx/calls.log"
  grep -q '^issue edit 1 -R owner/name --remove-label ready' "$fx/calls.log"
  grep -q '^issue comment 1 -R owner/name --body waiting on 2' "$fx/calls.log"
}

@test "update needs an id, an action and a valid state" {
  run "${G[@]}" update
  [ "$status" -eq 1 ]
  run "${G[@]}" update 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing to do"* ]]
  run "${G[@]}" update 1 --state bogus
  [ "$status" -eq 1 ]
}

@test "update prints the header first and reports what was applied when a later step fails" {
  make_view OPEN 1
  FAKE_GH_FAIL_EDIT=1 run "${G[@]}" update 1 --state done --label nope
  [ "$status" -ne 0 ]
  [ "${lines[0]}" = "# backend=github repo=owner/name" ]
  [[ "$output" == *"partially applied: state=done"* ]]
  grep -q '^issue close 1 -R owner/name' "$fx/calls.log"
}

make_spec() {
  spec="$BATS_TEST_TMPDIR/specs/002-demo"
  mkdir -p "$spec"
  cat >"$spec/tasks.md" <<'EOF'
# Tasks
- [X] T001 [P] [US1] Set up repo
- [ ] T002 Write docs
- [ ] T003 [US2] Do thing
EOF
  tasks="$spec/tasks.md"
}

@test "sync-plan dry run plans an epic and mutates nothing" {
  make_spec
  run "${G[@]}" sync-plan "$tasks"
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "$(printf 'would-create\tepic\tpm:spec-002\t[spec-002] demo')" ]
  refute_mutated
}

@test "sync-plan --apply creates the epic with a task list and the marker" {
  make_spec
  run "${G[@]}" sync-plan "$tasks" --apply
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "$(printf 'created\tepic\tpm:spec-002\t#99')" ]
  grep -q '^label create pm-epic' "$fx/calls.log"
  grep -q 'issue create -R owner/name --title \[spec-002\] demo --body-file - --label pm-epic' "$fx/calls.log"
  grep -q '^<!-- pm:spec-002 -->$' "$fx/created-body.txt"
  grep -q '^Progress: 1 of 3 done$' "$fx/created-body.txt"
  grep -q '^- \[x\] T001 Set up repo$' "$fx/created-body.txt"
  grep -q '^- \[ \] T002 Write docs$' "$fx/created-body.txt"
}

@test "sync-plan finds the epic by marker and reports exists" {
  make_spec
  "${G[@]}" sync-plan "$tasks" --apply >/dev/null
  jq -n --rawfile b "$fx/created-body.txt" '[{number:99,state:"OPEN",body:$b}]' >"$fx/epics.json"
  : >"$fx/calls.log"
  run "${G[@]}" sync-plan "$tasks" --apply
  [ "${lines[1]}" = "$(printf 'exists\tepic\tpm:spec-002\t#99')" ]
  refute_mutated
}

@test "sync-plan updates the epic body in place when a box changes" {
  make_spec
  "${G[@]}" sync-plan "$tasks" --apply >/dev/null
  jq -n --rawfile b "$fx/created-body.txt" '[{number:99,state:"OPEN",body:$b}]' >"$fx/epics.json"
  sed -i.bak 's/^- \[ \] T002/- [X] T002/' "$tasks"
  : >"$fx/calls.log"
  run "${G[@]}" sync-plan "$tasks"
  [ "${lines[1]}" = "$(printf 'would-update\tepic\tpm:spec-002\t#99')" ]
  refute_mutated
  run "${G[@]}" sync-plan "$tasks" --apply
  [ "${lines[1]}" = "$(printf 'updated\tepic\tpm:spec-002\t#99')" ]
  grep -q '^issue edit 99 -R owner/name --body-file -' "$fx/calls.log"
  grep -q '^- \[x\] T002 Write docs$' "$fx/edited-body.txt"
  refute_logged 'issue create'
}

@test "sync-plan never modifies the input file" {
  make_spec
  before="$(cat "$tasks")"
  "${G[@]}" sync-plan "$tasks" --apply >/dev/null
  [ "$(cat "$tasks")" = "$before" ]
}

@test "sync-plan uses a plan marker outside a numbered spec directory" {
  mkdir -p "$BATS_TEST_TMPDIR/misc"
  printf -- '- [ ] pm:one Do it\n' >"$BATS_TEST_TMPDIR/misc/Launch_Plan.md"
  run "${G[@]}" sync-plan "$BATS_TEST_TMPDIR/misc/Launch_Plan.md"
  [ "${lines[1]}" = "$(printf 'would-create\tepic\tpm:plan-misc-launch-plan\t[plan] misc/Launch_Plan.md')" ]
}

@test "per-task sync-plan does not let gh swallow the loop's input" {
  make_spec
  FAKE_GH_READ_STDIN=1 run "${G[@]}" sync-plan "$tasks" --per-task all --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *$'created\ttask\tT001'* ]]
  [[ "$output" == *$'created\ttask\tT002'* ]]
  [[ "$output" == *$'created\ttask\tT003'* ]]
}

@test "per-task closing does not swallow the loop's input either" {
  per_task_fixture
  FAKE_GH_READ_STDIN=1 run "${G[@]}" sync-plan "$tasks" --per-task all --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *$'updated\ttask\tT001'* ]]
  [[ "$output" == *$'drift\ttask\tT002'* ]]
  [[ "$output" == *$'created\ttask\tT003'* ]]
}

@test "a duplicate id in the tasks file creates one issue" {
  mkdir -p "$BATS_TEST_TMPDIR/specs/003-dup"
  printf -- '- [ ] T009 One\n- [ ] T009 One again\n' >"$BATS_TEST_TMPDIR/specs/003-dup/tasks.md"
  run "${G[@]}" sync-plan "$BATS_TEST_TMPDIR/specs/003-dup/tasks.md" --per-task all --apply
  [ "$status" -eq 0 ]
  [ "$(grep -c '^issue create .*--title T009' "$fx/calls.log")" -eq 1 ]
  [[ "$output" == *$'exists\ttask\tT009\tduplicate id in file'* ]]
}

@test "a pm: id does not match a longer pm: id's issue" {
  mkdir -p "$BATS_TEST_TMPDIR/misc"
  printf -- '- [ ] pm:a Short\n' >"$BATS_TEST_TMPDIR/misc/plan.md"
  echo '[{"number":5,"title":"pm:a-b: Other","state":"OPEN"}]' >"$fx/list.json"
  run "${G[@]}" sync-plan "$BATS_TEST_TMPDIR/misc/plan.md" --per-task all
  [ "$status" -eq 0 ]
  [[ "$output" == *$'would-create\ttask\tpm:a\tShort'* ]]
}

@test "sync-plan refuses --apply when the epic lookup is truncated, and warns on a dry run" {
  make_spec
  jq -n '[range(0;200) | {number:., state:"OPEN", body:"x"}]' >"$fx/epics.json"
  run "${G[@]}" sync-plan "$tasks" --apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing --apply"* ]]
  refute_mutated
  run "${G[@]}" sync-plan "$tasks"
  [ "$status" -eq 0 ]
  [[ "$output" == *"truncated"* ]]
}

@test "sync-plan refuses --apply before any mutation when the issue lookup is truncated" {
  make_spec
  jq -n '[range(0;500) | {number:., title:"x", state:"OPEN"}]' >"$fx/list.json"
  run "${G[@]}" sync-plan "$tasks" --per-task all --apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing --apply"* ]]
  refute_mutated
}

@test "plan epics from different directories get different markers" {
  mkdir -p "$BATS_TEST_TMPDIR/proj-a" "$BATS_TEST_TMPDIR/proj-b"
  printf -- '- [ ] pm:one Do it\n' >"$BATS_TEST_TMPDIR/proj-a/tasks.md"
  cp "$BATS_TEST_TMPDIR/proj-a/tasks.md" "$BATS_TEST_TMPDIR/proj-b/tasks.md"
  run "${G[@]}" sync-plan "$BATS_TEST_TMPDIR/proj-a/tasks.md"
  [ "${lines[1]}" = "$(printf 'would-create\tepic\tpm:plan-proj-a-tasks\t[plan] proj-a/tasks.md')" ]
  run "${G[@]}" sync-plan "$BATS_TEST_TMPDIR/proj-b/tasks.md"
  [ "${lines[1]}" = "$(printf 'would-create\tepic\tpm:plan-proj-b-tasks\t[plan] proj-b/tasks.md')" ]
}

@test "two epics with one marker are reported as drift and left alone" {
  make_spec
  jq -n '[{number:7,state:"OPEN",body:"<!-- pm:spec-002 -->\nold"},{number:8,state:"OPEN",body:"<!-- pm:spec-002 -->\nnew"}]' >"$fx/epics.json"
  run "${G[@]}" sync-plan "$tasks" --apply
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "$(printf 'drift\tepic\tpm:spec-002\tduplicate epics #7 #8; not touching them')" ]
  refute_mutated
}

@test "per-task issues are matched per tasks file, not across specs" {
  make_spec
  mkdir -p "$BATS_TEST_TMPDIR/specs/003-other"
  printf -- '- [X] T001 Other thing\n' >"$BATS_TEST_TMPDIR/specs/003-other/tasks.md"
  cat >"$fx/list.json" <<'EOF'
[{"number":10,"title":"T001: Set up repo","state":"OPEN","body":"Tracked in [spec-002] demo. Source: 002-demo/tasks.md"}]
EOF
  run "${G[@]}" sync-plan "$BATS_TEST_TMPDIR/specs/003-other/tasks.md" --per-task all --apply
  [ "${lines[2]}" = "$(printf 'created\ttask\tT001\t#99')" ]
  refute_logged 'issue close 10'
}

@test "an untied issue that starts with the id is reported as ambiguous and left alone" {
  make_spec
  echo '[{"number":10,"title":"T002: Some other wording","state":"CLOSED","body":""}]' >"$fx/list.json"
  run "${G[@]}" sync-plan "$tasks" --per-task T002 --apply
  [[ "$output" == *$'drift\ttask\tT002\tan issue starts with T002 but is not tied to 002-demo/tasks.md; not touching it'* ]]
  refute_logged 'issue create .*--title T002'
}

@test "per-task exists branches: done and closed, open and open" {
  make_spec
  cat >"$fx/list.json" <<'EOF'
[{"number":10,"title":"T001: Set up repo","state":"CLOSED","body":""},
 {"number":11,"title":"T002: Write docs","state":"OPEN","body":""}]
EOF
  run "${G[@]}" sync-plan "$tasks" --per-task T001,T002
  [ "${lines[2]}" = "$(printf 'exists\ttask\tT001\t#10')" ]
  [ "${lines[3]}" = "$(printf 'exists\ttask\tT002\t#11')" ]
}

@test "--per-task tolerates spaces after the commas" {
  per_task_fixture
  run "${G[@]}" sync-plan "$tasks" --per-task "T001, T003"
  [[ "$output" == *$'\tT001\t'* ]]
  [[ "$output" == *$'\tT003\t'* ]]
  [[ "$output" != *$'\tT002\t'* ]]
}

