#!/usr/bin/env bash
# Set a PersistentVolume's reclaim policy to Retain so deleting its claim cannot
# delete the volume behind it (spec FR-007). Safe to re-run.
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: retain-pv.sh PV_NAME" >&2
  exit 2
fi
pv=$1

policy=$(kubectl get pv "$pv" -o jsonpath='{.spec.persistentVolumeReclaimPolicy}' 2>&1) || {
  echo "retain-pv: cannot read pv $pv: $policy" >&2
  exit 1
}

if [ "$policy" = Retain ]; then
  echo "pv=$pv reclaimPolicy=Retain (unchanged)"
  exit 0
fi

kubectl patch pv "$pv" -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}' >/dev/null || {
  echo "retain-pv: patching pv $pv from $policy to Retain failed" >&2
  exit 1
}

policy=$(kubectl get pv "$pv" -o jsonpath='{.spec.persistentVolumeReclaimPolicy}')
if [ "$policy" != Retain ]; then
  echo "retain-pv: pv $pv still has reclaimPolicy=$policy after the patch" >&2
  exit 1
fi
echo "pv=$pv reclaimPolicy=$policy"
