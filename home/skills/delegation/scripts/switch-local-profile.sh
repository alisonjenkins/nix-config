#!/usr/bin/env bash
# Loads a named local-LLM profile through the local-LLM queue worker (see
# ../delegate-to-local.md), stopping whatever profile is currently running
# first. Loading a model takes real time (seconds to minutes depending on
# size), so this is a deliberate, occasional action — delegate-to-local.sh
# never triggers it automatically. Going through the same queue as
# delegate-to-local.sh means a switch waits its turn behind any chat calls
# already queued, and no chat call can run against a half-torn-down model.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/queue-common.sh
source "$script_dir/lib/queue-common.sh"

usage() {
  echo "usage: $0 <profile-name>" >&2
  echo "env: LOCAL_LLM_PROFILES_FILE (profiles.toml location override)," >&2
  echo "     LOCAL_LLM_STATE_DIR (state/log location override)," >&2
  echo "     LOCAL_LLM_READY_TIMEOUT (seconds to wait for the model to load, default 120)," >&2
  echo "     LOCAL_LLM_READY_INTERVAL (seconds between readiness checks, default 1)," >&2
  echo "     LOCAL_LLM_QUEUE_TIMEOUT (seconds to wait in the queue plus load time, default 180)," >&2
  echo "     LOCAL_LLM_VRAM_OVERHEAD_FRACTION (extra VRAM to budget beyond model size, default 0.2)," >&2
  echo "     LOCAL_LLM_VRAM_BUFFER_MB (flat VRAM buffer on top of that, default 512)," >&2
  echo "     LOCAL_LLM_FORCE_SWITCH=1 (skip the fits-in-free-VRAM safety check)" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

for bin in curl jq yq; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "error: '$bin' not found on PATH — required to manage a local profile (yq: mikefarah/yq, parses profiles.toml)." >&2
    exit 1
  fi
done

profile_name="$1"

if [[ -n "${LOCAL_LLM_PROFILES_FILE:-}" ]]; then
  profiles_file="$LOCAL_LLM_PROFILES_FILE"
elif [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
  profiles_file="$XDG_CONFIG_HOME/delegate-to-local/profiles.toml"
elif [[ -n "${HOME:-}" ]]; then
  profiles_file="$HOME/.config/delegate-to-local/profiles.toml"
else
  echo "error: none of LOCAL_LLM_PROFILES_FILE, XDG_CONFIG_HOME, or HOME are set — can't tell where profiles.toml lives." >&2
  exit 1
fi

if [[ ! -f "$profiles_file" ]]; then
  echo "error: profiles file not found: $profiles_file — see ../delegate-to-local.md for its schema." >&2
  exit 1
fi

state_dir="$(resolve_local_llm_state_dir)" || {
  echo "error: none of LOCAL_LLM_STATE_DIR, XDG_CACHE_HOME, or HOME are set — can't tell where to keep profile state." >&2
  exit 1
}
mkdir -p "$state_dir"

ready_timeout="$(numeric_env_or_default LOCAL_LLM_READY_TIMEOUT 120)"
ready_interval="$(numeric_env_or_default LOCAL_LLM_READY_INTERVAL 1)"
# The queue timeout has to cover both any wait behind other jobs AND the
# model's own load time, so it defaults comfortably above ready_timeout
# rather than a small fixed number.
queue_timeout="$(numeric_env_or_default LOCAL_LLM_QUEUE_TIMEOUT "$((${ready_timeout%.*} + 60))")"
vram_overhead_fraction="$(numeric_env_or_default LOCAL_LLM_VRAM_OVERHEAD_FRACTION 0.2)"
vram_buffer_mb="$(numeric_env_or_default LOCAL_LLM_VRAM_BUFFER_MB 512)"
vram_buffer_bytes="$((${vram_buffer_mb%.*} * 1024 * 1024))"
force_switch="${LOCAL_LLM_FORCE_SWITCH:-0}"

ensure_queue_worker_running "$state_dir" "$script_dir"

job_json="$(jq -nc --arg profile "$profile_name" --arg profiles_file "$profiles_file" \
  --argjson ready_timeout "$ready_timeout" --argjson ready_interval "$ready_interval" \
  --argjson vram_overhead_fraction "$vram_overhead_fraction" --argjson vram_buffer_bytes "$vram_buffer_bytes" \
  --arg force_switch "$force_switch" \
  '{type: "switch", profile: $profile, profiles_file: $profiles_file, ready_timeout: $ready_timeout, ready_interval: $ready_interval, vram_overhead_fraction: $vram_overhead_fraction, vram_buffer_bytes: $vram_buffer_bytes, force_switch: $force_switch}')"

submit_and_wait "$state_dir" "$job_json" "$queue_timeout"
