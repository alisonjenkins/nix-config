#!/usr/bin/env bash
# Clears the cached credits-exhausted cooldown that delegate.sh writes, for
# when the account's limit got raised (or the billing period reset) before
# the cooldown would otherwise have lapsed on its own.
set -euo pipefail

# Same resolution as delegate.sh: prefer an explicit override so this
# still works with neither XDG_CACHE_HOME nor HOME set.
if [[ -n "${DELEGATE_STATE_DIR:-}" ]]; then
  credits_state_dir="$DELEGATE_STATE_DIR"
elif [[ -n "${XDG_CACHE_HOME:-}" ]]; then
  credits_state_dir="$XDG_CACHE_HOME/delegate-to-copilot"
elif [[ -n "${HOME:-}" ]]; then
  credits_state_dir="$HOME/.cache/delegate-to-copilot"
else
  echo "error: none of DELEGATE_STATE_DIR, XDG_CACHE_HOME, or HOME are set — can't tell where delegate.sh would have cached a cooldown." >&2
  exit 1
fi
credits_cooldown_file="$credits_state_dir/credits-exhausted-until"

if [[ -f "$credits_cooldown_file" ]]; then
  rm -f "$credits_cooldown_file"
  echo "cleared: $credits_cooldown_file"
else
  echo "nothing to clear: $credits_cooldown_file does not exist"
fi
