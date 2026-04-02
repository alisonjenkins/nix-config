#!/usr/bin/env bash
# Background niks3 cache push with post-build-hook integration.
#
# Usage:
#   source .github/scripts/niks3-background-push.sh
#   niks3_start_drainer          # starts background push loop
#   # ... run nix builds ...
#   niks3_stop_and_final_push    # stops drainer, pushes remaining paths
#
# Required environment variables:
#   NIKS3_SERVER_URL  - niks3 server URL
#   NIKS3_TOKEN       - niks3 auth token
#
# Optional environment variables:
#   NIKS3_MAX_UPLOADS - max concurrent uploads (default: 10)
#   NIKS3_MAX_RETRIES - max retry attempts per push (default: 3)
#   NIKS3_QUEUE       - queue file path (default: /tmp/niks3-queue)

set -euo pipefail

NIKS3_MAX_UPLOADS="${NIKS3_MAX_UPLOADS:-10}"
NIKS3_MAX_RETRIES="${NIKS3_MAX_RETRIES:-3}"
NIKS3_QUEUE="${NIKS3_QUEUE:-/tmp/niks3-queue}"
_NIKS3_DRAINER_PID=""

niks3_start_drainer() {
  touch "$NIKS3_QUEUE"

  (
    BATCH=0
    while true; do
      if [ -s "$NIKS3_QUEUE" ] && mv "$NIKS3_QUEUE" /tmp/niks3-processing 2>/dev/null; then
        touch "$NIKS3_QUEUE"
        PATHS=$(wc -l < /tmp/niks3-processing)
        BATCH=$((BATCH + 1))
        echo "[drainer] Batch $BATCH: pushing $PATHS path(s) to cache..."
        PUSH_PATHS=$(cat /tmp/niks3-processing | xargs -r nix path-info --recursive 2>/dev/null | sort -u)
        if [ -n "$PUSH_PATHS" ]; then
          for attempt in $(seq 1 "$NIKS3_MAX_RETRIES"); do
            if echo "$PUSH_PATHS" | xargs -r niks3 push \
              --server-url "$NIKS3_SERVER_URL" \
              --max-concurrent-uploads "$NIKS3_MAX_UPLOADS" \
              --auth-token "$NIKS3_TOKEN" 2>&1; then
              echo "[drainer] Batch $BATCH: done"
              break
            fi
            echo "::warning::[drainer] Batch $BATCH: attempt $attempt failed, retrying in 5s..."
            sleep 5
          done
        fi
        rm -f /tmp/niks3-processing
      fi
      sleep 2
    done
  ) &
  _NIKS3_DRAINER_PID=$!
  echo "[drainer] Started (PID $_NIKS3_DRAINER_PID)"
}

niks3_stop_and_final_push() {
  # Stop drainer
  if [ -n "$_NIKS3_DRAINER_PID" ]; then
    kill "$_NIKS3_DRAINER_PID" 2>/dev/null || true
    wait "$_NIKS3_DRAINER_PID" 2>/dev/null || true
    echo "[drainer] Stopped"
  fi

  # Merge any leftover queue + in-progress paths
  cat "$NIKS3_QUEUE" /tmp/niks3-processing 2>/dev/null | sort -u > /tmp/niks3-final || true
  if [ -s /tmp/niks3-final ]; then
    FINAL_PATHS=$(wc -l < /tmp/niks3-final)
    echo "[final push] Pushing $FINAL_PATHS remaining path(s) to cache..."
    FINAL_PUSH_PATHS=$(cat /tmp/niks3-final | xargs -r nix path-info --recursive 2>/dev/null | sort -u)
    if [ -n "$FINAL_PUSH_PATHS" ]; then
      for attempt in $(seq 1 "$NIKS3_MAX_RETRIES"); do
        if echo "$FINAL_PUSH_PATHS" | xargs -r niks3 push \
          --server-url "$NIKS3_SERVER_URL" \
          --max-concurrent-uploads "$NIKS3_MAX_UPLOADS" \
          --auth-token "$NIKS3_TOKEN" 2>&1; then
          echo "[final push] Done"
          break
        fi
        echo "::warning::[final push] Attempt $attempt failed, retrying in 5s..."
        sleep 5
      done
    fi
  else
    echo "[final push] No remaining paths to push"
  fi
}
