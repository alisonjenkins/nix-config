#!/usr/bin/env bash
# Install niks3 binary for the current architecture.
# Usage: install-niks3.sh
set -euo pipefail

NIKS3_VERSION="v1.4.0"
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  NIKS3_ARCH="x86_64" ;;
  aarch64) NIKS3_ARCH="arm64" ;;
  *)       echo "::error::Unsupported architecture: $ARCH"; exit 1 ;;
esac

echo "Installing niks3 ${NIKS3_VERSION} for ${NIKS3_ARCH}..."
curl -fsSL "https://github.com/Mic92/niks3/releases/download/${NIKS3_VERSION}/niks3_Linux_${NIKS3_ARCH}.tar.gz" \
  | sudo tar xz -C /usr/local/bin niks3
sudo chmod +x /usr/local/bin/niks3
echo "Installed: $(niks3 --version 2>&1 || echo niks3)"
