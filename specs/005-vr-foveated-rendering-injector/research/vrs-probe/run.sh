#!/usr/bin/env bash
# Builds and runs the shading-rate probe; build output goes to a temp dir, not the repo.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -d)"
export SRC OUT
trap 'rm -rf "$OUT"' EXIT

# Single quotes are intentional: the command string is expanded inside nix-shell.
# shellcheck disable=SC2016
nix-shell -p gcc vulkan-headers vulkan-loader shaderc vulkan-validation-layers --run '
  glslc --target-env=vulkan1.3 "$SRC/vrs.vert" -o "$OUT/vrs.vert.spv" &&
  glslc --target-env=vulkan1.3 "$SRC/vrs.frag" -o "$OUT/vrs.frag.spv" &&
  glslc --target-env=vulkan1.3 "$SRC/vrs_layer.vert" -o "$OUT/vrs_layer.vert.spv" &&
  gcc -std=gnu11 -O1 -g -Wall -Wextra -o "$OUT/vrs_probe" "$SRC/vrs_probe.c" -lvulkan &&
  cd "$OUT" &&
  VK_LAYER_PATH=$(nix-build "<nixpkgs>" -A vulkan-validation-layers --no-out-link)/share/vulkan/explicit_layer.d \
  VK_LAYER_DUPLICATE_MESSAGE_LIMIT=0 VK_LOADER_LAYERS_DISABLE="*lsfg*" ./vrs_probe'
