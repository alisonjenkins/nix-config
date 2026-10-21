#!/usr/bin/env bats

# The same checks run against every backend. A backend that drifts from the
# verb contract fails here.

load helpers

setup() {
  pm_setup
  install_fake_gh
  fx="$FAKE_GH_FIXTURES"
  dir="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$dir"
  cat >"$dir/tasks.md" <<'EOF'
- [X] T001 Set up repo owner:ali est:30 prio:1
- [ ] T002 Write docs deps:T001 due:2026-11-01T00:00:00Z
EOF
  cat >"$fx/list.json" <<'EOF'
[{"number":1,"title":"Set up repo","state":"OPEN","assignees":[],"labels":[],"milestone":null,"updatedAt":"2099-01-01T00:00:00Z","body":""},
 {"number":2,"title":"Write docs","state":"CLOSED","assignees":[],"labels":[],"milestone":null,"updatedAt":"2099-01-01T00:00:00Z","body":""}]
EOF
  jq -n '{number:1,title:"Set up repo",state:"OPEN",assignees:[],labels:[],milestone:null,updatedAt:"2099-01-01T00:00:00Z",url:"https://github.com/owner/name/issues/1",body:""}' >"$fx/view.json"
}

# be_args <local|github>: the -b and backend flags for that backend.
be_args() {
  case "$1" in
    local) echo "-b l -d $dir" ;;
    github) echo "-b g -r owner/name" ;;
  esac
}

# sample_id <backend>: an id that exists in that backend's fixture.
sample_id() {
  case "$1" in
    local) echo T002 ;;
    github) echo 1 ;;
  esac
}

check_header() {
  # shellcheck disable=SC2046
  run bash "$pm" $(be_args "$1") list --state all
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "# backend=$2 "* ]]
}

check_list_columns() {
  # shellcheck disable=SC2046
  run bash "$pm" $(be_args "$1") list --state all
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -ge 2 ]
  printf '%s\n' "$output" | awk -F'\t' '!/^#/ && NF != 8 { bad = 1 } END { exit bad }'
}

check_status() {
  # shellcheck disable=SC2046
  run bash "$pm" $(be_args "$1") status
  [ "$status" -eq 0 ]
  [[ "${lines[1]}" =~ ^open=[0-9]+\ done=[0-9]+\ blocked=[0-9]+\ stale= ]]
}

check_show() {
  # shellcheck disable=SC2046
  run bash "$pm" $(be_args "$1") show "$(sample_id "$1")"
  [ "$status" -eq 0 ]
  local keys
  keys="$(printf '%s\n' "$output" | awk -F'\t' 'NR > 1 && NR <= 9 { printf "%s ", $1 }')"
  [ "$keys" = "id state title owner deps due est prio " ]
}

check_bad_update_flag() {
  # shellcheck disable=SC2046
  run bash "$pm" $(be_args "$1") update "$(sample_id "$1")" --bogus
  [ "$status" -ne 0 ]
}

check_paging() {
  # shellcheck disable=SC2046
  run bash "$pm" $(be_args "$1") list --state all --limit 1
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [ "${lines[2]}" = "# more=1 next-offset=1" ]
  # shellcheck disable=SC2046
  run bash "$pm" $(be_args "$1") list --state all --limit 1 --offset 1
  [ "${#lines[@]}" -eq 2 ]
  # shellcheck disable=SC2046
  run bash "$pm" $(be_args "$1") list --state all --offset 08
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
}

@test "local: header names the backend" { check_header local local; }
@test "local: list pages with --limit and --offset" { check_paging local; }
@test "github: list pages with --limit and --offset" { check_paging github; }
@test "github: header names the backend" { check_header github github; }
@test "local: list rows have 8 columns" { check_list_columns local; }
@test "github: list rows have 8 columns" { check_list_columns github; }
@test "local: status line shape" { check_status local; }
@test "github: status line shape" { check_status github; }
@test "local: show key order" { check_show local; }
@test "github: show key order" { check_show github; }
@test "local: an unknown update flag fails" { check_bad_update_flag local; }
@test "github: an unknown update flag fails" { check_bad_update_flag github; }

@test "the real backends have collision-free aliases" {
  run bash "$scripts_dir/lint-aliases.sh"
  [ "$status" -eq 0 ]
}

@test "every backend implements every verb" {
  local b v
  for b in "$scripts_dir"/backends/*/; do
    for v in status list show update sync-plan; do
      [ -f "$b$v.sh" ] || { echo "missing: $b$v.sh"; return 1; }
    done
  done
}
