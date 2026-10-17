#!/usr/bin/env bats

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  script="$script_dir/../check-triggers.sh"
  skills="$BATS_TEST_TMPDIR/skills"
  mkdir -p "$skills"
}

# make_skill NAME DESCRIPTION [PHRASE...]
make_skill() {
  local name="$1" description="$2"
  shift 2
  mkdir -p "$skills/$name"
  printf -- '---\nname: %s\ndescription: >-\n  %s\n---\n\nbody\n' "$name" "$description" >"$skills/$name/SKILL.md"
  if (($# > 0)); then
    printf '%s\n' "$@" | jq -R . | jq -s '{fire: .}' >"$skills/$name/triggers.json"
  fi
}

@test "passes when a phrase shares a word with the description" {
  make_skill git "Use when committing or opening a pull request." "commit this"
  run bash "$script" "$skills"
  [ "$status" -eq 0 ]
  [[ "$output" == *"all 1 trigger phrases"* ]]
}

@test "fails a phrase with no word in the description" {
  make_skill debugging "Use when something is broken." "why is this crashing"
  run bash "$script" "$skills"
  [ "$status" -eq 1 ]
  [[ "$output" == *'FAIL debugging: no word of "why is this crashing"'* ]]
}

@test "matches across suffixes: fails, failing and failed meet" {
  make_skill debugging "Use when a build is failing." "it still fails"
  run bash "$script" "$skills"
  [ "$status" -eq 0 ]
}

@test "undoubles a consonant: committing meets commit" {
  make_skill git "Use when committing." "commit this"
  run bash "$script" "$skills"
  [ "$status" -eq 0 ]
}

@test "keeps a natural double l or s: pressing meets press" {
  make_skill keys "Use when pressing keys." "press the button"
  run bash "$script" "$skills"
  [ "$status" -eq 0 ]
}

@test "matches write against writing" {
  make_skill writing "Use when writing prose." "write a summary"
  run bash "$script" "$skills"
  [ "$status" -eq 0 ]
}

@test "counts three-letter tool names such as aws and nix" {
  make_skill infra "Use for aws and nix deploys." "check the aws instance"
  run bash "$script" "$skills"
  [ "$status" -eq 0 ]
}

@test "does not count stop words as shared vocabulary" {
  make_skill other "Use when you want this, with that, and then." "what about this and that"
  run bash "$script" "$skills"
  [ "$status" -eq 1 ]
}

@test "matching is case-insensitive" {
  make_skill infra "Use for Kubernetes." "scale KUBERNETES"
  run bash "$script" "$skills"
  [ "$status" -eq 0 ]
}

@test "skips a skill with no triggers.json" {
  make_skill quiet "Use for nothing in particular."
  run bash "$script" "$skills"
  [ "$status" -eq 0 ]
  [[ "$output" == *"all 0 trigger phrases"* ]]
}

@test "reports every orphan phrase, not just the first" {
  make_skill a "Use for apples." "bananas please" "cherries please"
  make_skill b "Use for pears." "plums please"
  run bash "$script" "$skills"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bananas"* ]]
  [[ "$output" == *"cherries"* ]]
  [[ "$output" == *"plums"* ]]
  [[ "$output" == *"3 trigger phrase(s)"* ]]
}

@test "passes the real shared skills" {
  run bash "$script"
  [ "$status" -eq 0 ]
}
