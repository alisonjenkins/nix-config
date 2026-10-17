#!/usr/bin/env bats

load 'sandbox-path-helpers'

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  delegate="$script_dir/../delegate-to-gemini.sh"
  stage_fakes_and_export_path "$script_dir"
  export FAKE_AGY_CALLS="$BATS_TEST_TMPDIR/calls.log"
  : >"$FAKE_AGY_CALLS"
  unset DELEGATE_REASONING_EFFORT DELEGATE_MODEL FAKE_AGY_MODE
  export DELEGATE_RETRY_BASE_DELAY=0
}

@test "no args prints usage and exits 1" {
  run bash "$delegate"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
  [[ "$output" == *"valid profiles: read, write-workdir, write-shell"* ]]
}

@test "missing agy CLI prints a clear error and exits 1" {
  bash_bin="$(command -v bash)"
  empty_dir="$BATS_TEST_TMPDIR/empty-path"
  mkdir -p "$empty_dir"
  PATH="$empty_dir" run "$bash_bin" "$delegate" "task" read
  [ "$status" -eq 1 ]
  [[ "$output" == *"'agy' (Antigravity CLI) not found on PATH"* ]]
}

@test "invalid profile exits 1 and lists valid profiles" {
  run bash "$delegate" "task" nonsense
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid profile 'nonsense'"* ]]
}

@test "read profile passes no permission flags" {
  run bash "$delegate" "do it" read
  [ "$status" -eq 0 ]
  [[ "$output" == "response for model=gemini-3.8-flash-medium: do it" ]]
  call="$(<"$FAKE_AGY_CALLS")"
  [[ "$call" == *$'mode=\tskip_perms=no'* ]]
}

@test "write-workdir uses accept-edits mode" {
  run bash "$delegate" "do it" write-workdir
  [ "$status" -eq 0 ]
  [[ "$(<"$FAKE_AGY_CALLS")" == *$'mode=accept-edits\tskip_perms=no'* ]]
}

@test "write-shell skips permissions" {
  run bash "$delegate" "do it" write-shell
  [ "$status" -eq 0 ]
  [[ "$(<"$FAKE_AGY_CALLS")" == *$'mode=\tskip_perms=yes'* ]]
}

@test "reasoning effort is passed through and a bad value is ignored" {
  DELEGATE_REASONING_EFFORT=high run bash "$delegate" "do it" read
  [ "$status" -eq 0 ]
  [[ "$(<"$FAKE_AGY_CALLS")" == *$'effort=high'* ]]

  : >"$FAKE_AGY_CALLS"
  DELEGATE_REASONING_EFFORT=bogus run bash "$delegate" "do it" read
  [ "$status" -eq 0 ]
  [[ "$output" == *"ignoring"* ]]
  [[ "$(<"$FAKE_AGY_CALLS")" == *$'effort=\t'* ]]
}

@test "a rejected model falls back to the next one" {
  FAKE_AGY_MODE=flash-medium-rejected run bash "$delegate" "do it" read
  [ "$status" -eq 0 ]
  [[ "$output" == "response for model=gemini-3.8-flash-low: do it" ]]
  [ "$(wc -l <"$FAKE_AGY_CALLS")" -eq 2 ]
}

@test "a denied command exits 3 and names write-shell" {
  FAKE_AGY_MODE=soft-denied-command run bash "$delegate" "do it" write-workdir
  [ "$status" -eq 3 ]
  [[ "$output" == *"needs write-shell"* ]]
  [[ "$output" == *"under profile 'write-workdir'"* ]]
}

@test "a denied write exits 3 and names write-workdir" {
  FAKE_AGY_MODE=soft-denied-write run bash "$delegate" "do it" read
  [ "$status" -eq 3 ]
  [[ "$output" == *"needs write-workdir"* ]]
}

@test "an effort error does not count as a rejected model" {
  FAKE_AGY_MODE=bad-effort run bash "$delegate" "do it" read
  [ "$status" -eq 1 ]
  [ "$(wc -l <"$FAKE_AGY_CALLS")" -eq 1 ]
}

@test "DELEGATE_MODEL picks the model and is not replaced on rejection" {
  DELEGATE_MODEL=gemini-4-argon-high run bash "$delegate" "do it" read
  [ "$status" -eq 0 ]
  [[ "$output" == "response for model=gemini-4-argon-high: do it" ]]

  : >"$FAKE_AGY_CALLS"
  FAKE_AGY_MODE=flash-medium-rejected DELEGATE_MODEL=gemini-3.8-flash-medium \
    run bash "$delegate" "do it" read
  [ "$status" -eq 1 ]
  [ "$(wc -l <"$FAKE_AGY_CALLS")" -eq 1 ]
}

@test "missing sign-in is reported with the fix" {
  FAKE_AGY_MODE=unauthenticated run bash "$delegate" "do it" read
  [ "$status" -eq 1 ]
  [[ "$output" == *"not signed in"* ]]
  [ "$(wc -l <"$FAKE_AGY_CALLS")" -eq 1 ]
}

@test "persistent outage retries then reports a possible outage" {
  FAKE_AGY_MODE=outage-persistent run bash "$delegate" "do it" read
  [ "$status" -eq 1 ]
  [[ "$output" == *"possible outage"* ]]
  [ "$(wc -l <"$FAKE_AGY_CALLS")" -eq 3 ]
}

@test "exhausted quota is reported and not retried" {
  FAKE_AGY_MODE=quota-exhausted run bash "$delegate" "do it" read
  [ "$status" -eq 1 ]
  [[ "$output" == *"exhausted quota"* ]]
  [ "$(wc -l <"$FAKE_AGY_CALLS")" -eq 1 ]
}

@test "an unrelated failure is surfaced without trying another model" {
  FAKE_AGY_MODE=unrelated-failure run bash "$delegate" "do it" read
  [ "$status" -eq 1 ]
  [[ "$output" == *"something else went wrong"* ]]
  [ "$(wc -l <"$FAKE_AGY_CALLS")" -eq 1 ]
}

@test "a named skill is staged and granted via --add-dir" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/skills/demo"
  echo "# demo" >"$HOME/.claude/skills/demo/SKILL.md"
  run bash "$delegate" "do it" read demo
  [ "$status" -eq 0 ]
  call="$(<"$FAKE_AGY_CALLS")"
  [[ "$call" == *"Before doing anything else, read the following:"* ]]
  [[ "$call" == *"delegate-to-gemini-skills."* ]]
}

@test "an unknown skill exits 1 naming it" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/skills"
  run bash "$delegate" "do it" read nosuchskill
  [ "$status" -eq 1 ]
  [[ "$output" == *"skill(s) 'nosuchskill' not found"* ]]
}
