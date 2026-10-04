#!/usr/bin/env bash
# Run after a Velero restore into a scratch namespace and BEFORE any restored pod runs.
# Every PVC there must have no volume yet, or a volume whose claim is that same PVC.
# A PVC that names a volume belonging to another claim (for example a live one, as happens when
# PersistentVolumes are left out of a partial restore) would let a restored pod write backup data
# into that volume. Exit 0 if all are safe, 1 if any is not or if it cannot tell, 2 on usage.
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: check-restored-pvcs.sh NAMESPACE" >&2
  exit 2
fi
ns=$1

if ! pvcs=$(kubectl get pvc -n "$ns" -o json 2>&1); then
  echo "FAIL cannot list PVCs in namespace $ns: ${pvcs:0:200}" >&2
  exit 1
fi

count=$(jq '.items | length' <<<"$pvcs")
if [ "$count" -eq 0 ]; then
  echo "ok   no PVCs in $ns"
  exit 0
fi

failed=0
while IFS=$'\t' read -r name vol; do
  if [ -z "$vol" ]; then
    echo "ok   $ns/$name has no volume yet"
    continue
  fi
  if ! ref=$(kubectl get pv "$vol" -o jsonpath='{.spec.claimRef.namespace}/{.spec.claimRef.name}' 2>&1); then
    echo "FAIL $ns/$name names volume $vol, which cannot be read: ${ref:0:120}"
    failed=1
  elif [ "$ref" = "$ns/$name" ]; then
    echo "ok   $ns/$name is bound to its own volume $vol"
  else
    echo "FAIL $ns/$name names volume $vol, which belongs to claim $ref"
    failed=1
  fi
done < <(jq -r '.items[] | [.metadata.name, (.spec.volumeName // "")] | @tsv' <<<"$pvcs")

exit "$failed"
