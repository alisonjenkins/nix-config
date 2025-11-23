#!/usr/bin/env bash
set -euo pipefail

# Devices
BOOT_DEV="/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB_S69ENF0R858096E-part2"
LUKS_DEV="/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB_S69ENF0R858096E-part3"

is_mounted() {
    mountpoint -q "$1" 2>/dev/null
}

# Mount the disks
## Root
if is_mounted /mnt; then
    echo "/mnt already mounted"
else
    echo "Mounting root"
    mount -t tmpfs -o size=16G none /mnt
fi

## Decrypt LUKS
if [[ ! -e /dev/mapper/crypted ]]; then
    echo "Opening LUKS"
    cryptsetup luksOpen "$LUKS_DEV" crypted

    # Wait for /dev/mapper/crypted to appear (max 10 seconds)
    timeout=20 # 20 * 0.5s = 10s
    while [ $timeout -gt 0 ] && [[ ! -e /dev/mapper/crypted ]]; do
        sleep 0.5
        timeout=$((timeout - 1))
    done
    if [[ ! -e /dev/mapper/crypted ]]; then
        echo "Error: /dev/mapper/crypted did not appear after opening LUKS" >&2
        exit 1
    fi

    # Activate LVM volume group if needed
    if ! vgs pool &>/dev/null || ! lvs pool/nix &>/dev/null; then
        echo "Activating LVM volume group"
        vgchange -ay pool
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

## Persistent volumes (ext4, not btrfs)
mkdir -p /mnt/nix /mnt/persistence /mnt/home

if is_mounted /mnt/nix; then
    echo "/mnt/nix already mounted"
else
    echo "Mounting /mnt/nix"
    mount /dev/pool/nix /mnt/nix
fi

if is_mounted /mnt/persistence; then
    echo "/mnt/persistence already mounted"
else
    echo "Mounting /mnt/persistence"
    mount /dev/pool/persistence /mnt/persistence
fi

if is_mounted /mnt/home; then
    echo "/mnt/home already mounted"
else
    echo "Mounting /mnt/home"
    mount /dev/pool/home /mnt/home
fi
