#!/bin/sh
# Grow root filesystem to fill the EBS volume.
# Detect root partition dynamically via findmnt/lsblk.
ROOT_PART=$(findmnt -no SOURCE /)
if [ -n "$ROOT_PART" ]; then
  PARTNAME=$(basename "$ROOT_PART")
  DISK="/dev/$(lsblk -no PKNAME "$ROOT_PART" | head -1)"
  PARTNUM=$(cat "/sys/class/block/${PARTNAME}/partition" 2>/dev/null || echo "")
  if [ -n "$PARTNUM" ] && [ -b "$DISK" ]; then
    growpart "$DISK" "$PARTNUM" 2>/dev/null || true
    # Force kernel to re-read partition size from on-disk table
    echo 1 > "/sys/class/block/${PARTNAME}/resize" 2>/dev/null || partx -u "$DISK" 2>/dev/null || true
    resize2fs "$ROOT_PART" 2>&1 || xfs_growfs / 2>&1 || true
  fi
fi
echo '__NIKS3_TOKEN__' > /etc/niks3-token
chown builder:users /etc/niks3-token
chmod 600 /etc/niks3-token
mkdir -p /home/builder/.ssh
echo '__SSH_PUBKEY__' >> /home/builder/.ssh/authorized_keys
chmod 700 /home/builder/.ssh
chmod 600 /home/builder/.ssh/authorized_keys
chown -R builder:users /home/builder/.ssh
