#!/bin/bash
# Verify root filesystem was grown to fill EBS volume.
# Run on EC2 builder via: ssh builder bash < verify-disk.sh
set -uo pipefail

echo "=== Disk layout ==="
lsblk
echo "=== Filesystem usage ==="
df -h /
echo "=== Partition table ==="
sudo fdisk -l /dev/xvda 2>/dev/null || sudo fdisk -l /dev/nvme0n1 2>/dev/null || true

ROOT_FREE=$(df / --output=avail -B1G | tail -1 | tr -d ' ')
if [ "$ROOT_FREE" -lt 50 ]; then
  echo "::error::Root filesystem has only ${ROOT_FREE}G free — growpart may have failed"
  ROOT_PART=$(findmnt -no SOURCE /)
  PARTNAME=$(basename "$ROOT_PART")
  DISK="/dev/$(lsblk -no PKNAME "$ROOT_PART" | head -1)"
  PARTNUM=$(cat "/sys/class/block/${PARTNAME}/partition" 2>/dev/null || echo "")
  echo "=== Detected root: $ROOT_PART (disk=$DISK partnum=$PARTNUM) ==="
  sudo blkid "$ROOT_PART" || true
  echo "=== systemd-growfs status ==="
  sudo systemctl status systemd-growfs-root.service 2>&1 || true
  echo "=== cloud-init growpart log ==="
  sudo grep -i 'growpart\|resizefs\|resize2fs\|growfs' /var/log/cloud-init.log 2>/dev/null | tail -20 || true
  echo "=== Attempting manual resize ==="
  sudo growpart "$DISK" "$PARTNUM" || echo "growpart: partition already full size"
  echo "--- forcing kernel partition re-read ---"
  echo 1 | sudo tee "/sys/class/block/${PARTNAME}/resize" 2>/dev/null || \
    sudo partx -u "$DISK" 2>/dev/null || true
  echo "--- kernel partition size after re-read ---"
  lsblk "$ROOT_PART"
  echo "--- resize2fs attempt ---"
  sudo resize2fs "$ROOT_PART" || echo "resize2fs failed"
  df -h /
  ROOT_FREE=$(df / --output=avail -B1G | tail -1 | tr -d ' ')
  if [ "$ROOT_FREE" -lt 50 ]; then
    echo "::error::Disk still too small after manual growpart (${ROOT_FREE}G free)"
    exit 1
  fi
fi
echo "Disk OK: ${ROOT_FREE}G free"
