#!/usr/bin/env bats

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  delegate="$script_dir/../delegate-to-local.sh"
  export PATH="$script_dir:$PATH"
  export FAKE_CURL_CALLS="$BATS_TEST_TMPDIR/calls.log"
  : >"$FAKE_CURL_CALLS"
  export LOCAL_LLM_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$LOCAL_LLM_STATE_DIR"
  unset LOCAL_LLM_URL LOCAL_LLM_MODEL LOCAL_LLM_EXPECT_PROFILE FAKE_CURL_UP FAKE_CURL_MODE
}

write_active() {
  jq -nc --arg profile "$1" --arg url "$2" --arg model "$3" --argjson pid "$$" \
    '{profile: $profile, url: $url, model: $model, pid: $pid}' >"$LOCAL_LLM_STATE_DIR/active-profile.json"
}

@test "no args prints usage and exits 1" {
  run "$delegate"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
  [[ "$output" == *"exit codes:"* ]]
}

@test "too many args prints usage and exits 1" {
  run "$delegate" "task" "extra"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "missing curl on PATH errors clearly and exits 1" {
  bash_bin="$(command -v bash)"
  empty_dir="$BATS_TEST_TMPDIR/empty-path"
  mkdir -p "$empty_dir"
  PATH="$empty_dir" run "$bash_bin" "$delegate" "hello task"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'curl' not found on PATH"* ]]
}

@test "no active profile recorded exits 2" {
  rm -f "$LOCAL_LLM_STATE_DIR/active-profile.json"
  run "$delegate" "hello task"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no local profile is active"* ]]
  [[ "$output" == *"switch-local-profile.sh"* ]]
}

@test "an active profile that isn't actually responding exits 2" {
  write_active "fast" "http://localhost:8080" "fake-model-8080"
  export FAKE_CURL_UP=""
  run "$delegate" "hello task"
  [ "$status" -eq 2 ]
  [[ "$output" == *"'fast' is recorded active but its server isn't responding"* ]]
}

@test "successful call against the active profile prints the reply" {
  write_active "fast" "http://localhost:8080" "fake-model-8080"
  export FAKE_CURL_UP="http://localhost:8080"
  run "$delegate" "hello task"
  [ "$status" -eq 0 ]
  [ "$output" = "response for model=fake-model-8080: hello task" ]
  chat_call="$(sed -n '2p' "$FAKE_CURL_CALLS")"
  [[ "$chat_call" == *'"model":"fake-model-8080"'* ]]
}

@test "LOCAL_LLM_MODEL overrides the active profile's recorded model" {
  write_active "fast" "http://localhost:8080" "fake-model-8080"
  export FAKE_CURL_UP="http://localhost:8080"
  export LOCAL_LLM_MODEL="custom-model"
  run "$delegate" "hello task"
  [ "$status" -eq 0 ]
  chat_call="$(sed -n '2p' "$FAKE_CURL_CALLS")"
  [[ "$chat_call" == *'"model":"custom-model"'* ]]
}

@test "LOCAL_LLM_EXPECT_PROFILE matching the active profile succeeds" {
  write_active "quality" "http://localhost:8080" "fake-model-8080"
  export FAKE_CURL_UP="http://localhost:8080"
  export LOCAL_LLM_EXPECT_PROFILE="quality"
  run "$delegate" "hello task"
  [ "$status" -eq 0 ]
}

@test "LOCAL_LLM_EXPECT_PROFILE mismatching the active profile exits 4" {
  write_active "fast" "http://localhost:8080" "fake-model-8080"
  export FAKE_CURL_UP="http://localhost:8080"
  export LOCAL_LLM_EXPECT_PROFILE="quality"
  run "$delegate" "hello task"
  [ "$status" -eq 4 ]
  [[ "$output" == *"expected profile 'quality'"* ]]
  [[ "$output" == *"'fast' is loaded"* ]]
  # never even attempted the chat call
  [ "$(wc -l <"$FAKE_CURL_CALLS")" -eq 0 ]
}

@test "explicit LOCAL_LLM_URL bypasses profiles entirely, even with no active profile recorded" {
  rm -f "$LOCAL_LLM_STATE_DIR/active-profile.json"
  export LOCAL_LLM_URL="http://localhost:9090"
  export FAKE_CURL_UP="http://localhost:9090"
  run "$delegate" "hello task"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fake-model-9090"* ]]
}

@test "explicit LOCAL_LLM_URL that responds but not with OpenAI-compatible JSON reports that distinctly, not 'not reachable'" {
  export LOCAL_LLM_URL="http://localhost:9090"
  export FAKE_CURL_UP="http://localhost:9090"
  export FAKE_CURL_MODE=malformed-models
  run "$delegate" "hello task"
  [ "$status" -eq 2 ]
  [[ "$output" == *"responded, but its /v1/models response wasn't the expected OpenAI-compatible shape"* ]]
  [[ "$output" != *"is not reachable"* ]]
}

@test "explicit LOCAL_LLM_URL whose chat call times out still reports why, not just 'failed:'" {
  export LOCAL_LLM_URL="http://localhost:9090"
  export FAKE_CURL_UP="http://localhost:9090"
  export FAKE_CURL_MODE=chat-timeout
  run "$delegate" "hello task"
  [ "$status" -eq 3 ]
  [[ "$output" == *"request to http://localhost:9090/v1/chat/completions failed"* ]]
  [[ "$output" == *"Operation timed out"* ]]
}

@test "explicit LOCAL_LLM_URL that is unreachable exits 2" {
  export LOCAL_LLM_URL="http://localhost:9090"
  export FAKE_CURL_UP=""
  run "$delegate" "hello task"
  [ "$status" -eq 2 ]
  [[ "$output" == *"LOCAL_LLM_URL=http://localhost:9090 is not reachable"* ]]
}

@test "endpoint reachable but the chat completion call itself fails exits 3" {
  write_active "fast" "http://localhost:8080" "fake-model-8080"
  export FAKE_CURL_UP="http://localhost:8080"
  export FAKE_CURL_MODE=chat-error
  run "$delegate" "hello task"
  [ "$status" -eq 3 ]
  [[ "$output" == *"request to http://localhost:8080/v1/chat/completions failed"* ]]
  [[ "$output" == *"boom"* ]]
}
