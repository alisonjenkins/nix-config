#!/usr/bin/env bash
# Remove an old plain volume once its migration is proven (spec FR-007, FR-008).
# Refuses unless: the verification verdict for this volume is verified, a completed
# backup is listed, and the PV is Retain. Dry run unless --execute is given.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() {
  cat >&2 <<'EOF'
usage: destroy-old-volume.sh --volume NAME --pv PV --claim NAMESPACE/NAME --hcloud-volume ID
         --verdict-file FILE --backup velero|cnpg --backup-namespace NS [--since ISO8601] [--execute]
EOF
  exit 2
}

volume="" pv="" claim="" hcloud_id="" verdict_file="" backup="" backup_ns="" since="" execute=0
while [ $# -gt 0 ]; do
  case "$1" in
    --execute) execute=1; shift; continue ;;
    --volume | --pv | --claim | --hcloud-volume | --verdict-file | --backup | --backup-namespace | --since) ;;
    *) echo "destroy-old-volume: unknown option $1" >&2; usage ;;
  esac
  [ $# -ge 2 ] || usage
  case "$1" in
    --volume) volume=$2 ;;
    --pv) pv=$2 ;;
    --claim) claim=$2 ;;
    --hcloud-volume) hcloud_id=$2 ;;
    --verdict-file) verdict_file=$2 ;;
    --backup) backup=$2 ;;
    --backup-namespace) backup_ns=$2 ;;
    --since) since=$2 ;;
  esac
  shift 2
done
for v in volume pv claim hcloud_id verdict_file backup backup_ns; do
  [ -n "${!v}" ] || { echo "destroy-old-volume: --${v//_/-} is required" >&2; usage; }
done

refuse() {
  echo "destroy-old-volume: refusing for volume=$volume: $1" >&2
  exit 1
}

[ -r "$verdict_file" ] || refuse "cannot read verdict file $verdict_file"
grep -q " volume=$volume verdict=verified\$" "$verdict_file" \
  || refuse "no 'volume=$volume verdict=verified' line in $verdict_file"

since_args=()
[ -z "$since" ] || since_args=(--since "$since")
"$here/verify.sh" --volume "$volume" --checks backup --backup "$backup" --backup-namespace "$backup_ns" "${since_args[@]}" >/dev/null \
  || refuse "no completed $backup backup in $backup_ns${since:+ since $since}"

policy=$(kubectl get pv "$pv" -o jsonpath='{.spec.persistentVolumeReclaimPolicy}' 2>/dev/null) \
  || refuse "cannot read pv $pv"
[ "$policy" = Retain ] || refuse "pv $pv has reclaimPolicy=$policy, want Retain (run retain-pv.sh first)"

claim_ns=${claim%%/*}
claim_name=${claim#*/}

if [ "$execute" -ne 1 ]; then
  echo "dry run: would delete pvc $claim_name in $claim_ns, pv $pv, then hcloud volume $hcloud_id (add --execute)"
  exit 0
fi

kubectl delete pvc "$claim_name" -n "$claim_ns" || refuse "deleting pvc $claim failed"
kubectl delete pv "$pv" || refuse "deleting pv $pv failed"
hcloud volume delete "$hcloud_id" || refuse "deleting hcloud volume $hcloud_id failed (claim and pv are already gone)"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) volume=$volume destroyed pvc=$claim pv=$pv hcloud_volume=$hcloud_id"
