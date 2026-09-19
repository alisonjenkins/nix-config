#!/usr/bin/env bats

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  script="$script_dir/../pr-description.sh"
  export PATH="$script_dir:$PATH"
  export FAKE_GH_FIXTURES="$BATS_TEST_TMPDIR/fixtures"
  mkdir -p "$FAKE_GH_FIXTURES"

  repo="$BATS_TEST_TMPDIR/repo"
  git init -q "$repo"
  cd "$repo"
  git config user.email "test@example.com"
  git config user.name "Test User"
  git commit -q --allow-empty -m init
}

@test "too few args prints usage and exits 1" {
  run "$script" pull
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "invalid action prints usage and exits 1" {
  run "$script" delete 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "non-numeric pr number errors clearly" {
  run "$script" pull not-a-number
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be numeric"* ]]
}

@test "rejects owner/repo with no slash" {
  run "$script" pull 1 ownerrepo
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be exactly 'owner/repo'"* ]]
}

@test "pull writes title and body to files under .git and prints their paths" {
  echo "Existing PR title" >"$FAKE_GH_FIXTURES/pr-title.txt"
  printf 'Existing body.\n\nMore detail.\n' >"$FAKE_GH_FIXTURES/pr-body.md"

  run "$script" pull 42
  [ "$status" -eq 0 ]
  [[ "$output" == *"title:"* ]]
  [[ "$output" == *"body:"* ]]

  title_file="$(git rev-parse --git-path pr-description/42)/title.txt"
  body_file="$(git rev-parse --git-path pr-description/42)/body.md"
  [ -f "$title_file" ]
  [ -f "$body_file" ]
  run cat "$title_file"
  [[ "$output" == "Existing PR title" ]]
  run cat "$body_file"
  [[ "$output" == *"More detail."* ]]
}

@test "push without a prior pull errors clearly" {
  run "$script" push 42
  [ "$status" -eq 1 ]
  [[ "$output" == *"run"*"pull 42"* ]]
}

@test "push sends the edited title and body via gh pr edit --body-file" {
  echo "Old title" >"$FAKE_GH_FIXTURES/pr-title.txt"
  printf 'Old body.\n' >"$FAKE_GH_FIXTURES/pr-body.md"
  run "$script" pull 7

  title_file="$(git rev-parse --git-path pr-description/7)/title.txt"
  body_file="$(git rev-parse --git-path pr-description/7)/body.md"
  echo "New title after review" >"$title_file"
  printf 'New body reflecting what actually changed.\n' >"$body_file"

  run "$script" push 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"pushed"* ]]

  run cat "$FAKE_GH_FIXTURES/pr-edit-capture.txt"
  [[ "$output" == *"New title after review"* ]]
  [[ "$output" == *"--body-file"* ]]

  run cat "$FAKE_GH_FIXTURES/pr-edit-body-file-capture.txt"
  [[ "$output" == *"New body reflecting what actually changed."* ]]
}

@test "a gh failure during pull stops with an error" {
  touch "$FAKE_GH_FIXTURES/pr-view-fails"
  run "$script" pull 1
  [ "$status" -ne 0 ]
}

@test "a gh failure during push stops with an error" {
  echo "T" >"$FAKE_GH_FIXTURES/pr-title.txt"
  echo "B" >"$FAKE_GH_FIXTURES/pr-body.md"
  run "$script" pull 3
  touch "$FAKE_GH_FIXTURES/pr-edit-fails"
  run "$script" push 3
  [ "$status" -ne 0 ]
}

@test "different PRs get isolated title/body files" {
  echo "T1" >"$FAKE_GH_FIXTURES/pr-title.txt"
  echo "B1" >"$FAKE_GH_FIXTURES/pr-body.md"
  run "$script" pull 1
  echo "T2" >"$FAKE_GH_FIXTURES/pr-title.txt"
  echo "B2" >"$FAKE_GH_FIXTURES/pr-body.md"
  run "$script" pull 2

  run cat "$(git rev-parse --git-path pr-description/1)/title.txt"
  [[ "$output" == "T1" ]]
  run cat "$(git rev-parse --git-path pr-description/2)/title.txt"
  [[ "$output" == "T2" ]]
}
