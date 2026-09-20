#!/usr/bin/env bash
# Stops the currently active local-LLM profile (see ../delegate-to-local.md)
# and clears the state file, freeing VRAM/unified memory. No-op, safe to
# run any time, with or without an active profile.
set -euo pipefail

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

if [[ ! -f "$active_file" ]]; then
  echo "nothing to stop: no active profile recorded at $active_file"
  exit 0
fi

profile="$(jq -r '.profile // "unknown"' "$active_file" 2>/dev/null || echo unknown)"
pid="$(jq -r '.pid // empty' "$active_file" 2>/dev/null || true)"

if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
  kill "$pid" 2>/dev/null || true
  for _ in $(seq 1 10); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.5
  done
  kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
  echo "stopped profile '$profile' (pid $pid)"
else
  echo "profile '$profile' was recorded active but its process ($pid) was already gone"
fi

rm -f "$active_file"
