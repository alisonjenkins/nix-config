#!/usr/bin/env bash
# Sends a self-contained text task to whichever local-LLM profile is
# currently active (see ../delegate-to-local.md). No tool-use loop: the
# target model cannot read/write files or run commands, so the task text
# must carry any context it needs.
#
# Loading a model is slow, so this never loads or switches profiles itself
# — that's a deliberate, separate step (switch-local-profile.sh). This
# script only reads which profile is already active and talks to it.
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

usage() {
  echo "usage: $0 <task>" >&2
  echo "env: LOCAL_LLM_URL (bypass profiles entirely, use this endpoint only)," >&2
  echo "     LOCAL_LLM_MODEL (override the model name sent in the request)," >&2
  echo "     LOCAL_LLM_EXPECT_PROFILE (fail with exit 4 if this profile isn't the active one)," >&2
  echo "     LOCAL_LLM_STATE_DIR (active-profile state location override)" >&2
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
base_url=""
model=""

if [[ -n "${LOCAL_LLM_URL:-}" ]]; then
  base_url="$LOCAL_LLM_URL"
  if models_json="$(curl -sS --max-time 1 "$base_url/v1/models" 2>/dev/null)"; then
    if discovered="$(jq -er '.data[0].id' <<<"$models_json" 2>/dev/null)"; then
      model="$discovered"
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
else
  if [[ -n "${LOCAL_LLM_STATE_DIR:-}" ]]; then
    state_dir="$LOCAL_LLM_STATE_DIR"
  elif [[ -n "${XDG_CACHE_HOME:-}" ]]; then
    state_dir="$XDG_CACHE_HOME/delegate-to-local"
  elif [[ -n "${HOME:-}" ]]; then
    state_dir="$HOME/.cache/delegate-to-local"
  else
    echo "error: none of LOCAL_LLM_STATE_DIR, XDG_CACHE_HOME, or HOME are set — can't tell where profile state lives." >&2
    exit 1
  fi
  active_file="$state_dir/active-profile.json"

  if [[ ! -f "$active_file" ]] || ! active_json="$(jq -e . "$active_file" 2>/dev/null)"; then
    echo "error: no local profile is active ($active_file not found or unreadable)" >&2
    echo "run switch-local-profile.sh <profile> first, or fall back to delegate-to-copilot.md / a Claude sub-agent for this task." >&2
    exit 2
  fi

  active_profile="$(jq -r '.profile // empty' <<<"$active_json")"

  if [[ -n "${LOCAL_LLM_EXPECT_PROFILE:-}" && "$LOCAL_LLM_EXPECT_PROFILE" != "$active_profile" ]]; then
    echo "error: expected profile '$LOCAL_LLM_EXPECT_PROFILE' to be active but '$active_profile' is loaded" >&2
    echo "run switch-local-profile.sh $LOCAL_LLM_EXPECT_PROFILE first." >&2
    exit 4
  fi

  base_url="$(jq -r '.url // empty' <<<"$active_json")"
  model="$(jq -r '.model // empty' <<<"$active_json")"

  if [[ -z "$base_url" ]] || ! curl -sS --max-time 1 "$base_url/v1/models" >/dev/null 2>&1; then
    echo "error: profile '$active_profile' is recorded active but its server isn't responding — it may have crashed" >&2
    echo "run switch-local-profile.sh $active_profile again, or fall back to delegate-to-copilot.md / a Claude sub-agent." >&2
    exit 2
  fi
fi

if [[ -n "${LOCAL_LLM_MODEL:-}" ]]; then
  model="$LOCAL_LLM_MODEL"
fi

request_body="$(jq -nc --arg model "$model" --arg task "$task" \
  '{model: $model, messages: [{role: "user", content: $task}]}')"

if ! response="$(curl -sS --fail-with-body -X POST "$base_url/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d "$request_body")"; then
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
