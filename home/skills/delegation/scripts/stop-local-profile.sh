#!/usr/bin/env bash
# Stops the currently active local-LLM profile through the local-LLM queue
# worker (see ../delegate-to-local.md) and clears the state file, freeing
# VRAM/unified memory. No-op, safe to run any time, with or without an
# active profile. Goes through the same queue as delegate-to-local.sh and
# switch-local-profile.sh so it can't race a chat call that's mid-flight.
# Refused (like a switch) if another session has an active reservation on
# it (LOCAL_LLM_RESERVE_SECONDS) — LOCAL_LLM_FORCE_SWITCH=1 overrides.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/queue-common.sh
source "$script_dir/lib/queue-common.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "error: 'jq' not found on PATH — required to submit and parse the stop job." >&2
  exit 1
fi

state_dir="$(resolve_local_llm_state_dir)" || {
  echo "error: none of LOCAL_LLM_STATE_DIR, XDG_CACHE_HOME, or HOME are set — can't tell where profile state lives." >&2
  exit 1
}
mkdir -p "$state_dir"

ensure_queue_worker_running "$state_dir" "$script_dir"

queue_timeout="$(numeric_env_or_default LOCAL_LLM_QUEUE_TIMEOUT 30)"
force_switch="${LOCAL_LLM_FORCE_SWITCH:-0}"
job_json="$(jq -nc --arg force_switch "$force_switch" '{type: "stop", force_switch: $force_switch}')"

submit_and_wait "$state_dir" "$job_json" "$queue_timeout"
