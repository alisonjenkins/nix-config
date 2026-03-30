#!/bin/bash
# Build nix expressions on EC2 and push results to niks3 cache.
# Usage: ec2-build.sh <nix-expr> [<nix-expr>...]
# Expects /etc/niks3-token to contain the auth token.
set -uo pipefail

if [ $# -eq 0 ]; then
  echo "Usage: ec2-build.sh <nix-expr> [<nix-expr>...]"
  exit 1
fi

# Add swap to prevent OOM killing sshd during heavy builds
if [ ! -f /var/tmp/swapfile ]; then
  sudo fallocate -l 16G /var/tmp/swapfile
  sudo chmod 600 /var/tmp/swapfile
  sudo mkswap /var/tmp/swapfile
  sudo swapon /var/tmp/swapfile
  echo "Swap enabled: $(swapon --show)"
fi

NIKS3_TOKEN=$(cat /etc/niks3-token)
QUEUE=/tmp/niks3-queue
touch "$QUEUE"

# Background drainer: watches queue and pushes paths as they appear
(
  BATCH=0
  while true; do
    if [ -s "$QUEUE" ] && mv "$QUEUE" /tmp/niks3-processing 2>/dev/null; then
      touch "$QUEUE"
      PATHS=$(wc -l < /tmp/niks3-processing)
      BATCH=$((BATCH + 1))
      echo "[drainer] Batch $BATCH: pushing $PATHS path(s) to cache..."
      if cat /tmp/niks3-processing | xargs -r nix path-info --recursive 2>/dev/null | sort -u | xargs -r niks3 push \
        --server-url https://api.nixcache.org \
        --max-concurrent-uploads 10 \
        --auth-token "$NIKS3_TOKEN" 2>&1; then
        echo "[drainer] Batch $BATCH: done"
      else
        echo "[drainer] Batch $BATCH: push failed (exit $?), will retry remaining paths later"
      fi
      rm -f /tmp/niks3-processing
    fi
    sleep 5
  done
) &
DRAINER_PID=$!
echo "$DRAINER_PID" > /tmp/drainer.pid

sudo mkdir -p /var/tmp/nix-build
sudo chown builder:users /var/tmp/nix-build
export TMPDIR=/var/tmp/nix-build

if [ -d ~/nix-config ]; then
  cd ~/nix-config
  git fetch origin main
  git reset --hard origin/main
else
  git clone https://github.com/alisonjenkins/nix-config.git ~/nix-config
  cd ~/nix-config
fi

any_failed=false
for expr in "$@"; do
  echo "=== Building $expr ==="
  if nix build -L --keep-going --print-out-paths --no-link \
    "$expr" \
    2> >(tee -a /tmp/nix-build-stderr.log >&2) >> "$QUEUE"; then
    echo "=== $expr complete ==="
  else
    echo "::warning::$expr build failed"
    any_failed=true
  fi
done

# Stop drainer and do final push of any remaining paths
kill $DRAINER_PID 2>/dev/null || true
wait $DRAINER_PID 2>/dev/null || true

cat "$QUEUE" /tmp/niks3-processing 2>/dev/null | sort -u > /tmp/niks3-final || true
if [ -s /tmp/niks3-final ]; then
  FINAL_PATHS=$(wc -l < /tmp/niks3-final)
  echo "[final push] Pushing $FINAL_PATHS remaining path(s) to cache..."
  cat /tmp/niks3-final | xargs -r nix path-info --recursive 2>/dev/null | sort -u | xargs -r niks3 push \
    --server-url https://api.nixcache.org \
    --max-concurrent-uploads 10 \
    --auth-token "$NIKS3_TOKEN" 2>&1 || echo "[final push] Failed (exit $?)"
  echo "[final push] Done"
else
  echo "[final push] No remaining paths to push"
fi

if [ "$any_failed" = true ]; then
  echo 1 > /tmp/build-exit
else
  echo 0 > /tmp/build-exit
fi
