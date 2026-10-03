#!/usr/bin/env bats

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  script="$script_dir/../check-no-fixups.sh"

  repo="$BATS_TEST_TMPDIR/repo"
  git init -q "$repo"
  cd "$repo"
  git config user.email "test@example.com"
  git config user.name "Test User"
  git config commit.gpgsign false
  git commit -q --allow-empty -m base
  git branch -M main
  git switch -q -c feature
}

commit_file() {
  echo "$1" >"$1.txt"
  git add "$1.txt"
  git commit -q -m "${2:-$1}"
}

@test "passes when the range has only ordinary commits" {
  commit_file one
  run "$script" main..HEAD
  [ "$status" -eq 0 ]
}

@test "passes on an empty range" {
  run "$script" HEAD..HEAD
  [ "$status" -eq 0 ]
}

@test "fails on a fixup! commit and names it" {
  commit_file one
  git commit -q --allow-empty --fixup=HEAD
  run "$script" main..HEAD
  [ "$status" -eq 1 ]
  [[ "$output" == *"fixup! one"* ]]
  [[ "$output" == *"--autosquash"* ]]
}

@test "fails on squash! and amend! commits" {
  commit_file one
  git commit -q --allow-empty -m "squash! one"
  run "$script" main..HEAD
  [ "$status" -eq 1 ]
  git reset -q --hard HEAD~1
  git commit -q --allow-empty -m "amend! one"
  run "$script" main..HEAD
  [ "$status" -eq 1 ]
}

@test "a subject merely containing the word fixup is fine" {
  commit_file one "fix: fixup! handling in the parser"
  run "$script" main..HEAD
  [ "$status" -eq 0 ]
}

@test "ignores a fixup! commit outside the range" {
  commit_file one
  git commit -q --allow-empty --fixup=HEAD
  run "$script" HEAD..HEAD
  [ "$status" -eq 0 ]
}

@test "rejects an invalid rev-range" {
  run "$script" nonexistent..HEAD
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a valid rev-range"* ]]
}
