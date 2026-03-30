#!/bin/bash
# Pre-pull container images into a VHD for Karpenter node AMIs.
# Usage: ami-prepull-images.sh <vhd-path> <arch>
#
# Downloads images listed in the home-cluster repo's prepull list as
# docker-archive tars into /var/lib/rancher/k3s/agent/images/ inside
# the VHD. k3s auto-imports these on first start.
#
# After pulling, verifies every expected image has a non-empty tar.
# Outputs PREPULL_VHD=<path> to $GITHUB_ENV with the modified VHD path.
set -euo pipefail

VHD="$1"
ARCH="$2"
IMAGE_LIST_URL="https://raw.githubusercontent.com/alisonjenkins/home-cluster/main/clusters/aws-k3s/karpenter-node-prepull-images.txt"
IMAGES_DIR_REL="var/lib/rancher/k3s/agent/images"

# --- Mount VHD ---
WORK_VHD="/tmp/ami-work.vhd"
cp "$VHD" "$WORK_VHD"

LOOP=$(sudo losetup --find --show --partscan "$WORK_VHD")
echo "Loop device: $LOOP"
lsblk "$LOOP" || true
sudo fdisk -l "$LOOP" || true

# Find the largest partition (root) — layout varies by arch
ROOT_PART=$(lsblk -lnpo NAME,SIZE "$LOOP" | grep -v "^${LOOP} " | sort -k2 -h | tail -1 | awk '{print $1}')
if [ -z "$ROOT_PART" ]; then
  echo "::error::No partitions found in VHD"
  sudo losetup -d "$LOOP"
  exit 1
fi
echo "Root partition: $ROOT_PART"

sudo mkdir -p /mnt/ami
sudo mount "$ROOT_PART" /mnt/ami

IMAGES_DIR="/mnt/ami/$IMAGES_DIR_REL"
sudo mkdir -p "$IMAGES_DIR"

# --- Fetch image list ---
IMAGES=$(curl -sfL "$IMAGE_LIST_URL" | grep -v '^\s*#' | grep -v '^\s*$')
IMAGE_COUNT=$(echo "$IMAGES" | wc -l)
echo "Fetched $IMAGE_COUNT images from prepull list"

# --- Download images ---
FAILED=()
for img in $IMAGES; do
  SAFE_NAME=$(echo "$img" | tr '/:@' '_')
  echo "Downloading: $img"
  if skopeo copy --override-arch "$ARCH" \
    "docker://$img" "docker-archive:/tmp/tar-$SAFE_NAME.tar:$img"; then
    sudo mv "/tmp/tar-$SAFE_NAME.tar" "$IMAGES_DIR/"
    echo "  OK: $img"
  else
    echo "::error::Failed to download: $img"
    FAILED+=("$img")
  fi
done

if [ ${#FAILED[@]} -gt 0 ]; then
  sudo umount /mnt/ami
  sudo losetup -d "$LOOP"
  echo "::error::Failed to pre-pull ${#FAILED[@]} image(s): ${FAILED[*]}"
  exit 1
fi

# --- Verify all images present ---
echo ""
echo "=== Verifying pre-pulled images ==="
MISSING=()
for img in $IMAGES; do
  SAFE_NAME=$(echo "$img" | tr '/:@' '_')
  TAR="$IMAGES_DIR/tar-${SAFE_NAME}.tar"
  if [ -f "$TAR" ] && [ -s "$TAR" ]; then
    SIZE=$(stat -c%s "$TAR")
    echo "  OK: $img ($(numfmt --to=iec "$SIZE"))"
  else
    echo "  MISSING: $img"
    MISSING+=("$img")
  fi
done

sudo umount /mnt/ami
sudo losetup -d "$LOOP"

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "::error::${#MISSING[@]} image(s) missing from AMI: ${MISSING[*]}"
  exit 1
fi

echo ""
echo "All $IMAGE_COUNT images verified present in AMI"

# Export the modified VHD path for subsequent steps
echo "PREPULL_VHD=$WORK_VHD" >> "$GITHUB_ENV"
