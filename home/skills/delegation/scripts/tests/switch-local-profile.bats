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

["evil/../name"]
runtime = "llama-server"
model = "/models/x.gguf"
port = 8083

[bad-port]
runtime = "llama-server"
model = "/models/x.gguf"
port = "not-a-number"
TOML
}

active_file() {
  echo "$LOCAL_LLM_STATE_DIR/active-profile.json"
}

reservation_file() {
  echo "$LOCAL_LLM_STATE_DIR/reservation.json"
}

reserve() {
  local profile="$1" seconds="$2" reason="${3:-batch work}"
  mkdir -p "$LOCAL_LLM_STATE_DIR"
  jq -nc --arg profile "$profile" --arg reason "$reason" --argjson expires "$(($(date +%s) + seconds))" \
    '{profile: $profile, reason: $reason, expires_at: $expires}' >"$(reservation_file)"
}

write_active() {
  # Default pid is a sentinel almost certainly not a live process — never
  # $$ (the test's own pid): teardown() does `kill -9 "$pid"` on whatever's
  # recorded here, and that would kill the test itself. Pass a real pid
  # explicitly (e.g. a backgrounded `sleep`) only for tests that actually
  # need a genuinely killable process.
  local pid="${4:-999999999}"
  mkdir -p "$LOCAL_LLM_STATE_DIR"
  jq -nc --arg profile "$1" --arg url "$2" --arg model "$3" --argjson pid "$pid" \
    '{profile: $profile, url: $url, model: $model, pid: $pid}' >"$(active_file)"
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

@test "a profile name containing a path separator is rejected before touching the filesystem" {
  run "$switch" "evil/../name"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid profile name"* ]]
  [ ! -e "$LOCAL_LLM_STATE_DIR/../name.log" ]
  [ ! -s "$FAKE_RUNTIME_CALLS" ]
}

@test "a non-numeric port is rejected" {
  run "$switch" "bad-port"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid port 'not-a-number'"* ]]
  [ ! -s "$FAKE_RUNTIME_CALLS" ]
}

@test "runtime binary not on PATH exits 1" {
  # Real system PATH, without the tests/ dir that provides the fake
  # llama-server/mlx_lm.server doubles — a real machine with neither
  # runtime installed looks exactly like this. A machine that has one
  # installed keeps its other tools (yq sits beside llama-server on
  # ali-desktop) through a directory linking everything but the runtimes.
  local no_runtimes="$BATS_TEST_TMPDIR/no-runtimes" clean_path="" dir tool
  mkdir -p "$no_runtimes"
  IFS=: read -ra dirs <<<"$orig_path"
  for dir in "${dirs[@]}"; do
    if [[ -x "$dir/llama-server" || -x "$dir/mlx_lm.server" ]]; then
      for tool in "$dir"/*; do
        case "${tool##*/}" in llama-server | mlx_lm.server) continue ;; esac
        [[ -e "$no_runtimes/${tool##*/}" ]] || ln -s "$tool" "$no_runtimes/${tool##*/}"
      done
      dir="$no_runtimes"
    fi
    clean_path="${clean_path:+$clean_path:}$dir"
  done
  PATH="$clean_path" run "$switch" "fast"
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

@test "a symlinked model is measured by its target, not the link" {
  # Nix store models are symlinks to the real file; measuring the link gave
  # 62 bytes for a 6.7GB model, so every fit check passed.
  ln -s "$BATS_TEST_TMPDIR/models/quality/weights.safetensors" "$BATS_TEST_TMPDIR/models/linked.gguf"
  cat >>"$LOCAL_LLM_PROFILES_FILE" <<TOML

[linked]
runtime = "llama-server"
model = "$BATS_TEST_TMPDIR/models/linked.gguf"
port = 8084
TOML
  fake_drm_vram 10737418240 17179869184 # 6GiB free; the 12GiB target does not fit
  export FAKE_CURL_UP="http://localhost:8084"
  run "$switch" "linked"
  [ "$status" -eq 1 ]
  [[ "$output" == *"profile 'linked' needs ~"* ]]
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

@test "refuses to switch away from a profile with an active reservation" {
  write_active "fast" "http://localhost:8080" "fake-model-8080"
  reserve "fast" 120 "big batch of edits"
  export FAKE_CURL_UP="http://localhost:8081"
  run "$switch" "quality"
  [ "$status" -eq 1 ]
  [[ "$output" == *"profile 'fast' is reserved for ~"* ]]
  [[ "$output" == *"big batch of edits"* ]]
  [[ "$output" == *"delegate-to-copilot.md or a Claude sub-agent"* ]]
  [[ "$output" == *"LOCAL_LLM_FORCE_SWITCH=1"* ]]
  [ "$(jq -r .profile "$(active_file)")" = "fast" ] # untouched
}

@test "LOCAL_LLM_FORCE_SWITCH=1 overrides an active reservation" {
  sleep 3600 </dev/null >/dev/null 2>&1 &
  old_pid=$!
  write_active "fast" "http://localhost:8080" "fake-model-8080" "$old_pid"
  reserve "fast" 120 "big batch of edits"
  export FAKE_CURL_UP="http://localhost:8081"
  export LOCAL_LLM_FORCE_SWITCH=1
  run "$switch" "quality"
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile 'quality' active"* ]]
  [ ! -f "$(reservation_file)" ] # cleared along with the profile it protected
  kill -9 "$old_pid" 2>/dev/null || true
}

@test "an expired reservation does not block a switch" {
  write_active "fast" "http://localhost:8080" "fake-model-8080"
  reserve "fast" -100 "long finished"
  export FAKE_CURL_UP="http://localhost:8081"
  run "$switch" "quality"
  [ "$status" -eq 0 ]
}

@test "a reservation for a profile that's already been replaced doesn't block a switch" {
  write_active "fast" "http://localhost:8080" "fake-model-8080"
  reserve "quality" 120 "stale — quality isn't even loaded" # active is fast, not quality
  export FAKE_CURL_UP="http://localhost:8081"
  run "$switch" "quality"
  [ "$status" -eq 0 ]
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

@test "a backend with /health reporting ok is treated as ready immediately" {
  export FAKE_CURL_UP="http://localhost:8080"
  export FAKE_CURL_MODE=health-ok
  run "$switch" "fast"
  [ "$status" -eq 0 ]
}

@test "a backend with /health stuck reporting loading never becomes ready" {
  export FAKE_CURL_UP="http://localhost:8080"
  export FAKE_CURL_MODE=health-loading
  export LOCAL_LLM_READY_TIMEOUT=1
  export LOCAL_LLM_READY_INTERVAL=0.3
  run "$switch" "fast"
  [ "$status" -eq 1 ]
  [[ "$output" == *"did not become ready within 1s"* ]]
}

@test "a backend that reports loading then ok becomes ready only once it actually says ok" {
  # Reproduces the real bug this fixed: llama-server's /v1/models answers
  # 200 while the model is still loading in the background, so a bare
  # reachability check reported ready before a chat call would actually
  # succeed. /health distinguishes the two.
  export FAKE_CURL_UP="http://localhost:8080"
  export FAKE_CURL_MODE=health-loading-then-ok
  export FAKE_CURL_HEALTH_COUNTER="$BATS_TEST_TMPDIR/health-counter"
  export FAKE_CURL_HEALTH_OK_ON=3
  export LOCAL_LLM_READY_INTERVAL=0.1
  run "$switch" "fast"
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_CURL_HEALTH_COUNTER")" -ge 3 ]
}

@test "reachable and /health-ok but the trial completion isn't ready yet: keeps polling until it truly is" {
  # Reproduces a second real gap found live: on a Vulkan-accelerated
  # llama-server build, /health reported ok several seconds before the
  # server could actually serve a completion (still uploading weights to
  # VRAM / compiling shaders) — /health alone isn't sufficient, only a
  # real trial request proves it.
  export FAKE_CURL_UP="http://localhost:8080"
  export FAKE_CURL_MODE=chat-loading-then-ok
  export FAKE_CURL_CHAT_COUNTER="$BATS_TEST_TMPDIR/chat-counter"
  export FAKE_CURL_CHAT_OK_ON=3
  export LOCAL_LLM_READY_INTERVAL=0.1
  run "$switch" "fast"
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_CURL_CHAT_COUNTER")" -ge 3 ]
}

@test "a real /health route reporting not-ready via a non-2xx status is not treated as a missing route" {
  # Regression: curl -f treats ANY non-2xx as a failure indistinguishable
  # from "connection refused" or "404, no such route" — a real /health
  # route (llama-server does exactly this) can legitimately answer 503
  # with a status body while loading. Falling back to /v1/models in that
  # case would defeat the whole point of checking /health at all, since
  # /v1/models answers 200 even while loading.
  export FAKE_CURL_UP="http://localhost:8080"
  export FAKE_CURL_MODE=health-503-loading
  export LOCAL_LLM_READY_TIMEOUT=1
  export LOCAL_LLM_READY_INTERVAL=0.3
  run "$switch" "fast"
  [ "$status" -eq 1 ]
  [[ "$output" == *"did not become ready within 1s"* ]]
}

@test "a backend with no /health route falls back to the plain /v1/models check" {
  # The mock runtime and mlx_lm.server don't implement /health — this is
  # the pre-existing behavior for them, confirmed explicitly rather than
  # just relying on every other test happening not to set FAKE_CURL_MODE.
  export FAKE_CURL_UP="http://localhost:8080"
  unset FAKE_CURL_MODE
  run "$switch" "fast"
  [ "$status" -eq 0 ]
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
