#!/usr/bin/env bash
# Checks lib.sh against a fake sysfs and a fake delegation scripts directory.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib.sh
source "$here/../lib.sh"

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

make_card() {
  local name=$1 total=$2 used=$3
  mkdir -p "$tmp/drm/$name/device"
  printf '%s' "$total" >"$tmp/drm/$name/device/mem_info_vram_total"
  printf '%s' "$used" >"$tmp/drm/$name/device/mem_info_vram_used"
}

# An iGPU enumerates first with a small aperture; the real GPU is card1.
make_card card0 536870912 46792704
make_card card1 17095983104 1640411136
export DRM_SYSFS_ROOT="$tmp/drm"

got=$(vram_used_bytes)
[[ "$got" == 1640411136 ]] || fail "vram_used_bytes picked the wrong card: $got"

DRM_SYSFS_ROOT="$tmp/empty" got=$(vram_used_bytes)
[[ "$got" == 0 ]] || fail "no card should report 0, got: $got"

mkdir -p "$tmp/deleg"
printf '#!/bin/sh\n' >"$tmp/deleg/switch-local-profile.sh"
chmod +x "$tmp/deleg/switch-local-profile.sh"
got=$(DELEGATION_SCRIPTS="$tmp/deleg" HOME="$tmp/nohome" find_delegation_scripts)
[[ "$got" == "$tmp/deleg" ]] || fail "DELEGATION_SCRIPTS override ignored: $got"

echo "test-lib: ok"
