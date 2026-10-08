#!/usr/bin/env bash
# Shared helpers for the local-llm-setup scripts. Source it; do not run it.

die() {
  echo "error: $*" >&2
  exit 1
}

# The delegation skill owns switch-local-profile.sh and friends. Skills are
# linked as siblings under ~/.claude/skills or ~/.agents/skills, or live in the
# repo at home/skills, so look in each instead of assuming one layout.
find_delegation_scripts() {
  local candidate
  for candidate in \
    "${DELEGATION_SCRIPTS:-}" \
    "$HOME/.claude/skills/delegation/scripts" \
    "$HOME/.agents/skills/delegation/scripts" \
    "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/delegation/scripts"; do
    if [[ -n "$candidate" && -x "$candidate/switch-local-profile.sh" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  die "delegation scripts not found; set DELEGATION_SCRIPTS to the directory holding switch-local-profile.sh"
}

# An iGPU enumerates as card0 with a small aperture on machines like
# ali-desktop, so the first card is not the GPU that holds the model: pick the
# card that reports the most VRAM.
vram_card_dir() {
  local root=${DRM_SYSFS_ROOT:-/sys/class/drm} dir total best="" best_total=0
  for dir in "$root"/card*/device; do
    [[ -r "$dir/mem_info_vram_total" && -r "$dir/mem_info_vram_used" ]] || continue
    total=$(<"$dir/mem_info_vram_total")
    if ((total > best_total)); then
      best=$dir
      best_total=$total
    fi
  done
  [[ -n "$best" ]] && printf '%s\n' "$best"
}

vram_used_bytes() {
  local dir
  if dir=$(vram_card_dir); then
    cat "$dir/mem_info_vram_used"
  else
    echo 0
  fi
}

# The queue worker inherits PATH from whichever client started it, so a worker
# left running from an earlier profile keeps the earlier llama-server.
stop_worker() {
  local scripts=$1 state=${LOCAL_LLM_STATE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/delegate-to-local}
  "$scripts/stop-local-profile.sh" >/dev/null 2>&1 || true
  if [[ -f "$state/queue-worker.pid" ]]; then
    kill "$(cat "$state/queue-worker.pid")" 2>/dev/null || true
    rm -f "$state/queue-worker.pid"
    sleep 2
  fi
}

# engine "old" keeps PATH; "new" puts LLAMA_BIN_DIR first.
select_engine() {
  local engine=$1
  if [[ "$engine" == new ]]; then
    [[ -n "${LLAMA_BIN_DIR:-}" && -x "$LLAMA_BIN_DIR/llama-server" ]] ||
      die "engine 'new' needs LLAMA_BIN_DIR pointing at a directory with llama-server"
    export PATH="$LLAMA_BIN_DIR:$BASE_PATH"
  else
    export PATH="$BASE_PATH"
  fi
}
