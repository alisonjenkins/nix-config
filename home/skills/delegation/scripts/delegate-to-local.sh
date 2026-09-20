#!/usr/bin/env bash
# Sends a self-contained text task to a locally-hosted, OpenAI-compatible
# chat-completions endpoint (llama-server, Ollama, LM Studio, ...). No
# tool-use loop: the target model cannot read/write files or run commands,
# so the task text must carry any context it needs (paste file contents in,
# don't ask it to open them). See ../delegate-to-local.md for when this is
# and isn't the right delegate.
#
# Never assumes which machine it's running on: with LOCAL_LLM_URL unset, it
# probes a short list of well-known default ports (llama-server, Ollama, LM
# Studio) with a fast per-candidate timeout and uses the first one that
# answers — one request per candidate, no per-machine config to maintain.
# The result is cached (see "Cache" below) so a repeat invocation on the
# same machine skips probing entirely.
#
# Exit codes are deliberately distinct so a caller can degrade gracefully:
#   1 = usage/dependency error (bad args, curl/jq missing) — a bug, not a
#       reason to fall back to another delegate.
#   2 = no local endpoint is reachable — expected on a machine with nothing
#       running locally; callers should treat this as "fall back to
#       delegate-to-copilot.md or a Claude sub-agent", not a hard failure.
#   3 = an endpoint answered but the chat-completion call itself failed or
#       returned something unparseable — a real failure worth surfacing.
set -euo pipefail

usage() {
  echo "usage: $0 <task>" >&2
  echo "env: LOCAL_LLM_URL (skip auto-detection and caching, use this endpoint only)," >&2
  echo "     LOCAL_LLM_MODEL (skip model auto-discovery, use this model name)," >&2
  echo "     LOCAL_LLM_PROBE_TIMEOUT (seconds per candidate, default 0.5)," >&2
  echo "     LOCAL_LLM_NO_CACHE (skip a cached endpoint and re-probe)," >&2
  echo "     LOCAL_LLM_STATE_DIR (cache location override)" >&2
  echo "exit codes: 1 usage/dependency error, 2 no local endpoint reachable" >&2
  echo "  (fall back to another delegate), 3 endpoint reachable but the call failed" >&2
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

# A non-numeric override would otherwise abort the whole script under set -e
# the first time it's used in a curl --max-time argument.
numeric_env_or_default() {
  local var_name="$1" default_value="$2" value="${!1:-}"
  if [[ -z "$value" ]]; then
    printf '%s' "$default_value"
    return
  fi
  if ! [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "warning: \$$var_name='$value' is not a non-negative number; using $default_value" >&2
    printf '%s' "$default_value"
    return
  fi
  printf '%s' "$value"
}

probe_timeout="$(numeric_env_or_default LOCAL_LLM_PROBE_TIMEOUT 0.5)"

if [[ -n "${LOCAL_LLM_STATE_DIR:-}" ]]; then
  state_dir="$LOCAL_LLM_STATE_DIR"
elif [[ -n "${XDG_CACHE_HOME:-}" ]]; then
  state_dir="$XDG_CACHE_HOME/delegate-to-local"
elif [[ -n "${HOME:-}" ]]; then
  state_dir="$HOME/.cache/delegate-to-local"
else
  state_dir=""
fi
cache_file="${state_dir:+$state_dir/detected-endpoint.json}"

# Well-known defaults for llama-server, Ollama, and LM Studio respectively.
# All three speak the OpenAI-compatible /v1/models shape, so one probe
# request per candidate both confirms reachability and discovers a model
# name in a single round trip.
default_candidates=(http://localhost:8080 http://localhost:11434 http://localhost:1234)

probe() {
  local url="$1"
  curl -sS --max-time "$probe_timeout" "$url/v1/models" 2>/dev/null
}

base_url=""
model=""

# Runs the full candidate probe, sets base_url/model on success, and caches
# the result. Only called for auto-detection (never for an explicit
# LOCAL_LLM_URL) — an explicit endpoint is cheap enough to just check once
# and isn't worth caching or invalidating.
run_probe() {
  local probed=()
  base_url=""
  model=""
  for candidate in "${default_candidates[@]}"; do
    probed+=("$candidate")
    if models_json="$(probe "$candidate")" && discovered="$(jq -er '.data[0].id' <<<"$models_json" 2>/dev/null)"; then
      base_url="$candidate"
      model="$discovered"
      break
    fi
  done

  if [[ -z "$base_url" ]]; then
    echo "error: no local model endpoint reachable — checked: ${probed[*]}" >&2
    echo "no local model is running, or LOCAL_LLM_URL points at the wrong place — fall back to delegate-to-copilot.md or a Claude sub-agent for this task." >&2
    return 1
  fi

  if [[ -n "$cache_file" ]]; then
    mkdir -p "$state_dir"
    jq -nc --arg url "$base_url" --arg model "$model" '{base_url: $url, model: $model}' >"$cache_file"
  fi
}

invalidate_cache() {
  [[ -n "$cache_file" ]] && rm -f "$cache_file"
  true
}

# Attempts the chat completion against $base_url/$model. Sets $reply on
# success. Returns the exit code to use if it fails (3 — a real failure,
# distinct from "no endpoint" — the caller decides whether to self-heal
# first via a fresh run_probe).
do_chat() {
  local request_body response
  request_body="$(jq -nc --arg model "$model" --arg task "$task" \
    '{model: $model, messages: [{role: "user", content: $task}]}')"

  if ! response="$(curl -sS --fail-with-body -X POST "$base_url/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    -d "$request_body")"; then
    echo "error: request to $base_url/v1/chat/completions failed" >&2
    echo "$response" >&2
    return 3
  fi

  if ! reply="$(jq -er '.choices[0].message.content' <<<"$response" 2>/dev/null)"; then
    echo "error: unexpected response shape from $base_url — raw body:" >&2
    echo "$response" >&2
    return 3
  fi
}

used_cache=0

if [[ -n "${LOCAL_LLM_URL:-}" ]]; then
  if models_json="$(probe "$LOCAL_LLM_URL")" && discovered="$(jq -er '.data[0].id' <<<"$models_json" 2>/dev/null)"; then
    base_url="$LOCAL_LLM_URL"
    model="$discovered"
  else
    echo "error: no local model endpoint reachable — checked: $LOCAL_LLM_URL" >&2
    echo "no local model is running, or LOCAL_LLM_URL points at the wrong place — fall back to delegate-to-copilot.md or a Claude sub-agent for this task." >&2
    exit 2
  fi
elif [[ -z "${LOCAL_LLM_NO_CACHE:-}" && -n "$cache_file" && -f "$cache_file" ]] \
  && cached="$(jq -e . "$cache_file" 2>/dev/null)" \
  && base_url="$(jq -er '.base_url' <<<"$cached" 2>/dev/null)" \
  && model="$(jq -er '.model' <<<"$cached" 2>/dev/null)"; then
  used_cache=1
else
  run_probe || exit 2
fi

if [[ -n "${LOCAL_LLM_MODEL:-}" ]]; then
  model="$LOCAL_LLM_MODEL"
fi

if do_chat; then
  :
else
  chat_status=$?
  # Only self-heal a cache-sourced endpoint: an explicit LOCAL_LLM_URL
  # failure is already the user's own choice, and a fresh run_probe()
  # failure has nothing left to retry against.
  if [[ "$used_cache" -eq 1 ]]; then
    echo "warning: cached endpoint $base_url stopped responding — invalidating cache and re-detecting" >&2
    invalidate_cache
    run_probe || exit 2
    if [[ -n "${LOCAL_LLM_MODEL:-}" ]]; then
      model="$LOCAL_LLM_MODEL"
    fi
    do_chat || exit 3
  else
    exit "$chat_status"
  fi
fi

printf '%s\n' "$reply"
