#!/usr/bin/env bash
# Sends a self-contained text task through the local-LLM queue worker (see
# ../delegate-to-local.md), which processes it strictly in order alongside
# any other queued delegate/switch/stop calls — so concurrent callers never
# race each other against the one loaded model. No tool-use loop: the
# target model cannot read/write files or run commands, so the task text
# must carry any context it needs.
#
# Loading a model is slow, so this never loads or switches profiles itself
# — that's a deliberate, separate step (switch-local-profile.sh).
#
# Exit codes are deliberately distinct so a caller can degrade gracefully:
#   1 = usage/dependency/config error (bad args, curl/jq missing, no
#       resolvable state dir) — a bug, not a reason to fall back.
#   2 = no profile is active, or the recorded one isn't actually
#       responding — expected on a machine with nothing loaded right now;
#       callers should treat this as "fall back to delegate-to-copilot.md
#       or a Claude sub-agent", not a hard failure.
#   3 = the active endpoint answered but the chat-completion call itself
#       failed or returned something unparseable — a real failure worth
#       surfacing.
#   4 = LOCAL_LLM_EXPECT_PROFILE was given and doesn't match the profile
#       actually active — the task assumed a specific model was loaded and
#       it wasn't; don't silently run against the wrong one.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/queue-common.sh
source "$script_dir/lib/queue-common.sh"

usage() {
  echo "usage: $0 <task>" >&2
  echo "env: LOCAL_LLM_URL (bypass the queue and profiles entirely, use this endpoint only)," >&2
  echo "     LOCAL_LLM_MODEL (override the model name sent in the request)," >&2
  echo "     LOCAL_LLM_EXPECT_PROFILE (fail with exit 4 if this profile isn't the active one)," >&2
  echo "     LOCAL_LLM_STATE_DIR (queue/state location override)," >&2
  echo "     LOCAL_LLM_QUEUE_TIMEOUT (seconds to wait for the queue, default 60)," >&2
  echo "     LOCAL_LLM_CHAT_TIMEOUT (seconds to wait for the chat completion itself, default 300)," >&2
  echo "     LOCAL_LLM_RESERVE_SECONDS (protect the active profile from being switched away for this" >&2
  echo "       long after each call — set it when you intend many calls, not for a single one;" >&2
  echo "       unset/0 means this call doesn't protect anything, the default)," >&2
  echo "     LOCAL_LLM_RESERVE_REASON (shown to whoever's switch gets refused because of the reservation)" >&2
  echo "exit codes: 1 usage/config error, 2 no profile active/reachable" >&2
  echo "  (fall back to another delegate), 3 the call itself failed, 4 wrong profile active" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

for bin in curl jq; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "error: '$bin' not found on PATH — required to call a local endpoint." >&2
    exit 1
  fi
done

task="$1"

if [[ -n "${LOCAL_LLM_URL:-}" ]]; then
  # An explicit endpoint bypasses the queue entirely — it isn't the
  # shared, profile-managed model, so there's nothing to serialize against.
  base_url="$LOCAL_LLM_URL"
  if models_json="$(curl -sS --max-time 1 "$base_url/v1/models" 2>/dev/null)"; then
    if discovered="$(jq -er '.data[0].id' <<<"$models_json" 2>/dev/null)"; then
      model="${LOCAL_LLM_MODEL:-$discovered}"
    else
      # A response arrived but wasn't shaped like an OpenAI-compatible
      # /v1/models reply — a genuinely different failure from "not
      # reachable" (curl succeeded, jq didn't), worth distinguishing so the
      # error points at the actual problem instead of implying the
      # endpoint is down.
      echo "error: LOCAL_LLM_URL=$base_url responded, but its /v1/models response wasn't the expected OpenAI-compatible shape" >&2
      echo "fall back to delegate-to-copilot.md or a Claude sub-agent for this task." >&2
      exit 2
    fi
  else
    echo "error: LOCAL_LLM_URL=$base_url is not reachable" >&2
    echo "fall back to delegate-to-copilot.md or a Claude sub-agent for this task." >&2
    exit 2
  fi

  request_body="$(jq -nc --arg model "$model" --arg task "$task" '{model: $model, messages: [{role: "user", content: $task}]}')"
  chat_timeout="$(numeric_env_or_default LOCAL_LLM_CHAT_TIMEOUT 300)"
  # 2>&1: a timeout or connection failure has no HTTP response body at all —
  # curl reports those on stderr, and a stdout-only capture left the error
  # detail blank (same fix as queue-worker.sh's equivalent call).
  if ! response="$(curl -sS --fail-with-body --max-time "$chat_timeout" -X POST "$base_url/v1/chat/completions" -H 'Content-Type: application/json' -d "$request_body" 2>&1)"; then
    echo "error: request to $base_url/v1/chat/completions failed" >&2
    echo "$response" >&2
    exit 3
  fi
  if ! reply="$(jq -er '.choices[0].message.content' <<<"$response" 2>/dev/null)"; then
    echo "error: unexpected response shape from $base_url — raw body:" >&2
    echo "$response" >&2
    exit 3
  fi
  printf '%s\n' "$reply"
  exit 0
fi

state_dir="$(resolve_local_llm_state_dir)" || {
  echo "error: none of LOCAL_LLM_STATE_DIR, XDG_CACHE_HOME, or HOME are set — can't tell where profile state lives." >&2
  exit 1
}
mkdir -p "$state_dir"

ensure_queue_worker_running "$state_dir" "$script_dir"

queue_timeout="$(numeric_env_or_default LOCAL_LLM_QUEUE_TIMEOUT 60)"
reserve_seconds="${LOCAL_LLM_RESERVE_SECONDS:-0}"
if ! [[ "$reserve_seconds" =~ ^[0-9]+$ ]]; then
  # The worker only renews reservations for integer values (it checks
  # ^[0-9]+$) — a decimal here would silently disable the reservation
  # rather than protecting the profile as the caller intended.
  echo "warning: \$LOCAL_LLM_RESERVE_SECONDS='$reserve_seconds' is not a non-negative integer; using 0 (no reservation)" >&2
  reserve_seconds=0
fi
reserve_reason="${LOCAL_LLM_RESERVE_REASON:-batch work via delegate-to-local.sh (pid $$)}"
job_json="$(jq -nc --arg task "$task" --arg model "${LOCAL_LLM_MODEL:-}" --arg expect "${LOCAL_LLM_EXPECT_PROFILE:-}" \
  --argjson reserve_seconds "$reserve_seconds" --arg reserve_reason "$reserve_reason" \
  '{type: "chat", task: $task, model_override: $model, expect_profile: $expect, reserve_seconds: $reserve_seconds, reserve_reason: $reserve_reason}')"

submit_and_wait "$state_dir" "$job_json" "$queue_timeout"
