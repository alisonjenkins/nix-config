#!/usr/bin/env bats

load helpers

setup() {
  pm_setup
  lint="$scripts_dir/lint-aliases.sh"
  dir="$BATS_TEST_TMPDIR/b"
  mkdir -p "$dir"
}

mk() { # mk <name> <alias>
  mkdir -p "$dir/$1"
  printf '%s\n' "$2" >"$dir/$1/alias"
}

@test "distinct valid aliases pass" {
  mk github g
  mk local l
  mk gitlab G
  run bash "$lint" "$dir"
  [ "$status" -eq 0 ]
}

@test "the same alias on two backends fails" {
  mk github g
  mk gitlab g
  run bash "$lint" "$dir"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL github: alias 'g' also used by gitlab"* ]]
}

@test "case differences are distinct aliases" {
  mk github g
  mk gitlab G
  run bash "$lint" "$dir"
  [ "$status" -eq 0 ]
}

@test "a non-letter alias fails" {
  mk github g1
  run bash "$lint" "$dir"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not [A-Za-z]+"* ]]
}

@test "an alias equal to another backend's name fails" {
  mk github local
  mk local l
  run bash "$lint" "$dir"
  [ "$status" -eq 1 ]
  [[ "$output" == *"equals backend name local"* ]]
}

@test "an alias longer than its backend name fails" {
  mk jira jiraxx
  run bash "$lint" "$dir"
  [ "$status" -eq 1 ]
  [[ "$output" == *"longer than the name"* ]]
}

@test "a backend without an alias file fails" {
  mkdir -p "$dir/github"
  run bash "$lint" "$dir"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL github: no alias file"* ]]
}
