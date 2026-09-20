#!/usr/bin/env bash
# Clears the cached endpoint/model that delegate-to-local.sh's
# auto-detection writes — for when a different local server is now running
# (a new port, a different model loaded) and you don't want to wait for the
# next call's chat request to fail before it self-heals.
set -euo pipefail

# Same resolution as delegate-to-local.sh.
if [[ -n "${LOCAL_LLM_STATE_DIR:-}" ]]; then
  state_dir="$LOCAL_LLM_STATE_DIR"
elif [[ -n "${XDG_CACHE_HOME:-}" ]]; then
  state_dir="$XDG_CACHE_HOME/delegate-to-local"
elif [[ -n "${HOME:-}" ]]; then
  state_dir="$HOME/.cache/delegate-to-local"
else
  echo "error: none of LOCAL_LLM_STATE_DIR, XDG_CACHE_HOME, or HOME are set — can't tell where delegate-to-local.sh would have cached a detected endpoint." >&2
  exit 1
fi
cache_file="$state_dir/detected-endpoint.json"

if [[ -f "$cache_file" ]]; then
  rm -f "$cache_file"
  echo "cleared: $cache_file"
else
  echo "nothing to clear: $cache_file does not exist"
fi
