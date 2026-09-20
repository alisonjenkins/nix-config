#!/usr/bin/env bats

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  stop="$script_dir/../stop-local-profile.sh"
  export LOCAL_LLM_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$LOCAL_LLM_STATE_DIR"
}

active_file() {
  echo "$LOCAL_LLM_STATE_DIR/active-profile.json"
}

@test "no-op, not an error, when nothing is active" {
  run "$stop"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to stop"* ]]
}

@test "stops the active profile's process and clears the state file" {
  sleep 3600 </dev/null >/dev/null 2>&1 &
  pid=$!
  jq -nc --arg profile "fast" --arg url "http://localhost:8080" --arg model "m" --argjson pid "$pid" \
    '{profile: $profile, url: $url, model: $model, pid: $pid}' >"$(active_file)"

  run "$stop"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stopped profile 'fast'"* ]]
  [ ! -f "$(active_file)" ]

  run kill -0 "$pid"
  [ "$status" -ne 0 ]
  kill -9 "$pid" 2>/dev/null || true
}

@test "clears the state file even if the recorded process was already gone" {
  jq -nc --arg profile "fast" --arg url "http://localhost:8080" --arg model "m" --argjson pid 999999 \
    '{profile: $profile, url: $url, model: $model, pid: 999999}' >"$(active_file)"

  run "$stop"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already gone"* ]]
  [ ! -f "$(active_file)" ]
}
