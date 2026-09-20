#!/usr/bin/env bash
# Loads a named local-LLM profile (see ../delegate-to-local.md), stopping
# whatever profile is currently running first. Loading a model takes real
# time (seconds to minutes depending on size), so this is a deliberate,
# occasional action — delegate-to-local.sh never triggers it automatically.
set -euo pipefail

usage() {
  echo "usage: $0 <profile-name>" >&2
  echo "env: LOCAL_LLM_PROFILES_FILE (profiles.toml location override)," >&2
  echo "     LOCAL_LLM_STATE_DIR (state/log location override)," >&2
  echo "     LOCAL_LLM_READY_TIMEOUT (seconds to wait for the model to load, default 120)," >&2
  echo "     LOCAL_LLM_READY_INTERVAL (seconds between readiness checks, default 1)" >&2
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

ready_timeout="$(numeric_env_or_default LOCAL_LLM_READY_TIMEOUT 120)"
ready_interval="$(numeric_env_or_default LOCAL_LLM_READY_INTERVAL 1)"

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

if ! profiles_json="$(yq -p toml -o json '.' "$profiles_file" 2>&1)"; then
  echo "error: failed to parse $profiles_file as TOML:" >&2
  echo "$profiles_json" >&2
  exit 1
fi

if [[ -n "${LOCAL_LLM_STATE_DIR:-}" ]]; then
  state_dir="$LOCAL_LLM_STATE_DIR"
elif [[ -n "${XDG_CACHE_HOME:-}" ]]; then
  state_dir="$XDG_CACHE_HOME/delegate-to-local"
elif [[ -n "${HOME:-}" ]]; then
  state_dir="$HOME/.cache/delegate-to-local"
else
  echo "error: none of LOCAL_LLM_STATE_DIR, XDG_CACHE_HOME, or HOME are set — can't tell where to keep profile state." >&2
  exit 1
fi
mkdir -p "$state_dir"
active_file="$state_dir/active-profile.json"

if ! profile_json="$(jq -e --arg name "$profile_name" '.[$name]' <<<"$profiles_json" 2>/dev/null)" || [[ "$profile_json" == "null" ]]; then
  available="$(jq -r 'keys | join(", ")' <<<"$profiles_json" 2>/dev/null || echo "(unreadable profiles file)")"
  echo "error: profile '$profile_name' not found in $profiles_file — available: $available" >&2
  exit 1
fi

runtime="$(jq -r '.runtime // empty' <<<"$profile_json")"
model="$(jq -r '.model // empty' <<<"$profile_json")"
port="$(jq -r '.port // 8080' <<<"$profile_json")"
readarray -t launch_args < <(jq -r '.launch_args[]? // empty' <<<"$profile_json")

if [[ -z "$runtime" || -z "$model" ]]; then
  echo "error: profile '$profile_name' is missing required field 'runtime' or 'model' in $profiles_file" >&2
  exit 1
fi

case "$runtime" in
  llama-server) cmd=(llama-server -m "$model" --port "$port" "${launch_args[@]}") ;;
  mlx-lm) cmd=(mlx_lm.server --model "$model" --port "$port" "${launch_args[@]}") ;;
  *)
    echo "error: profile '$profile_name' has unknown runtime '$runtime' — expected 'llama-server' or 'mlx-lm'" >&2
    exit 1
    ;;
esac

if ! command -v "${cmd[0]}" >/dev/null 2>&1; then
  echo "error: '${cmd[0]}' not found on PATH — required to run profile '$profile_name' (runtime: $runtime)." >&2
  exit 1
fi

# Stop whatever's currently active before loading the new one — running two
# models at once isn't a resource option on hardware sized for exactly one.
if [[ -f "$active_file" ]]; then
  old_pid="$(jq -r '.pid // empty' "$active_file" 2>/dev/null || true)"
  old_profile="$(jq -r '.profile // "unknown"' "$active_file" 2>/dev/null || echo unknown)"
  if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
    echo "stopping active profile '$old_profile' (pid $old_pid)..." >&2
    kill "$old_pid" 2>/dev/null || true
    for _ in $(seq 1 10); do
      kill -0 "$old_pid" 2>/dev/null || break
      sleep 0.5
    done
    kill -0 "$old_pid" 2>/dev/null && kill -9 "$old_pid" 2>/dev/null || true
  fi
  rm -f "$active_file"
fi

log_file="$state_dir/$profile_name.log"
nohup "${cmd[@]}" </dev/null >"$log_file" 2>&1 &
new_pid=$!
disown
sleep 0.1 # let a fast-crashing process actually exit before the first check

elapsed=0
until curl -sS --max-time 1 "http://localhost:$port/v1/models" >/dev/null 2>&1; do
  if ! kill -0 "$new_pid" 2>/dev/null; then
    echo "error: profile '$profile_name' exited before becoming ready — see $log_file" >&2
    exit 1
  fi
  sleep "$ready_interval"
  elapsed="$(awk -v e="$elapsed" -v i="$ready_interval" 'BEGIN{printf "%.2f", e+i}')"
  if awk -v e="$elapsed" -v t="$ready_timeout" 'BEGIN{exit !(e >= t)}'; then
    echo "error: profile '$profile_name' did not become ready within ${ready_timeout}s — killing it; see $log_file" >&2
    kill "$new_pid" 2>/dev/null || true
    exit 1
  fi
done

discovered_model="$(curl -sS --max-time 1 "http://localhost:$port/v1/models" 2>/dev/null | jq -er '.data[0].id' 2>/dev/null || echo "$model")"

jq -nc --arg profile "$profile_name" --arg url "http://localhost:$port" --arg model "$discovered_model" --argjson pid "$new_pid" \
  '{profile: $profile, url: $url, model: $model, pid: $pid}' >"$active_file"

echo "profile '$profile_name' active: $discovered_model on port $port (pid $new_pid)"
