#!/bin/bash
# Generate nix hashes for container images to pre-pull into Karpenter node AMIs.
# Reads the image list and runs nix-prefetch-docker for the specified architecture.
# Usage: update-prepull-hashes.sh [amd64|arm64]
#   If no arch specified, generates for both architectures.
# Outputs: flake-modules/karpenter-prepull-images.json
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTPUT="$REPO_ROOT/flake-modules/karpenter-prepull-images.json"
IMAGE_LIST="$REPO_ROOT/flake-modules/karpenter-prepull-images.txt"

if [ "${1:-}" = "amd64" ] || [ "${1:-}" = "arm64" ]; then
  ARCHES=("$1")
else
  ARCHES=("amd64" "arm64")
fi

if [ ! -f "$IMAGE_LIST" ]; then
  echo "::error::Image list not found: $IMAGE_LIST"
  exit 1
fi

IMAGES=$(grep -v '^\s*#' "$IMAGE_LIST" | grep -v '^\s*$')

if [ -z "$IMAGES" ]; then
  echo "::error::No images found in $IMAGE_LIST"
  exit 1
fi

echo "Fetching hashes for $(echo "$IMAGES" | wc -l) images..."
echo "["  > "$OUTPUT"

FIRST=true
for img in $IMAGES; do
  IMAGE_NAME="${img%%:*}"
  IMAGE_TAG="${img##*:}"

  for arch in "${ARCHES[@]}"; do
    echo "  Prefetching: $img ($arch)"
    PREFETCH=$(nix run nixpkgs#nix-prefetch-docker -- \
      --image-name "$IMAGE_NAME" \
      --image-tag "$IMAGE_TAG" \
      --arch "$arch" \
      --os linux 2>&1) || {
      echo "::warning::Failed to prefetch $img for $arch, skipping"
      continue
    }

    DIGEST=$(echo "$PREFETCH" | grep 'imageDigest' | sed 's/.*"\(sha256:[^"]*\)".*/\1/')
    HASH=$(echo "$PREFETCH" | grep 'hash = ' | sed 's/.*"\(sha256-[^"]*\)".*/\1/')

    if [ -z "$DIGEST" ] || [ -z "$HASH" ]; then
      echo "::warning::Could not parse prefetch output for $img ($arch)"
      continue
    fi

    if [ "$FIRST" = true ]; then
      FIRST=false
    else
      echo "," >> "$OUTPUT"
    fi

    cat >> "$OUTPUT" <<EOF
  {
    "imageName": "$IMAGE_NAME",
    "imageTag": "$IMAGE_TAG",
    "arch": "$arch",
    "imageDigest": "$DIGEST",
    "hash": "$HASH"
  }
EOF
  done
done

echo "]" >> "$OUTPUT"

echo "Wrote $(grep -c '"imageName"' "$OUTPUT") image entries to $OUTPUT"
