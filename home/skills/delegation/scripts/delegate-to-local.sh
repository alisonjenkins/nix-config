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
  echo "env: LOCAL_LLM_URL (skip auto-detection, use this endpoint only)," >&2
  echo "     LOCAL_LLM_MODEL (skip auto-detection, use this model name)," >&2
  echo "     LOCAL_LLM_PROBE_TIMEOUT (seconds per candidate, default 0.5)" >&2
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
probed=()

if [[ -n "${LOCAL_LLM_URL:-}" ]]; then
  candidates=("$LOCAL_LLM_URL")
else
  candidates=("${default_candidates[@]}")
fi

for candidate in "${candidates[@]}"; do
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
  exit 2
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
