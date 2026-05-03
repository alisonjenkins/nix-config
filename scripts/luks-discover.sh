#!/usr/bin/env bash
# Print the path of each crypto_LUKS partition on the system, one per
# line, sorted. Extracted from manage-luks's `pick_luks_device` so the
# discovery logic can be bats-tested independently of the kdialog
# menu.
#
# Why a 2-column FSTYPE,NAME read? The previous 4-column NAME,SIZE,
# MODEL,FSTYPE form silently dropped LUKS rows whenever MODEL was
# either empty (NVMe partition children — kernel reports MODEL only on
# the parent disk) or multi-word ("Samsung SSD 990 PRO 2TB"). FSTYPE
# would shift out of $4, awk's test would never match, and the picker
# would report no devices on hosts that clearly had a LUKS partition
# (e.g. Steam Deck post-disko at /dev/nvme0n1p3).
#
# Test hook (only set in tests):
#   LUKS_DISCOVER_LSBLK_CMD   command to run instead of `sudo lsblk
#                             -lnp -o FSTYPE,NAME`. Stdout must match
#                             that format (FSTYPE in column 1, NAME in
#                             column 2; rows for non-LUKS devices may
#                             have an empty FSTYPE column).

set -euo pipefail

if [ -n "${LUKS_DISCOVER_LSBLK_CMD:-}" ]; then
  # Use the test-hook command verbatim. eval is necessary so the
  # caller can pass argv (e.g. `cat fake.txt`).
  eval "$LUKS_DISCOVER_LSBLK_CMD"
else
  sudo lsblk -lnp -o FSTYPE,NAME
fi | awk '$1 == "crypto_LUKS" { print $2 }' | sort
