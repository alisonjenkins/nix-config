#!/usr/bin/env bats

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  script="$script_dir/../eval-triggers.sh"
  skills="$BATS_TEST_TMPDIR/skills"
  mkdir -p "$skills"

  fake_delegate="$BATS_TEST_TMPDIR/fake-delegate.sh"
  cat >"$fake_delegate" <<'EOF'
#!/usr/bin/env bash
printf '%s' "$1" > "$BATS_TEST_TMPDIR/recorded_prompt.txt"
printf '%s' "${2:-}" > "$BATS_TEST_TMPDIR/recorded_profile.txt"
if [[ -f "$BATS_TEST_TMPDIR/delegate_err.txt" ]]; then
  cat "$BATS_TEST_TMPDIR/delegate_err.txt" >&2
fi
if [[ -f "$BATS_TEST_TMPDIR/delegate_exit.txt" ]]; then
  exit "$(<"$BATS_TEST_TMPDIR/delegate_exit.txt")"
fi
if [[ -f "$BATS_TEST_TMPDIR/canned_reply.txt" ]]; then
  cat "$BATS_TEST_TMPDIR/canned_reply.txt"
else
  echo "[]"
fi
EOF
  chmod +x "$fake_delegate"
  export EVAL_TRIGGERS_DELEGATE="$fake_delegate"
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

set_reply() {
  printf '%s' "$1" >"$BATS_TEST_TMPDIR/canned_reply.txt"
}

set_delegate_error() {
  local code="$1" msg="${2:-delegate failed}"
  printf '%s' "$code" >"$BATS_TEST_TMPDIR/delegate_exit.txt"
  printf '%s\n' "$msg" >"$BATS_TEST_TMPDIR/delegate_err.txt"
}

@test "all correct routes score 100% and exit 0" {
  make_skill git "Use when committing." "commit this"
  make_skill review "Use when reviewing." "review this"
  set_reply '[{"i": 1, "skill": "git"}, {"i": 2, "skill": "review"}]'
  run bash "$script" "$skills"
  [ "$status" -eq 0 ]
  [[ "$output" == *"top-1: 2/2 (100.0%)"* ]]
  [[ "$output" != *"MISS"* ]]
}

@test "one wrong routing prints MISS line, skill score, and correct percentage" {
  make_skill git "Use when committing." "commit this"
  make_skill review "Use when reviewing." "review this"
  set_reply '[{"i": 1, "skill": "review"}, {"i": 2, "skill": "review"}]'
  run bash "$script" "$skills"
  [ "$status" -eq 0 ]
  [[ "$output" == *'MISS git: "commit this" -> review'* ]]
  [[ "$output" == *"git: 0/1"* ]]
  [[ "$output" == *"top-1: 1/2 (50.0%)"* ]]
}

@test "reply wrapped in a markdown fence with prose parses" {
  make_skill git "Use when committing." "commit this"
  set_reply $'Here is the routed list:\n```json\n[{"i": 1, "skill": "git"}]\n```\nAll done.'
  run bash "$script" "$skills"
  [ "$status" -eq 0 ]
  [[ "$output" == *"top-1: 1/1 (100.0%)"* ]]
}

@test "unparseable reply prints error and first 20 lines, exits 3" {
  make_skill git "Use when committing." "commit this"
  set_reply "I am unable to answer this request."
  run bash "$script" "$skills"
  [ "$status" -eq 3 ]
  [[ "$output" == *"error: could not parse the router reply"* ]]
  [[ "$output" == *"I am unable to answer this request."* ]]
}

@test "phrase number missing from the reply exits 3" {
  make_skill git "Use when committing." "commit this"
  make_skill review "Use when reviewing." "review this"
  set_reply '[{"i": 1, "skill": "git"}]'
  run bash "$script" "$skills"
  [ "$status" -eq 3 ]
  [[ "$output" == *"error: could not parse the router reply"* ]]
}

@test "delegate exiting non-zero prints stderr and exits 2" {
  make_skill git "Use when committing." "commit this"
  set_delegate_error 1 "rate limit exceeded"
  run bash "$script" "$skills"
  [ "$status" -eq 2 ]
  [[ "$output" == *"rate limit exceeded"* ]]
}

@test "--min above the score exits 1 while printing everything" {
  make_skill git "Use when committing." "commit this"
  make_skill review "Use when reviewing." "review this"
  set_reply '[{"i": 1, "skill": "review"}, {"i": 2, "skill": "review"}]'
  run bash "$script" --min 80 "$skills"
  [ "$status" -eq 1 ]
  [[ "$output" == *'MISS git: "commit this" -> review'* ]]
  [[ "$output" == *"top-1: 1/2 (50.0%)"* ]]
}

@test "--min below the score exits 0" {
  make_skill git "Use when committing." "commit this"
  make_skill review "Use when reviewing." "review this"
  set_reply '[{"i": 1, "skill": "review"}, {"i": 2, "skill": "review"}]'
  run bash "$script" --min 40 "$skills"
  [ "$status" -eq 0 ]
  [[ "$output" == *"top-1: 1/2 (50.0%)"* ]]
}

@test "prompt contains every skill name and phrase and passes read profile" {
  make_skill alpha "Description for alpha." "phrase alpha one" "phrase alpha two"
  make_skill beta "Description for beta." "phrase beta one"
  set_reply '[{"i": 1, "skill": "alpha"}, {"i": 2, "skill": "alpha"}, {"i": 3, "skill": "beta"}]'
  run bash "$script" "$skills"
  [ "$status" -eq 0 ]
  prompt="$(<"$BATS_TEST_TMPDIR/recorded_prompt.txt")"
  profile="$(<"$BATS_TEST_TMPDIR/recorded_profile.txt")"
  [ "$profile" = "read" ]
  [[ "$prompt" == *"alpha"* ]]
  [[ "$prompt" == *"beta"* ]]
  [[ "$prompt" == *"phrase alpha one"* ]]
  [[ "$prompt" == *"phrase alpha two"* ]]
  [[ "$prompt" == *"phrase beta one"* ]]
}

@test "skills without triggers.json are listed as candidates but add no phrases" {
  make_skill candidate_only "Candidate only description."
  make_skill active_skill "Active skill description." "trigger active"
  set_reply '[{"i": 1, "skill": "active_skill"}]'
  run bash "$script" "$skills"
  [ "$status" -eq 0 ]
  prompt="$(<"$BATS_TEST_TMPDIR/recorded_prompt.txt")"
  [[ "$prompt" == *"candidate_only: Candidate only description."* ]]
  [[ "$prompt" == *"active_skill: Active skill description."* ]]
  [[ "$prompt" == *"1. trigger active"* ]]
  [[ "$prompt" != *"2."* ]]
  [[ "$output" == *"top-1: 1/1 (100.0%)"* ]]
}

@test "unknown flag prints usage and exits 1" {
  run bash "$script" --invalid-flag "$skills"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}
