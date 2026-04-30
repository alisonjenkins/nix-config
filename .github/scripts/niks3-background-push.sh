#!/usr/bin/env bash
# Background niks3 cache push with post-build-hook integration.
#
# Usage:
#   source .github/scripts/niks3-background-push.sh
#   niks3_start_drainer          # starts background push loop
#   # ... run nix builds ...
#   niks3_stop_and_final_push    # stops drainer (drains remaining queue)
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
_NIKS3_QUEUE_STOP="${NIKS3_QUEUE}.stop"
_NIKS3_DRAINER_PID=""

# Strip query strings from any URL in the stream. niks3 v1.4.0 logs full
# presigned URLs (including X-Amz-Signature) in WARN/ERROR messages because
# Go's url.Redacted() does not redact query parameters. GHA logs are
# user-visible (and public on public repos), so we must redact at the boundary.
niks3_redact() {
  # Backslash is excluded so we do not eat the escaped quote that closes the
  # URL inside a JSON-like error string like `error="Put \"https://...\""`.
  sed -u -E 's@(https?://[^?[:space:]"\\]+)\?[^[:space:]"\\]*@\1?<REDACTED>@g'
}

niks3_start_drainer() {
  rm -f "$_NIKS3_QUEUE_STOP"
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
              --auth-token "$NIKS3_TOKEN" 2>&1 | niks3_redact; then
              echo "[drainer] Batch $BATCH: done"
              break
            fi
            echo "::warning::[drainer] Batch $BATCH: attempt $attempt failed, retrying in 5s..."
            sleep 5
          done
        fi
        rm -f /tmp/niks3-processing
        continue
      fi
      # Queue is empty. Exit cleanly if shutdown was requested.
      if [ -e "$_NIKS3_QUEUE_STOP" ]; then
        break
      fi
      sleep 2
    done
  ) &
  _NIKS3_DRAINER_PID=$!
  echo "[drainer] Started (PID $_NIKS3_DRAINER_PID)"
}

niks3_stop_and_final_push() {
  # Signal drainer to exit after the queue is empty. We deliberately do NOT
  # `kill` the bash subshell — that orphans any in-flight niks3 child, which
  # then races with a "final push" run on the same multipart upload IDs and
  # causes 404s from the object store on Complete Multipart Upload.
  touch "$_NIKS3_QUEUE_STOP"
  if [ -n "$_NIKS3_DRAINER_PID" ]; then
    wait "$_NIKS3_DRAINER_PID" 2>/dev/null || true
    echo "[drainer] Stopped"
  fi
  rm -f "$_NIKS3_QUEUE_STOP"
}
