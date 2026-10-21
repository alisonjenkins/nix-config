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
