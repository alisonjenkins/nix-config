#!/usr/bin/env bash
# Single serial worker for local-LLM delegation (see ../delegate-to-local.md):
# processes chat/switch/stop jobs strictly in submission order from
# $state_dir/queue/, one at a time, so llama-server/mlx_lm.server only ever
# see one client "in the driver's seat" no matter how many
# delegate-to-local.sh / switch-local-profile.sh / stop-local-profile.sh
# calls are running concurrently. Lazily auto-started by those scripts
# (ensure_queue_worker_running in lib/queue-common.sh) — not meant to be run
# by hand, though nothing stops you from watching its log. Exits itself
# after LOCAL_LLM_QUEUE_IDLE_TIMEOUT idle seconds (default 600) rather than
# running forever unattended; the next submitter respawns it lazily.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/queue-common.sh
source "$script_dir/lib/queue-common.sh"

state_dir="$(resolve_local_llm_state_dir)" || {
  echo "error: none of LOCAL_LLM_STATE_DIR, XDG_CACHE_HOME, or HOME are set." >&2
  exit 1
}
mkdir -p "$state_dir/queue" "$state_dir/results"
pidfile="$state_dir/queue-worker.pid"
echo "$$" >"$pidfile"
trap 'rm -f "$pidfile"' EXIT

idle_timeout="$(numeric_env_or_default LOCAL_LLM_QUEUE_IDLE_TIMEOUT 600)"

# Percentage of VRAM currently in use, or "unknown" if it can't be
# determined on this platform. AMDGPU sysfs today (matches
# detect-local-hardware.sh's approach) — works without rocm-smi or any
# userspace tool installed. LOCAL_LLM_DRM_GLOB overrides the probed path,
# for testing against a fake sysfs tree.
gpu_busy_percent() {
  local drm_glob="${LOCAL_LLM_DRM_GLOB:-/sys/class/drm/card*/device}"
  local dev_dir used total best_total=-1 best_used=0
  # A machine can expose several DRM devices (a real dGPU plus a tiny
  # display-only one) — pick the one with the largest VRAM pool, since
  # that's the one a model would actually load onto, not just whichever
  # sorts first.
  # shellcheck disable=SC2231 # word-splitting the glob is the intended behavior here
  for dev_dir in $drm_glob; do
    [[ -f "$dev_dir/mem_info_vram_used" && -f "$dev_dir/mem_info_vram_total" ]] || continue
    used="$(cat "$dev_dir/mem_info_vram_used" 2>/dev/null || true)"
    total="$(cat "$dev_dir/mem_info_vram_total" 2>/dev/null || true)"
    if [[ "$used" =~ ^[0-9]+$ && "$total" =~ ^[0-9]+$ && "$total" -gt "$best_total" ]]; then
      best_total="$total"
      best_used="$used"
    fi
  done
  if [[ "$best_total" -gt 0 ]]; then
    awk -v u="$best_used" -v t="$best_total" 'BEGIN{printf "%.0f", (u/t)*100}'
  else
    echo "unknown"
  fi
}

write_result() {
  local job_id="$1" exit_code="$2" output="$3" stderr_text="$4"
  jq -nc --argjson exit_code "$exit_code" --arg output "$output" --arg stderr "$stderr_text" \
    '{exit_code: $exit_code, output: $output, stderr: $stderr}' >"$state_dir/results/$job_id.result.tmp"
  mv "$state_dir/results/$job_id.result.tmp" "$state_dir/results/$job_id.result"
}

process_chat_job() {
  local job_json="$1" job_id="$2"
  local task model_override expect_profile
  task="$(jq -r '.task // empty' <<<"$job_json")"
  model_override="$(jq -r '.model_override // empty' <<<"$job_json")"
  expect_profile="$(jq -r '.expect_profile // empty' <<<"$job_json")"

  local active_file="$state_dir/active-profile.json" active_json
  if [[ ! -f "$active_file" ]] || ! active_json="$(jq -e . "$active_file" 2>/dev/null)"; then
    write_result "$job_id" 2 "" "no local profile is active. run switch-local-profile.sh <profile> first, or fall back to delegate-to-copilot.md / a Claude sub-agent."
    return
  fi

  local active_profile base_url model
  active_profile="$(jq -r '.profile // empty' <<<"$active_json")"
  if [[ -n "$expect_profile" && "$expect_profile" != "$active_profile" ]]; then
    write_result "$job_id" 4 "" "expected profile '$expect_profile' to be active but '$active_profile' is loaded. run switch-local-profile.sh $expect_profile first."
    return
  fi

  base_url="$(jq -r '.url // empty' <<<"$active_json")"
  model="$(jq -r '.model // empty' <<<"$active_json")"
  if [[ -z "$base_url" ]] || ! curl -sS --max-time 1 "$base_url/v1/models" >/dev/null 2>&1; then
    write_result "$job_id" 2 "" "profile '$active_profile' is recorded active but its server isn't responding — it may have crashed. run switch-local-profile.sh $active_profile again, or fall back."
    return
  fi
  [[ -n "$model_override" ]] && model="$model_override"

  local request_body response chat_timeout
  # The worker is strictly serial — a hung chat call here blocks every
  # subsequent chat/switch/stop job, not just this caller, so it needs a
  # bound even though delegate-to-local.sh's own queue_timeout also caps
  # how long ITS caller waits for a result.
  chat_timeout="$(numeric_env_or_default LOCAL_LLM_CHAT_TIMEOUT 300)"
  request_body="$(jq -nc --arg model "$model" --arg task "$task" '{model: $model, messages: [{role: "user", content: $task}]}')"
  # 2>&1: a timeout or connection failure has no HTTP response body at all —
  # curl reports those on stderr ("curl: (28) Operation timed out"), and a
  # stdout-only capture left the error message empty ("failed: ", no
  # detail). -sS's silent mode means stderr carries nothing extra on the
  # success path, so merging it in doesn't contaminate the JSON body parsed
  # below.
  if ! response="$(curl -sS --fail-with-body --max-time "$chat_timeout" -X POST "$base_url/v1/chat/completions" -H 'Content-Type: application/json' -d "$request_body" 2>&1)"; then
    write_result "$job_id" 3 "" "request to $base_url/v1/chat/completions failed: $response"
    return
  fi

  local reply
  if ! reply="$(jq -er '.choices[0].message.content' <<<"$response" 2>/dev/null)"; then
    write_result "$job_id" 3 "" "unexpected response shape from $base_url — raw body: $response"
    return
  fi
  write_result "$job_id" 0 "$reply" ""
}

process_switch_job() {
  local job_json="$1" job_id="$2"
  local profile_name profiles_file ready_timeout ready_interval gpu_busy_threshold force_switch
  profile_name="$(jq -r '.profile // empty' <<<"$job_json")"
  profiles_file="$(jq -r '.profiles_file // empty' <<<"$job_json")"
  ready_timeout="$(jq -r '.ready_timeout // 120' <<<"$job_json")"
  ready_interval="$(jq -r '.ready_interval // 1' <<<"$job_json")"
  gpu_busy_threshold="$(jq -r '.gpu_busy_threshold // 40' <<<"$job_json")"
  force_switch="$(jq -r '.force_switch // "0"' <<<"$job_json")"

  if [[ ! -f "$profiles_file" ]]; then
    write_result "$job_id" 1 "" "profiles file not found: $profiles_file"
    return
  fi
  local profiles_json
  if ! profiles_json="$(yq -p toml -o json '.' "$profiles_file" 2>&1)"; then
    write_result "$job_id" 1 "" "failed to parse $profiles_file as TOML: $profiles_json"
    return
  fi
  local profile_json
  if ! profile_json="$(jq -e --arg name "$profile_name" '.[$name]' <<<"$profiles_json" 2>/dev/null)" || [[ "$profile_json" == "null" ]]; then
    local available
    available="$(jq -r 'keys | join(", ")' <<<"$profiles_json" 2>/dev/null || echo "(unreadable profiles file)")"
    write_result "$job_id" 1 "" "profile '$profile_name' not found in $profiles_file — available: $available"
    return
  fi

  local runtime model port launch_args
  runtime="$(jq -r '.runtime // empty' <<<"$profile_json")"
  model="$(jq -r '.model // empty' <<<"$profile_json")"
  port="$(jq -r '.port // 8080' <<<"$profile_json")"
  readarray -t launch_args < <(jq -r '.launch_args[]? // empty' <<<"$profile_json")
  if [[ -z "$runtime" || -z "$model" ]]; then
    write_result "$job_id" 1 "" "profile '$profile_name' is missing required field 'runtime' or 'model' in $profiles_file"
    return
  fi

  local cmd
  case "$runtime" in
    llama-server) cmd=(llama-server -m "$model" --port "$port" "${launch_args[@]}") ;;
    mlx-lm) cmd=(mlx_lm.server --model "$model" --port "$port" "${launch_args[@]}") ;;
    mock) cmd=(python3 "$script_dir/mock-llm-server.py" --port "$port" --model "$model" "${launch_args[@]}") ;;
    *)
      write_result "$job_id" 1 "" "profile '$profile_name' has unknown runtime '$runtime' — expected 'llama-server', 'mlx-lm', or 'mock'"
      return
      ;;
  esac
  if ! command -v "${cmd[0]}" >/dev/null 2>&1; then
    write_result "$job_id" 1 "" "'${cmd[0]}' not found on PATH — required to run profile '$profile_name' (runtime: $runtime)."
    return
  fi

  # Safety gate: don't load a real model onto a GPU that's already doing
  # real work (a game). The mock runtime never touches the GPU, so it's
  # exempt; an explicit force_switch skips the check for someone who's
  # already sure it's fine.
  if [[ "$runtime" != "mock" && "$force_switch" != "1" ]]; then
    local busy_pct
    busy_pct="$(gpu_busy_percent)"
    if [[ "$busy_pct" =~ ^[0-9]+$ ]] && ((busy_pct >= gpu_busy_threshold)); then
      write_result "$job_id" 1 "" "GPU appears busy (${busy_pct}% VRAM used, threshold ${gpu_busy_threshold}%) — refusing to load '$profile_name' to avoid crashing whatever's using the GPU (e.g. a game). Set LOCAL_LLM_FORCE_SWITCH=1 to override if you're sure it's safe."
      return
    fi
  fi

  local active_file="$state_dir/active-profile.json"
  if [[ -f "$active_file" ]]; then
    local old_pid
    old_pid="$(jq -r '.pid // empty' "$active_file" 2>/dev/null || true)"
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
      kill "$old_pid" 2>/dev/null || true
      for _ in $(seq 1 10); do
        kill -0 "$old_pid" 2>/dev/null || break
        sleep 0.5
      done
      kill -0 "$old_pid" 2>/dev/null && kill -9 "$old_pid" 2>/dev/null || true
    fi
    rm -f "$active_file"
  fi

  local log_file="$state_dir/$profile_name.log"
  nohup "${cmd[@]}" </dev/null >"$log_file" 2>&1 &
  local new_pid=$!
  disown
  sleep 0.1 # let a fast-crashing process actually exit before the first check

  local elapsed=0
  until curl -sS --max-time 1 "http://localhost:$port/v1/models" >/dev/null 2>&1; do
    if ! kill -0 "$new_pid" 2>/dev/null; then
      write_result "$job_id" 1 "" "profile '$profile_name' exited before becoming ready — see $log_file"
      return
    fi
    sleep "$ready_interval"
    elapsed="$(awk -v e="$elapsed" -v i="$ready_interval" 'BEGIN{printf "%.2f", e+i}')"
    if awk -v e="$elapsed" -v t="$ready_timeout" 'BEGIN{exit !(e >= t)}'; then
      kill "$new_pid" 2>/dev/null || true
      write_result "$job_id" 1 "" "profile '$profile_name' did not become ready within ${ready_timeout}s — killed it; see $log_file"
      return
    fi
  done

  local discovered_model
  discovered_model="$(curl -sS --max-time 1 "http://localhost:$port/v1/models" 2>/dev/null | jq -er '.data[0].id' 2>/dev/null || echo "$model")"
  jq -nc --arg profile "$profile_name" --arg url "http://localhost:$port" --arg model "$discovered_model" --argjson pid "$new_pid" \
    '{profile: $profile, url: $url, model: $model, pid: $pid}' >"$active_file"
  write_result "$job_id" 0 "profile '$profile_name' active: $discovered_model on port $port (pid $new_pid)" ""
}

process_stop_job() {
  local job_id="$1"
  local active_file="$state_dir/active-profile.json"
  if [[ ! -f "$active_file" ]]; then
    write_result "$job_id" 0 "nothing to stop: no active profile recorded" ""
    return
  fi

  local profile pid output
  profile="$(jq -r '.profile // "unknown"' "$active_file" 2>/dev/null || echo unknown)"
  pid="$(jq -r '.pid // empty' "$active_file" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 10); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.5
    done
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
    output="stopped profile '$profile' (pid $pid)"
  else
    output="profile '$profile' was recorded active but its process ($pid) was already gone"
  fi
  rm -f "$active_file"
  write_result "$job_id" 0 "$output" ""
}

idle_elapsed=0
while :; do
  job_file="$(find "$state_dir/queue" -maxdepth 1 -name '*.job' 2>/dev/null | sort | head -n1)"
  if [[ -z "$job_file" ]]; then
    if awk -v e="$idle_elapsed" -v t="$idle_timeout" 'BEGIN{exit !(e >= t)}'; then
      exit 0
    fi
    sleep 0.2
    idle_elapsed="$(awk -v e="$idle_elapsed" 'BEGIN{printf "%.1f", e+0.2}')"
    continue
  fi
  idle_elapsed=0

  job_id="$(basename "$job_file" .job)"
  job_json="$(<"$job_file")"
  rm -f "$job_file"
  job_type="$(jq -r '.type // empty' <<<"$job_json")"
  case "$job_type" in
    chat) process_chat_job "$job_json" "$job_id" ;;
    switch) process_switch_job "$job_json" "$job_id" ;;
    stop) process_stop_job "$job_id" ;;
    *) write_result "$job_id" 1 "" "unknown job type '$job_type'" ;;
  esac
done
