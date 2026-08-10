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
#   NIKS3_GCROOT_DIR  - GC root dir (default: /nix/var/nix/gcroots/gha)

set -euo pipefail

NIKS3_MAX_UPLOADS="${NIKS3_MAX_UPLOADS:-10}"
NIKS3_MAX_RETRIES="${NIKS3_MAX_RETRIES:-3}"
NIKS3_QUEUE="${NIKS3_QUEUE:-/tmp/niks3-queue}"
NIKS3_GCROOT_DIR="${NIKS3_GCROOT_DIR:-/nix/var/nix/gcroots/gha}"
_NIKS3_QUEUE_STOP="${NIKS3_QUEUE}.stop"
_NIKS3_DRAINER_PID=""

# The builder host runs the nix daemon with min-free=50G / max-free=100G, so it
# prunes mid-build under disk pressure. `nix build --no-link` leaves no GC root,
# so freshly built outputs could be collected in the window between the build
# finishing and the drainer pushing them — which showed up as
# "error: path '...' is not valid" killing an entire push batch.
#
# Roots must live under /nix/var/nix/gcroots to be visible to the HOST daemon.
# An indirect root (--out-link into the pod filesystem) is no good: the target
# path does not exist in the host's mount namespace, so the daemon treats it as
# dangling and collects the output anyway. NIKS3_GCROOT_DIR is a writable
# hostPath mount nested inside the otherwise read-only /nix/var.
#
# Echoes a path to pass to `nix build --out-link`.
niks3_gcroot_path() {
  local name="$1"
  # Namespaced by run id so concurrent jobs cannot collide, and so cleanup can
  # target only this run's roots.
  printf '%s/%s-%s' "$NIKS3_GCROOT_DIR" "${GITHUB_RUN_ID:-manual}" "$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '-')"
}

# Drop this run's roots so the host's short-retention GC can reclaim the store.
# Also sweeps roots older than a day, which is the only way roots leaked by a
# killed pod ever get cleaned up.
niks3_gcroot_cleanup() {
  [ -d "$NIKS3_GCROOT_DIR" ] || return 0
  rm -f "$NIKS3_GCROOT_DIR/${GITHUB_RUN_ID:-manual}-"* 2>/dev/null || true
  find "$NIKS3_GCROOT_DIR" -maxdepth 1 -type l -mtime +1 -delete 2>/dev/null || true
}

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
        # Belt and braces alongside the GC roots: drop anything the store no
        # longer has before expanding the closure. `nix path-info --recursive`
        # fails outright on the first invalid path, which would discard every
        # other path in the batch along with it.
        QUEUED=$(sort -u /tmp/niks3-processing)
        INVALID=$(printf '%s\n' "$QUEUED" | xargs -r nix-store --check-validity --print-invalid 2>/dev/null | sort -u || true)
        if [ -n "$INVALID" ]; then
          echo "::warning::[drainer] Batch $BATCH: $(printf '%s\n' "$INVALID" | grep -c .) queued path(s) no longer in the store, skipping them"
        fi
        VALID_ROOTS=$(comm -13 <(printf '%s\n' "$INVALID" | grep -v '^$') <(printf '%s\n' "$QUEUED" | grep -v '^$'))
        PUSH_PATHS=$(printf '%s\n' "$VALID_ROOTS" | grep -v '^$' | xargs -r nix path-info --recursive 2>/dev/null | sort -u || true)
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
  # Everything is pushed, so the outputs no longer need pinning.
  niks3_gcroot_cleanup
}
