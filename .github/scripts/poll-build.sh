#!/bin/bash
# Poll a remote EC2 builder for build completion.
# Usage: poll-build.sh <builder-ip> [ssh-key-path]
# Env: SSH_OPTS (optional, defaults to standard opts)
set -uo pipefail

BUILDER_IP="$1"
KEY_PATH="${2:-/tmp/builder_key}"
SSH_OPTS="${SSH_OPTS:--o StrictHostKeyChecking=no -o ServerAliveInterval=30 -o ServerAliveCountMax=5 -o TCPKeepAlive=yes}"

echo "Build running in background on $BUILDER_IP, polling for completion..."
CONSECUTIVE_FAILURES=0
while true; do
  sleep 30
  if ssh $SSH_OPTS -o ConnectTimeout=10 -i "$KEY_PATH" builder@"$BUILDER_IP" \
    "kill -0 \$(cat /tmp/build.pid) 2>/dev/null" 2>/dev/null; then
    CONSECUTIVE_FAILURES=0
    ssh $SSH_OPTS -o ConnectTimeout=10 -i "$KEY_PATH" builder@"$BUILDER_IP" \
      "tail -5 /tmp/build.log" 2>/dev/null || true
  else
    EXIT_CODE=$(ssh $SSH_OPTS -o ConnectTimeout=10 -i "$KEY_PATH" builder@"$BUILDER_IP" \
      "cat /tmp/build-exit 2>/dev/null || echo 255" 2>/dev/null) || {
      CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
      if [ $CONSECUTIVE_FAILURES -ge 6 ]; then
        echo "::error::Lost connection to builder instance after 6 retries (possible spot interruption or OOM)"
        exit 1
      fi
      echo "SSH failed (attempt $CONSECUTIVE_FAILURES/6), retrying in 30s..."
      continue
    }

    echo "=== Build finished (exit code: $EXIT_CODE) ==="
    ssh $SSH_OPTS -i "$KEY_PATH" builder@"$BUILDER_IP" \
      "tail -100 /tmp/build.log" 2>/dev/null || true
    exit "${EXIT_CODE:-1}"
  fi
done
