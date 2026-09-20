#!/usr/bin/env bats

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  list="$script_dir/../list-local-profiles.sh"
  export PATH="$script_dir:$PATH"
  export FAKE_CURL_CALLS="$BATS_TEST_TMPDIR/calls.log"
  : >"$FAKE_CURL_CALLS"
  export LOCAL_LLM_PROFILES_FILE="$BATS_TEST_TMPDIR/profiles.toml"
  export LOCAL_LLM_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$LOCAL_LLM_STATE_DIR"
  unset FAKE_CURL_UP FAKE_CURL_MODE
  cat >"$LOCAL_LLM_PROFILES_FILE" <<'TOML'
[fast]
runtime = "llama-server"
model = "/models/fast.gguf"
description = "quick profile"

[quality]
runtime = "mlx-lm"
model = "/models/quality"
description = "bigger profile"
TOML
}

@test "missing profiles file exits 1" {
  rm -f "$LOCAL_LLM_PROFILES_FILE"
  run "$list"
  [ "$status" -eq 1 ]
  [[ "$output" == *"profiles file not found"* ]]
}

@test "malformed profiles file exits 1" {
  printf 'not = valid = toml =\n' >"$LOCAL_LLM_PROFILES_FILE"
  run "$list"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not valid TOML"* ]]
}

@test "lists all profiles with no active marker when nothing is active" {
  run "$list"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fast"*"/models/fast.gguf"*"quick profile"* ]]
  [[ "$output" == *"quality"*"/models/quality"*"bigger profile"* ]]
  [[ "$output" != *"active"* ]]
}

@test "marks the active profile and confirms it's responding" {
  jq -nc --arg profile "fast" --arg url "http://localhost:8080" --arg model "m" --argjson pid 1 \
    '{profile: $profile, url: $url, model: $model, pid: $pid}' >"$LOCAL_LLM_STATE_DIR/active-profile.json"
  export FAKE_CURL_UP="http://localhost:8080"
  run "$list"
  [ "$status" -eq 0 ]
  [[ "$output" == *"* fast"*"(active, responding)"* ]]
  [[ "$output" != *"quality"*"active"* ]]
}

@test "marks the active profile as not responding when it's actually down" {
  jq -nc --arg profile "fast" --arg url "http://localhost:8080" --arg model "m" --argjson pid 1 \
    '{profile: $profile, url: $url, model: $model, pid: $pid}' >"$LOCAL_LLM_STATE_DIR/active-profile.json"
  export FAKE_CURL_UP=""
  run "$list"
  [ "$status" -eq 0 ]
  [[ "$output" == *"* fast"*"(active, but not responding"* ]]
}

@test "never makes a live check for a profile that isn't active" {
  run "$list"
  [ "$status" -eq 0 ]
  [ ! -s "$FAKE_CURL_CALLS" ]
}
