#!/usr/bin/env bats

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  delegate="$script_dir/../delegate-to-local.sh"
  export PATH="$script_dir:$PATH"
  export FAKE_CURL_CALLS="$BATS_TEST_TMPDIR/calls.log"
  : >"$FAKE_CURL_CALLS"
  unset LOCAL_LLM_URL LOCAL_LLM_MODEL LOCAL_LLM_PROBE_TIMEOUT FAKE_CURL_UP FAKE_CURL_MODE
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

@test "missing jq on PATH errors clearly and exits 1" {
  bash_bin="$(command -v bash)"
  jq_only_dir="$BATS_TEST_TMPDIR/no-jq-path"
  mkdir -p "$jq_only_dir"
  ln -s "$(command -v curl)" "$jq_only_dir/curl"
  PATH="$jq_only_dir" run "$bash_bin" "$delegate" "hello task"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'jq' not found on PATH"* ]]
}

@test "no local endpoint reachable exits 2 and names it a fall-back case" {
  export FAKE_CURL_UP=""
  run "$delegate" "hello task"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no local model endpoint reachable"* ]]
  [[ "$output" == *"http://localhost:8080"* ]]
  [[ "$output" == *"http://localhost:11434"* ]]
  [[ "$output" == *"http://localhost:1234"* ]]
  [[ "$output" == *"fall back to delegate-to-copilot.md or a Claude sub-agent"* ]]
}

@test "explicit LOCAL_LLM_URL that is unreachable also exits 2, without trying the default candidates" {
  export LOCAL_LLM_URL=http://localhost:9999
  export FAKE_CURL_UP="http://localhost:8080"
  run "$delegate" "hello task"
  [ "$status" -eq 2 ]
  [[ "$output" == *"http://localhost:9999"* ]]
  [[ "$output" != *"http://localhost:8080"* ]]
  [ "$(wc -l <"$FAKE_CURL_CALLS")" -eq 1 ]
}

@test "auto-detects the first reachable default candidate, skipping dead ones first" {
  export FAKE_CURL_UP="http://localhost:11434"
  run "$delegate" "hello task"
  [ "$status" -eq 0 ]
  # tried 8080 (dead) then 11434 (up) for the models probe, then one POST to 11434
  [ "$(wc -l <"$FAKE_CURL_CALLS")" -eq 3 ]
  sed -n '1p' "$FAKE_CURL_CALLS" | grep -q "url=http://localhost:8080/v1/models"
  sed -n '2p' "$FAKE_CURL_CALLS" | grep -q "url=http://localhost:11434/v1/models"
  sed -n '3p' "$FAKE_CURL_CALLS" | grep -q "url=http://localhost:11434/v1/chat/completions"
  [[ "$output" == *"response for model=fake-model-11434: hello task"* ]]
}

@test "stops probing as soon as the first candidate answers" {
  export FAKE_CURL_UP="http://localhost:8080,http://localhost:11434"
  run "$delegate" "hello task"
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$FAKE_CURL_CALLS")" -eq 2 ]
  sed -n '1p' "$FAKE_CURL_CALLS" | grep -q "url=http://localhost:8080/v1/models"
  sed -n '2p' "$FAKE_CURL_CALLS" | grep -q "url=http://localhost:8080/v1/chat/completions"
}

@test "uses the auto-discovered model id when LOCAL_LLM_MODEL is unset" {
  export FAKE_CURL_UP="http://localhost:8080"
  run "$delegate" "hello task"
  [ "$status" -eq 0 ]
  chat_call="$(sed -n '2p' "$FAKE_CURL_CALLS")"
  [[ "$chat_call" == *'"model":"fake-model-8080"'* ]]
}

@test "LOCAL_LLM_MODEL overrides the auto-discovered model" {
  export FAKE_CURL_UP="http://localhost:8080"
  export LOCAL_LLM_MODEL="my-preferred-model"
  run "$delegate" "hello task"
  [ "$status" -eq 0 ]
  chat_call="$(sed -n '2p' "$FAKE_CURL_CALLS")"
  [[ "$chat_call" == *'"model":"my-preferred-model"'* ]]
  [[ "$output" == *"response for model=my-preferred-model: hello task"* ]]
}

@test "a candidate with a malformed models list is treated as unusable and skipped" {
  export FAKE_CURL_UP="http://localhost:8080,http://localhost:11434"
  export FAKE_CURL_MODE=malformed-models
  run "$delegate" "hello task"
  # both candidates are "up" but every /v1/models response is malformed,
  # so neither ever qualifies as usable
  [ "$status" -eq 2 ]
  [[ "$output" == *"no local model endpoint reachable"* ]]
}

@test "endpoint reachable but the chat completion call itself fails exits 3" {
  export FAKE_CURL_UP="http://localhost:8080"
  export FAKE_CURL_MODE=chat-error
  run "$delegate" "hello task"
  [ "$status" -eq 3 ]
  [[ "$output" == *"request to http://localhost:8080/v1/chat/completions failed"* ]]
  [[ "$output" == *"boom"* ]]
}

@test "a non-numeric LOCAL_LLM_PROBE_TIMEOUT warns and falls back to the 0.5s default" {
  export FAKE_CURL_UP="http://localhost:8080"
  export LOCAL_LLM_PROBE_TIMEOUT="not-a-number"
  run "$delegate" "hello task"
  [ "$status" -eq 0 ]
  [[ "$output" == *"warning: \$LOCAL_LLM_PROBE_TIMEOUT='not-a-number'"* ]]
  grep -q "max_time=0.5" "$FAKE_CURL_CALLS"
}

@test "a custom numeric LOCAL_LLM_PROBE_TIMEOUT is honored" {
  export FAKE_CURL_UP="http://localhost:8080"
  export LOCAL_LLM_PROBE_TIMEOUT="2"
  run "$delegate" "hello task"
  [ "$status" -eq 0 ]
  grep -q "max_time=2" "$FAKE_CURL_CALLS"
}

@test "successful call prints the model's reply" {
  export FAKE_CURL_UP="http://localhost:8080"
  run "$delegate" "hello task"
  [ "$status" -eq 0 ]
  [ "$output" = "response for model=fake-model-8080: hello task" ]
}
