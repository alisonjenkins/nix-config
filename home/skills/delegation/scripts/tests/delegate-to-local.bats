#!/usr/bin/env bats

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  delegate="$script_dir/../delegate-to-local.sh"
  export PATH="$script_dir:$PATH"
  export FAKE_CURL_CALLS="$BATS_TEST_TMPDIR/calls.log"
  : >"$FAKE_CURL_CALLS"
  export LOCAL_LLM_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$LOCAL_LLM_STATE_DIR"
  # Keep test-run workers from lingering for the full 600s production
  # default — they're leftover clutter across a bats run, not a bug.
  export LOCAL_LLM_QUEUE_IDLE_TIMEOUT=2
  unset LOCAL_LLM_URL LOCAL_LLM_MODEL LOCAL_LLM_EXPECT_PROFILE FAKE_CURL_UP FAKE_CURL_MODE
}

write_active() {
  jq -nc --arg profile "$1" --arg url "$2" --arg model "$3" --argjson pid "$$" \
    '{profile: $profile, url: $url, model: $model, pid: $pid}' >"$LOCAL_LLM_STATE_DIR/active-profile.json"
}

teardown() {
  local worker_pidfile="$LOCAL_LLM_STATE_DIR/queue-worker.pid" worker_pid
  if [[ -f "$worker_pidfile" ]]; then
    worker_pid="$(<"$worker_pidfile")"
    [[ -n "$worker_pid" ]] && kill -9 "$worker_pid" 2>/dev/null || true
  fi
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
  # dirname (used to resolve the script's own directory before sourcing
  # lib/queue-common.sh) has to stay available, or the script dies on that
  # instead of reaching the curl/jq dependency check this test targets.
  empty_dir="$BATS_TEST_TMPDIR/empty-path"
  mkdir -p "$empty_dir"
  ln -s "$(command -v dirname)" "$empty_dir/dirname"
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

@test "many concurrent delegate calls are all served correctly by exactly one worker process" {
  write_active "fast" "http://localhost:8080" "fake-model-8080"
  export FAKE_CURL_UP="http://localhost:8080"

  local n=10 pids=() outs=()
  for i in $(seq 1 "$n"); do
    out="$BATS_TEST_TMPDIR/out-$i.log"
    outs+=("$out")
    "$delegate" "task $i" >"$out" 2>&1 &
    pids+=("$!")
  done
  for p in "${pids[@]}"; do wait "$p"; done

  for i in $(seq 1 "$n"); do
    [ "$(cat "${outs[$((i - 1))]}")" = "response for model=fake-model-8080: task $i" ]
  done

  # Confirms exactly one worker instance is alive for THIS test's own
  # queue — read-only (pgrep), never kills anything: teardown() cleans up
  # only the specific pid recorded in $LOCAL_LLM_STATE_DIR/queue-worker.pid.
  # A bare `pgrep -f "queue-worker.sh"` machine-wide count is non-hermetic:
  # on a shared runner (or just another bats test's worker still winding
  # down after its own LOCAL_LLM_QUEUE_IDLE_TIMEOUT), a second, unrelated
  # queue-worker.sh can be alive at the same instant and inflate the count
  # with no bug present. Cross-check each matched pid's own environment for
  # this test's specific state dir (Linux's /proc; falls back to trusting
  # the recorded pidfile alone where /proc isn't available, e.g. macOS).
  worker_count=0
  for candidate_pid in $(pgrep -f "queue-worker.sh"); do
    if [[ -r "/proc/$candidate_pid/environ" ]]; then
      if tr '\0' '\n' <"/proc/$candidate_pid/environ" 2>/dev/null | grep -qF "LOCAL_LLM_STATE_DIR=$LOCAL_LLM_STATE_DIR"; then
        worker_count=$((worker_count + 1))
      fi
    elif [[ "$candidate_pid" == "$(cat "$LOCAL_LLM_STATE_DIR/queue-worker.pid" 2>/dev/null)" ]]; then
      worker_count=$((worker_count + 1))
    fi
  done
  [ "$worker_count" -eq 1 ]
  # No manual kill here: teardown() already stops this test's specific
  # worker via the pid it recorded in its own pidfile — an unscoped
  # `kill "$(pgrep -f queue-worker.sh)"` here would kill every match
  # machine-wide, the same real-user-process hazard the comment above
  # already says this code doesn't have.
}

@test "a single call with no LOCAL_LLM_RESERVE_SECONDS creates no reservation" {
  write_active "fast" "http://localhost:8080" "fake-model-8080"
  export FAKE_CURL_UP="http://localhost:8080"
  run "$delegate" "hello task"
  [ "$status" -eq 0 ]
  [ ! -f "$LOCAL_LLM_STATE_DIR/reservation.json" ]
}

@test "LOCAL_LLM_RESERVE_SECONDS records a reservation for the active profile" {
  write_active "fast" "http://localhost:8080" "fake-model-8080"
  export FAKE_CURL_UP="http://localhost:8080"
  export LOCAL_LLM_RESERVE_SECONDS=120
  export LOCAL_LLM_RESERVE_REASON="a batch of edits"
  run "$delegate" "hello task"
  [ "$status" -eq 0 ]
  [ -f "$LOCAL_LLM_STATE_DIR/reservation.json" ]
  [ "$(jq -r .profile "$LOCAL_LLM_STATE_DIR/reservation.json")" = "fast" ]
  [ "$(jq -r .reason "$LOCAL_LLM_STATE_DIR/reservation.json")" = "a batch of edits" ]
  now="$(date +%s)"
  expires="$(jq -r .expires_at "$LOCAL_LLM_STATE_DIR/reservation.json")"
  [ "$((expires - now))" -ge 110 ]
  [ "$((expires - now))" -le 121 ]
}

@test "a failed call does not create or renew a reservation" {
  write_active "fast" "http://localhost:8080" "fake-model-8080"
  export FAKE_CURL_UP="http://localhost:8080"
  export FAKE_CURL_MODE=chat-error
  export LOCAL_LLM_RESERVE_SECONDS=120
  run "$delegate" "hello task"
  [ "$status" -eq 3 ]
  [ ! -f "$LOCAL_LLM_STATE_DIR/reservation.json" ]
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

@test "a chat call that times out with no HTTP response still reports why, not just 'failed:'" {
  write_active "fast" "http://localhost:8080" "fake-model-8080"
  export FAKE_CURL_UP="http://localhost:8080"
  export FAKE_CURL_MODE=chat-timeout
  run "$delegate" "hello task"
  [ "$status" -eq 3 ]
  [[ "$output" == *"request to http://localhost:8080/v1/chat/completions failed"* ]]
  # Regression: curl's own timeout/connection diagnostic is on stderr, not
  # stdout — a stdout-only capture reported "failed: " with nothing after
  # it, since a timeout has no HTTP response body to show.
  [[ "$output" == *"Operation timed out"* ]]
}
