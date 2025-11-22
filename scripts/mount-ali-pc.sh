#!/usr/bin/env bash
set -euo pipefail

# Devices
BOOT_DEV="/dev/disk/by-id/nvme-CT4000T700SSD3_2328E6EDA130-part1"
LUKS_DEV="/dev/disk/by-id/nvme-CT4000T700SSD3_2328E6EDA130-part2"
BTRFS_DEV="/dev/mapper/osvg-persistence"

# Common btrfs mount options
BTRFS_OPTS="noatime,compress=zstd:3,ssd,discard=async,space_cache=v2"

is_mounted() {
    mountpoint -q "$1" 2>/dev/null
}

mount_btrfs() {
    local subvol="$1" target="$2"
    if is_mounted "$target"; then
        echo "$target already mounted"
    else
        echo "Mounting $target"
        mount -t btrfs -o "rw,${BTRFS_OPTS},subvol=${subvol}" "$BTRFS_DEV" "$target"
    fi
}

# Mount the disks
## Root
if is_mounted /mnt; then
    echo "/mnt already mounted"
else
    echo "Mounting root"
    mount -t tmpfs -o size=16G none /mnt
fi

## Decrypt osvg
if [[ ! -e /dev/mapper/osvg ]]; then
    echo "Opening LUKS"
    cryptsetup luksOpen "$LUKS_DEV" osvg

    # Wait for /dev/mapper/osvg to appear (max 10 seconds)
    timeout=20 # 20 * 0.5s = 10s
    while [ $timeout -gt 0 ] && [[ ! -e /dev/mapper/osvg ]]; do
        sleep 0.5
        timeout=$((timeout - 1))
    done
    if [[ ! -e /dev/mapper/osvg ]]; then
        echo "Error: /dev/mapper/osvg did not appear after opening LUKS" >&2
        exit 1
    fi

    # Activate LVM volume group if needed
    if ! vgs osvg &>/dev/null || ! lvs osvg/persistence &>/dev/null; then
        echo "Activating LVM volume group"
        vgchange -ay osvg
    fi
else
    echo "LUKS already open"
fi

## Boot (must be after /mnt exists)
mkdir -p /mnt/boot
if is_mounted /mnt/boot; then
    echo "/mnt/boot already mounted"
else
    echo "Mounting boot"
    mount "$BOOT_DEV" /mnt/boot
fi

## Persistent volumes
mkdir -p /mnt/nix /mnt/persistence
mount_btrfs /nix /mnt/nix
mount_btrfs /persistence /mnt/persistence
