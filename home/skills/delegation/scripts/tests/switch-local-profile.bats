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
  # This machine may have a real GPU with real sysfs VRAM stats — point the
  # busy-check at a nonexistent path by default so tests read "unknown"
  # (fail-open) rather than this machine's live, non-deterministic state.
  # Tests targeting the busy-check itself override this to a fake tree.
  export LOCAL_LLM_DRM_GLOB="$BATS_TEST_TMPDIR/no-such-drm/card*/device"
  unset FAKE_CURL_UP FAKE_CURL_MODE FAKE_RUNTIME_MODE LOCAL_LLM_READY_TIMEOUT LOCAL_LLM_READY_INTERVAL \
    LOCAL_LLM_FORCE_SWITCH LOCAL_LLM_VRAM_OVERHEAD_FRACTION LOCAL_LLM_VRAM_BUFFER_MB

  # Real (sparse — instant to create, no real disk use) model files so the
  # fit-check has an actual size to measure. fast.gguf ~4GiB, quality/ ~12GiB.
  mkdir -p "$BATS_TEST_TMPDIR/models/quality"
  truncate -s 4G "$BATS_TEST_TMPDIR/models/fast.gguf"
  truncate -s 12G "$BATS_TEST_TMPDIR/models/quality/weights.safetensors"

  cat >"$LOCAL_LLM_PROFILES_FILE" <<TOML
[fast]
runtime = "llama-server"
model = "$BATS_TEST_TMPDIR/models/fast.gguf"
port = 8080
launch_args = ["--ctx-size", "8192"]
description = "quick profile"

[quality]
runtime = "mlx-lm"
model = "$BATS_TEST_TMPDIR/models/quality"
port = 8081
description = "bigger, slower profile"

[repo-model]
runtime = "llama-server"
model = "some-org/some-repo-not-downloaded-yet"
port = 8082
description = "model size can't be determined locally"

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

# Points LOCAL_LLM_DRM_GLOB at a fake sysfs tree reporting the given
# used/total VRAM in bytes.
fake_drm_vram() {
  local used="$1" total="$2" dev_dir="$BATS_TEST_TMPDIR/fake-drm/card0/device"
  mkdir -p "$dev_dir"
  echo "$used" >"$dev_dir/mem_info_vram_used"
  echo "$total" >"$dev_dir/mem_info_vram_total"
  export LOCAL_LLM_DRM_GLOB="$BATS_TEST_TMPDIR/fake-drm/card*/device"
}

# Adds a second fake DRM device — for asserting the busy-check picks the
# device with the largest VRAM pool (the real dGPU) over a tiny secondary
# one (an iGPU or display-only device), not just whichever sorts first.
fake_drm_vram_second_device() {
  local card_name="$1" used="$2" total="$3" dev_dir="$BATS_TEST_TMPDIR/fake-drm/$card_name/device"
  mkdir -p "$dev_dir"
  echo "$used" >"$dev_dir/mem_info_vram_used"
  echo "$total" >"$dev_dir/mem_info_vram_total"
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

@test "the mock runtime works end to end against a real process and real HTTP, no fakes" {
  if ! command -v python3 >/dev/null 2>&1; then
    skip "python3 not on PATH"
  fi
  cat >"$LOCAL_LLM_PROFILES_FILE" <<TOML
[test]
runtime = "mock"
model = "mock-model"
port = 8199
TOML
  PATH="$orig_path" run "$switch" "test"
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile 'test' active: mock-model on port 8199"* ]]

  PATH="$orig_path" run "$script_dir/../delegate-to-local.sh" "real end to end"
  [ "$status" -eq 0 ]
  [ "$output" = "mock response from mock-model: real end to end" ]
}

@test "refuses to load a profile whose model won't fit in free VRAM, and suggests one that would" {
  fake_drm_vram 10737418240 17179869184 # 10GiB used of 16GiB -> 6GiB free
  export FAKE_CURL_UP="http://localhost:8081"
  run "$switch" "quality" # needs ~15GiB (12GiB * 1.2 + 512MiB) -- doesn't fit in 6GiB free
  [ "$status" -eq 1 ]
  [[ "$output" == *"profile 'quality' needs ~"*"of VRAM but only ~"*"is free right now"* ]]
  [[ "$output" == *"profiles that would fit instead: fast"* ]] # fast needs ~5.3GiB, fits in 6GiB
  [[ "$output" == *"LOCAL_LLM_FORCE_SWITCH=1"* ]]
  [ ! -f "$(active_file)" ]
  [ ! -s "$FAKE_RUNTIME_CALLS" ] # never even tried to launch anything
}

@test "refuses and reports no alternatives when nothing declared would fit either" {
  fake_drm_vram 17079869184 17179869184 # ~100MiB free
  export FAKE_CURL_UP="http://localhost:8081"
  run "$switch" "quality"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no other declared profile would fit right now either"* ]]
}

@test "proceeds normally when the requested profile's model fits in free VRAM" {
  fake_drm_vram 8589934592 17179869184 # 8GiB used -> 8GiB free, fast needs ~5.3GiB
  export FAKE_CURL_UP="http://localhost:8080"
  run "$switch" "fast"
  [ "$status" -eq 0 ]
}

@test "LOCAL_LLM_FORCE_SWITCH=1 overrides a doesn't-fit refusal" {
  fake_drm_vram 10737418240 17179869184 # 6GiB free -- quality doesn't fit
  export FAKE_CURL_UP="http://localhost:8081"
  export LOCAL_LLM_FORCE_SWITCH=1
  run "$switch" "quality"
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile 'quality' active"* ]]
}

@test "a higher LOCAL_LLM_VRAM_OVERHEAD_FRACTION can push a previously-fitting profile over the edge" {
  fake_drm_vram 10737418240 17179869184 # 6GiB free -- fits fast at the default 0.2 overhead
  export FAKE_CURL_UP="http://localhost:8080"
  export LOCAL_LLM_VRAM_OVERHEAD_FRACTION=1.0 # required becomes 4GiB*2 + 512MiB =~ 8.5GiB
  run "$switch" "fast"
  [ "$status" -eq 1 ]
  [[ "$output" == *"profile 'fast' needs ~"* ]]
}

@test "a model whose size can't be determined (bare repo id) fails open and proceeds" {
  fake_drm_vram 17079869184 17179869184 # ~100MiB free -- would refuse anything measurable
  export FAKE_CURL_UP="http://localhost:8082"
  run "$switch" "repo-model"
  [ "$status" -eq 0 ]
}

@test "picks the largest-VRAM device across multiple GPUs, not just the first one" {
  # A tiny secondary/display-only device reporting high usage (card0) must
  # not shadow the real, mostly-idle dGPU (card1) with far more VRAM —
  # this exact ordering (small device sorts first) is what a real machine
  # with an iGPU + dGPU looks like.
  fake_drm_vram_second_device card0 400000000 500000000 # 80% used of a tiny 512MB device
  fake_drm_vram_second_device card1 1000000000 17179869184 # tiny fraction of the real 16GiB card
  export LOCAL_LLM_DRM_GLOB="$BATS_TEST_TMPDIR/fake-drm/card*/device"
  export FAKE_CURL_UP="http://localhost:8080"
  run "$switch" "fast"
  [ "$status" -eq 0 ] # judged against card1's huge free space, not card0's near-full 512MB
}

@test "cannot determine VRAM usage (no sysfs data): fails open and proceeds" {
  export LOCAL_LLM_DRM_GLOB="$BATS_TEST_TMPDIR/nothing-here/card*/device"
  export FAKE_CURL_UP="http://localhost:8080"
  run "$switch" "fast"
  [ "$status" -eq 0 ]
}

@test "a stat failure on one file in a directory model doesn't kill the worker under set -e" {
  # Regression for a real bug: model_size_bytes() returning non-zero on an
  # unstat-able file (this test's fake stat, simulating a file that vanished
  # mid-scan) used to abort the whole queue-worker.sh script under `set -e`
  # via the bare `candidate_bytes="$(model_size_bytes ...)"` assignment —
  # fixed with `|| true` at both call sites.
  touch "$BATS_TEST_TMPDIR/models/quality/UNSTATABLE.bin"
  fake_drm_vram 17079869184 17179869184 # ~100MiB free -- forces the fit check to actually run
  export FAKE_CURL_UP="http://localhost:8081"
  run "$switch" "quality"
  [ "$status" -eq 0 ] # unknown size for this profile's own model -> fails open
}

@test "the mock runtime is exempt from the fit check" {
  if ! command -v python3 >/dev/null 2>&1; then
    skip "python3 not on PATH"
  fi
  fake_drm_vram 17079869184 17179869184 # ~100MiB free -- would refuse llama-server/mlx-lm
  cat >"$LOCAL_LLM_PROFILES_FILE" <<TOML
[test]
runtime = "mock"
model = "mock-model"
port = 8198
TOML
  PATH="$orig_path" run "$switch" "test"
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile 'test' active: mock-model on port 8198"* ]]
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

  grep -q -- "-m $BATS_TEST_TMPDIR/models/fast.gguf --port 8080 --ctx-size 8192" "$FAKE_RUNTIME_CALLS"

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
