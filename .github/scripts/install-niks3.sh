#!/usr/bin/env bash
# Install the niks3 binary for the current architecture onto PATH.
# Usage: install-niks3.sh
#
# Deliberately sudo-free. The self-hosted ARC runners set
# allowPrivilegeEscalation: false, so sudo cannot become root there and
# writing to /usr/local/bin is impossible. Install into a writable directory
# and put it on PATH for subsequent steps instead.
set -euo pipefail

NIKS3_VERSION="v1.4.0"
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  NIKS3_ARCH="x86_64" ;;
  aarch64) NIKS3_ARCH="arm64" ;;
  *)       echo "::error::Unsupported architecture: $ARCH"; exit 1 ;;
esac

BIN_DIR="${RUNNER_TEMP:-/tmp}/niks3-bin"
mkdir -p "$BIN_DIR"

if [ -x "$BIN_DIR/niks3" ]; then
  echo "niks3 already present at $BIN_DIR/niks3 — skipping download"
else
  echo "Installing niks3 ${NIKS3_VERSION} for ${NIKS3_ARCH} into ${BIN_DIR}..."
  curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
    "https://github.com/Mic92/niks3/releases/download/${NIKS3_VERSION}/niks3_Linux_${NIKS3_ARCH}.tar.gz" \
    | tar xz -C "$BIN_DIR" niks3
  chmod +x "$BIN_DIR/niks3"
fi

# GITHUB_PATH reaches subsequent steps; export covers this one.
export PATH="$BIN_DIR:$PATH"
if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$BIN_DIR" >> "$GITHUB_PATH"
fi

echo "Installed: $(command -v niks3)"
