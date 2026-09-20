#!/usr/bin/env bash
# Lists profiles declared in profiles.json (see ../delegate-to-local.md),
# marking whichever one the state file says is active and whether that
# active one is actually still responding. Never loads or unloads
# anything — read-only.
set -euo pipefail

for bin in curl jq; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "error: '$bin' not found on PATH." >&2
    exit 1
  fi
done

if [[ -n "${LOCAL_LLM_PROFILES_FILE:-}" ]]; then
  profiles_file="$LOCAL_LLM_PROFILES_FILE"
elif [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
  profiles_file="$XDG_CONFIG_HOME/delegate-to-local/profiles.json"
elif [[ -n "${HOME:-}" ]]; then
  profiles_file="$HOME/.config/delegate-to-local/profiles.json"
else
  echo "error: none of LOCAL_LLM_PROFILES_FILE, XDG_CONFIG_HOME, or HOME are set — can't tell where profiles.json lives." >&2
  exit 1
fi

if [[ ! -f "$profiles_file" ]]; then
  echo "error: profiles file not found: $profiles_file — see ../delegate-to-local.md for its schema." >&2
  exit 1
fi

if ! jq -e . "$profiles_file" >/dev/null 2>&1; then
  echo "error: $profiles_file is not valid JSON." >&2
  exit 1
fi

if [[ -n "${LOCAL_LLM_STATE_DIR:-}" ]]; then
  state_dir="$LOCAL_LLM_STATE_DIR"
elif [[ -n "${XDG_CACHE_HOME:-}" ]]; then
  state_dir="$XDG_CACHE_HOME/delegate-to-local"
elif [[ -n "${HOME:-}" ]]; then
  state_dir="$HOME/.cache/delegate-to-local"
else
  state_dir=""
fi
active_file="${state_dir:+$state_dir/active-profile.json}"

active_name=""
active_url=""
if [[ -n "$active_file" && -f "$active_file" ]] && active_json="$(jq -e . "$active_file" 2>/dev/null)"; then
  active_name="$(jq -r '.profile // empty' <<<"$active_json")"
  active_url="$(jq -r '.url // empty' <<<"$active_json")"
fi

while IFS=$'\t' read -r name model description; do
  marker="  "
  status=""
  if [[ "$name" == "$active_name" ]]; then
    marker="* "
    if [[ -n "$active_url" ]] && curl -sS --max-time 1 "$active_url/v1/models" >/dev/null 2>&1; then
      status=" (active, responding)"
    else
      status=" (active, but not responding — it may have crashed)"
    fi
  fi
  printf '%s%s\t%s%s\t%s\n' "$marker" "$name" "$model" "$status" "$description"
done < <(jq -r 'to_entries[] | [.key, (.value.model // "?"), (.value.description // "")] | @tsv' "$profiles_file")
