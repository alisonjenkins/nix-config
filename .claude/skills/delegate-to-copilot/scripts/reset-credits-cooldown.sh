#!/usr/bin/env bash
# Clears the cached credits-exhausted cooldown that delegate.sh writes, for
# when the account's limit got raised (or the billing period reset) before
# the cooldown would otherwise have lapsed on its own.
set -euo pipefail

credits_state_dir="${DELEGATE_STATE_DIR:-${XDG_CACHE_HOME:-${HOME:-}/.cache}/delegate-to-copilot}"
credits_cooldown_file="$credits_state_dir/credits-exhausted-until"

if [[ -f "$credits_cooldown_file" ]]; then
  rm -f "$credits_cooldown_file"
  echo "cleared: $credits_cooldown_file"
else
  echo "nothing to clear: $credits_cooldown_file does not exist"
fi
