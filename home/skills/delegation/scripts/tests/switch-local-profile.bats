#!/usr/bin/env bats

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  switch="$script_dir/../switch-local-profile.sh"
  orig_path="$PATH"
  export PATH="$script_dir:$PATH"
  export LOCAL_LLM_PROFILES_FILE="$BATS_TEST_TMPDIR/profiles.toml"
  export LOCAL_LLM_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export FAKE_CURL_CALLS="$BATS_TEST_TMPDIR/curl-calls.log"
  export FAKE_RUNTIME_CALLS="$BATS_TEST_TMPDIR/runtime-calls.log"
  : >"$FAKE_CURL_CALLS"
  : >"$FAKE_RUNTIME_CALLS"
  export LOCAL_LLM_QUEUE_IDLE_TIMEOUT=2
  unset FAKE_CURL_UP FAKE_CURL_MODE FAKE_RUNTIME_MODE LOCAL_LLM_READY_TIMEOUT LOCAL_LLM_READY_INTERVAL
  cat >"$LOCAL_LLM_PROFILES_FILE" <<'TOML'
[fast]
runtime = "llama-server"
model = "/models/fast.gguf"
port = 8080
launch_args = ["--ctx-size", "8192"]
description = "quick profile"

[quality]
runtime = "mlx-lm"
model = "/models/quality"
port = 8081
description = "bigger, slower profile"

[broken-runtime]
runtime = "something-else"
model = "/models/x"

[missing-model]
runtime = "llama-server"
TOML
}

active_file() {
  echo "$LOCAL_LLM_STATE_DIR/active-profile.json"
}

teardown() {
  local pid
  if [[ -f "$(active_file)" ]]; then
    pid="$(jq -r '.pid // empty' "$(active_file)" 2>/dev/null || true)"
    [[ -n "$pid" ]] && kill -9 "$pid" 2>/dev/null || true
  fi
  worker_pidfile="$LOCAL_LLM_STATE_DIR/queue-worker.pid"
  if [[ -f "$worker_pidfile" ]]; then
    worker_pid="$(<"$worker_pidfile")"
    [[ -n "$worker_pid" ]] && kill -9 "$worker_pid" 2>/dev/null || true
  fi
}

@test "no args prints usage and exits 1" {
  run "$switch"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "unknown profile name exits 1 and lists available profiles" {
  run "$switch" "no-such-profile"
  [ "$status" -eq 1 ]
  [[ "$output" == *"profile 'no-such-profile' not found"* ]]
  [[ "$output" == *"fast"* ]]
  [[ "$output" == *"quality"* ]]
}

@test "missing profiles file exits 1" {
  rm -f "$LOCAL_LLM_PROFILES_FILE"
  run "$switch" "fast"
  [ "$status" -eq 1 ]
  [[ "$output" == *"profiles file not found"* ]]
}

@test "malformed TOML in the profiles file exits 1" {
  printf 'not = valid = toml =\n' >"$LOCAL_LLM_PROFILES_FILE"
  run "$switch" "fast"
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed to parse"*"as TOML"* ]]
}

@test "profile missing the model field exits 1" {
  run "$switch" "missing-model"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing required field"* ]]
}

@test "profile with an unknown runtime exits 1" {
  run "$switch" "broken-runtime"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown runtime 'something-else'"* ]]
}

@test "runtime binary not on PATH exits 1" {
  # Real system PATH, without the tests/ dir that provides the fake
  # llama-server/mlx_lm.server doubles — a real machine with neither
  # runtime installed looks exactly like this.
  PATH="$orig_path" run "$switch" "fast"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'llama-server' not found on PATH"* ]]
}

@test "successful switch launches the runtime, waits for readiness, and records active state" {
  export FAKE_CURL_UP="http://localhost:8080"
  run "$switch" "fast"
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile 'fast' active: fake-model-8080 on port 8080"* ]]

  [ -f "$(active_file)" ]
  [ "$(jq -r .profile "$(active_file)")" = "fast" ]
  [ "$(jq -r .url "$(active_file)")" = "http://localhost:8080" ]
  [ "$(jq -r .model "$(active_file)")" = "fake-model-8080" ]

  grep -q -- "-m /models/fast.gguf --port 8080 --ctx-size 8192" "$FAKE_RUNTIME_CALLS"

  pid="$(jq -r .pid "$(active_file)")"
  kill -0 "$pid" # still running afterward, the delegate can talk to it
}

@test "stops the previously active profile before loading the new one" {
  sleep 3600 </dev/null >/dev/null 2>&1 &
  old_pid=$!
  mkdir -p "$LOCAL_LLM_STATE_DIR"
  jq -nc --arg profile "old" --arg url "http://localhost:9999" --arg model "m" --argjson pid "$old_pid" \
    '{profile: $profile, url: $url, model: $model, pid: $pid}' >"$(active_file)"

  export FAKE_CURL_UP="http://localhost:8080"
  run "$switch" "fast"
  [ "$status" -eq 0 ]

  # `!` negates a bats/bash-errexit-invisible way — a bare `! kill -0 ...`
  # never fails the test even when the process is still alive, since set -e
  # ignores a negated command's status. Route through `run` instead.
  run kill -0 "$old_pid"
  [ "$status" -ne 0 ]
  [ "$(jq -r .profile "$(active_file)")" = "fast" ]
  kill -9 "$old_pid" 2>/dev/null || true # in case the assertion above failed
}

@test "times out and kills the process when the model never becomes ready" {
  export FAKE_CURL_UP=""
  export LOCAL_LLM_READY_TIMEOUT=1
  export LOCAL_LLM_READY_INTERVAL=0.3
  run "$switch" "fast"
  [ "$status" -eq 1 ]
  [[ "$output" == *"did not become ready within 1s"* ]]
  [ ! -f "$(active_file)" ]
}

@test "a process that exits immediately fails fast with a pointer to its log" {
  export FAKE_CURL_UP=""
  export FAKE_RUNTIME_MODE=exit-immediately
  export LOCAL_LLM_READY_TIMEOUT=30
  run "$switch" "fast"
  [ "$status" -eq 1 ]
  [[ "$output" == *"exited before becoming ready"* ]]
  [[ "$output" == *"$LOCAL_LLM_STATE_DIR/fast.log"* ]]
}

@test "defaults port to 8080 when the profile omits it" {
  cat >"$LOCAL_LLM_PROFILES_FILE" <<'TOML'
[no-port]
runtime = "llama-server"
model = "/models/x.gguf"
TOML
  export FAKE_CURL_UP="http://localhost:8080"
  run "$switch" "no-port"
  [ "$status" -eq 0 ]
  grep -q -- "--port 8080" "$FAKE_RUNTIME_CALLS"
}
