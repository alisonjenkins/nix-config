#!/usr/bin/env bash
# Flash the installer ISO to a USB device and verify the write byte-for-byte.
#
# Usage: scripts/flash-installer-iso.sh [--legacy-bios|--strict-uefi] <device> [iso]
#   device:         target block device, e.g. /dev/sdb (REQUIRED, all data lost)
#   iso:            path to ISO (default: ./result/iso/*.iso)
#   --strict-uefi:  default. After dd, zero out the hybrid-MBR partition
#                   entries while keeping the 0x55AA boot signature and the
#                   GPT untouched. Avoids firmware that rejects the
#                   isohybrid layout (Steam Deck, some OEM UEFI) and silences
#                   fdisk's "does not start on physical sector boundary"
#                   warning that comes from the unaligned MBR view.
#   --legacy-bios:  opt out of strict-uefi and keep the hybrid MBR so the
#                   stick can boot a legacy-BIOS box.
#
# Exits non-zero on any failure including a SHA256 mismatch on read-back.

set -euo pipefail

STRICT_UEFI=1
case "${1:-}" in
  --legacy-bios) STRICT_UEFI=0; shift ;;
  --strict-uefi) STRICT_UEFI=1; shift ;;
esac

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "usage: $0 [--legacy-bios|--strict-uefi] <device> [iso]" >&2
  exit 2
fi

DEV=$1
ISO=${2:-}

if [ -z "$ISO" ]; then
  shopt -s nullglob
  candidates=(./result/iso/*.iso)
  shopt -u nullglob
  if [ ${#candidates[@]} -eq 0 ]; then
    echo "no ISO found in ./result/iso — pass one explicitly or run 'just iso' first" >&2
    exit 1
  fi
  if [ ${#candidates[@]} -gt 1 ]; then
    echo "multiple ISOs in ./result/iso — pass one explicitly:" >&2
    printf '  %s\n' "${candidates[@]}" >&2
    exit 1
  fi
  ISO=${candidates[0]}
fi

if [ ! -f "$ISO" ]; then
  echo "iso not found: $ISO" >&2
  exit 1
fi

if [ ! -b "$DEV" ]; then
  echo "not a block device: $DEV" >&2
  exit 1
fi

ISO_SIZE=$(stat -c%s "$ISO")

if command -v pv >/dev/null 2>&1; then
  USE_PV=1
else
  echo "warn: 'pv' not in PATH — falling back to 'dd status=progress'" >&2
  USE_PV=0
fi

echo "==> target device:"
lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS "$DEV"
echo
echo "==> iso: $ISO ($ISO_SIZE bytes)"
echo
read -r -p "ALL DATA on $DEV will be destroyed. Type 'yes' to continue: " confirm
if [ "$confirm" != "yes" ]; then
  echo "aborted" >&2
  exit 1
fi

echo "==> unmounting any partitions on $DEV"
for part in $(lsblk -lno NAME "$DEV" | tail -n +2); do
  sudo umount "/dev/$part" 2>/dev/null || true
done

echo "==> wiping existing signatures"
sudo wipefs -a "$DEV"

echo "==> writing ISO"
if [ "$USE_PV" = "1" ]; then
  pv -s "$ISO_SIZE" -- "$ISO" \
    | sudo dd of="$DEV" bs=4M conv=fsync oflag=direct status=none
else
  sudo dd if="$ISO" of="$DEV" bs=4M status=progress conv=fsync oflag=direct
fi

echo "==> flushing kernel buffers"
sync
sudo blockdev --flushbufs "$DEV"
sudo partprobe "$DEV" 2>/dev/null || true

echo "==> verifying read-back"
ISO_SHA=$(sha256sum "$ISO" | awk '{print $1}')
DEV_SHA=$(sudo dd if="$DEV" bs=1M count=$(((ISO_SIZE + 1048575) / 1048576)) iflag=direct status=none |
  head -c "$ISO_SIZE" | sha256sum | awk '{print $1}')

echo "    iso sha256: $ISO_SHA"
echo "    dev sha256: $DEV_SHA"

if [ "$ISO_SHA" != "$DEV_SHA" ]; then
  echo "MISMATCH — write failed or USB stick is bad" >&2
  exit 1
fi

if [ "$STRICT_UEFI" = "1" ]; then
  echo "==> strict-uefi: zeroing hybrid-MBR partition entries (sig + GPT preserved)"
  # MBR partition table is at offset 446, four 16-byte entries (64 bytes).
  # The 0x55AA boot signature lives at offset 510 and is left intact.
  # GPT at LBA 1 (offset 512) is untouched.
  sudo dd if=/dev/zero of="$DEV" bs=1 count=64 seek=446 conv=notrunc status=none
  sync
  sudo blockdev --flushbufs "$DEV"
  sudo partprobe "$DEV" 2>/dev/null || true
fi

echo "==> partition table on $DEV:"
sudo fdisk -l "$DEV"

echo
echo "OK — bootable ISO written to $DEV"
