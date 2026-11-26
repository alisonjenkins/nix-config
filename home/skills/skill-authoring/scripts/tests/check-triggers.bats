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

@test "passes when a phrase shares a word with the listed summary" {
  make_skill git "Use when committing or opening a pull request." "commit this"
  run bash "$script" "$skills"
  [ "$status" -eq 0 ]
  [[ "$output" == *"all 1 trigger phrases"* ]]
}

@test "fails a phrase with no word in the listed summary" {
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

# make_raw NAME FRONTMATTER_BODY PHRASE...: writes the frontmatter as given.
make_raw() {
  local name="$1" header="$2"
  shift 2
  mkdir -p "$skills/$name"
  printf -- '---\n%s\n---\n\nbody\n' "$header" >"$skills/$name/SKILL.md"
  printf '%s\n' "$@" | jq -R . | jq -s '{fire: .}' >"$skills/$name/triggers.json"
}

padding="$(printf 'filler words %.0s' $(seq 1 20))"

@test "checks against the summary, not the full description" {
  make_raw infra "name: infra
description: Use for kubernetes deploys.
summary: Use for pods." "scale kubernetes"
  run bash "$script" "$skills"
  [ "$status" -eq 1 ]
  [[ "$output" == *'FAIL infra: no word of "scale kubernetes"'* ]]
}

@test "reads a summary nested under metadata" {
  make_raw infra "name: infra
description: Use for kubernetes deploys.
metadata:
  summary: Use for pods." "restart pods"
  run bash "$script" "$skills"
  [ "$status" -eq 0 ]
}

@test "lists a short description whole, past its first sentence" {
  make_raw infra "name: infra
description: Use for pods. Also nodes." "drain nodes"
  run bash "$script" "$skills"
  [ "$status" -eq 0 ]
}

@test "lists only the first sentence of a long description" {
  make_raw infra "name: infra
description: Use for pods. Also nodes and $padding" "drain nodes"
  run bash "$script" "$skills"
  [ "$status" -eq 1 ]
}

@test "a dotted version number does not end the first sentence" {
  make_raw infra "name: infra
description: Use for v1.2 pods and nodes. $padding" "drain nodes"
  run bash "$script" "$skills"
  [ "$status" -eq 0 ]
}

@test "a summary past the listing cap loses its tail" {
  make_raw infra "name: infra
description: Use for pods.
summary: Use for pods and $padding nodes" "drain nodes"
  run bash "$script" "$skills"
  [ "$status" -eq 1 ]
  LISTING_CHARS=400 run bash "$script" "$skills"
  [ "$status" -eq 0 ]
}
