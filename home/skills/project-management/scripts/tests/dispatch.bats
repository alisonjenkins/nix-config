#!/usr/bin/env bats

load helpers

setup() {
  pm_setup
  export PM_BACKENDS_DIR="$BATS_TEST_TMPDIR/b"
  local b
  for b in demo other github; do
    mkdir -p "$PM_BACKENDS_DIR/$b"
  done
  echo d >"$PM_BACKENDS_DIR/demo/alias"
  echo O >"$PM_BACKENDS_DIR/other/alias"
  echo g >"$PM_BACKENDS_DIR/github/alias"
  for b in demo other; do
    printf 'echo "%s status $*"\n' "$b" >"$PM_BACKENDS_DIR/$b/status.sh"
  done
  echo 'echo "show $*"' >"$PM_BACKENDS_DIR/github/show.sh"
  unset PM_BACKEND
}

@test "a missing -b fails and lists the aliases" {
  run bash "$pm" status
  [ "$status" -eq 1 ]
  [[ "$output" == *"error: -b required: d|demo g|github O|other"* ]]
}

@test "-b accepts an alias in every spelling" {
  local form
  for form in "-b d" "-bd" "--backend d" "--backend=d" "-b demo" "--backend=demo"; do
    run bash "$pm" $form status a b
    [ "$status" -eq 0 ]
    [ "$output" = "demo status a b" ]
  done
}

@test "aliases are case sensitive" {
  run bash "$pm" -b O status
  [ "$status" -eq 0 ]
  [ "$output" = "other status " ]
  run bash "$pm" -b o status
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown backend 'o'; use d|demo g|github O|other"* ]]
}

@test "a backend without the verb fails by name" {
  run bash "$pm" -b d list
  [ "$status" -eq 1 ]
  [[ "$output" == *"backend demo has no verb list"* ]]
}

@test "PM_BACKEND is used when -b is absent and loses to -b" {
  PM_BACKEND=d run bash "$pm" status
  [ "$status" -eq 0 ]
  [ "$output" = "demo status " ]
  PM_BACKEND=O run bash "$pm" -b d status
  [ "$status" -eq 0 ]
  [ "$output" = "demo status " ]
}

@test "backend flags pass through untouched" {
  run bash "$pm" -b d -r x/y status 7
  [ "$output" = "demo status -r x/y 7" ]
}

@test "a GitHub issue URL routes to github without -b" {
  run bash "$pm" show https://github.com/owner/name/issues/12
  [ "$status" -eq 0 ]
  [ "$output" = "show -r owner/name 12" ]
}

@test "a verb is required" {
  run bash "$pm" -b d
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage: pm"* ]]
}

@test "-h prints usage and exits 0" {
  run bash "$pm" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"verbs: status list show update sync-plan"* ]]
}

@test "URL routing keeps arguments with spaces intact" {
  printf 'for a in "$@"; do printf "[%%s]" "$a"; done; echo\n' >"$PM_BACKENDS_DIR/github/show.sh"
  run bash "$pm" show https://github.com/owner/name/issues/12 "a b"
  [ "$status" -eq 0 ]
  [ "$output" = "[-r][owner/name][12][a b]" ]
}

@test "a backend without an alias file still resolves by its full name" {
  mkdir -p "$PM_BACKENDS_DIR/noalias"
  echo 'echo "noalias status"' >"$PM_BACKENDS_DIR/noalias/status.sh"
  run bash "$pm" -b noalias status
  [ "$status" -eq 0 ]
  [ "$output" = "noalias status" ]
  run bash "$pm" -b foo status
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown backend 'foo'"* ]]
}

@test "arguments after the verb reach the backend untouched" {
  run bash "$pm" -b d status --comment "-blocked on X" -h -b x
  [ "$status" -eq 0 ]
  [ "$output" = "demo status --comment -blocked on X -h -b x" ]
}

@test "a URL with a trailing slash routes to github" {
  run bash "$pm" show https://github.com/owner/name/issues/12/
  [ "$status" -eq 0 ]
  [ "$output" = "show -r owner/name 12" ]
}

@test "a URL that is not a GitHub issue is passed through unchanged" {
  run bash "$pm" -b g show https://example.com/owner/name/issues/12
  [ "$status" -eq 0 ]
  [ "$output" = "show https://example.com/owner/name/issues/12" ]
}

@test "an explicit -b wins over a URL and the URL is not rewritten" {
  run bash "$pm" -b d status https://github.com/owner/name/issues/1
  [ "$status" -eq 0 ]
  [ "$output" = "demo status https://github.com/owner/name/issues/1" ]
}
