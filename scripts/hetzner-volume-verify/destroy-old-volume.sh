#!/usr/bin/env bash
# Remove an old plain volume once its migration is proven (spec FR-007, FR-008).
# Refuses unless: the verification verdict for this volume is verified, a completed
# backup is listed, and the PV is Retain. Dry run unless --execute is given.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() {
  cat >&2 <<'EOF'
usage: destroy-old-volume.sh --volume NAME --pv PV --claim NAMESPACE/NAME --hcloud-volume ID
         --verdict-file FILE --backup velero|cnpg --backup-namespace NS --backup-for TARGET
         --since ISO8601 [--execute]
  --since is the time of the switch: a backup or a verdict from before it does not count.
  --backup-for is the workload namespace for velero, or the cluster name for cnpg.
EOF
  exit 2
}

volume="" pv="" claim="" hcloud_id="" verdict_file="" backup="" backup_ns="" backup_for="" since="" execute=0
while [ $# -gt 0 ]; do
  case "$1" in
    --execute) execute=1; shift; continue ;;
    --volume | --pv | --claim | --hcloud-volume | --verdict-file | --backup | --backup-namespace | --backup-for | --since) ;;
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
    --backup-for) backup_for=$2 ;;
    --since) since=$2 ;;
  esac
  shift 2
done
for req in volume:--volume pv:--pv claim:--claim hcloud_id:--hcloud-volume verdict_file:--verdict-file \
  backup:--backup backup_ns:--backup-namespace backup_for:--backup-for since:--since; do
  name=${req%%:*}
  [ -n "${!name}" ] || { echo "destroy-old-volume: ${req##*:} is required" >&2; usage; }
done

refuse() {
  echo "destroy-old-volume: refusing for volume=$volume: $1" >&2
  exit 1
}

[ -r "$verdict_file" ] || refuse "cannot read verdict file $verdict_file"
last=$(awk -v want="volume=$volume" '
  { hit = 0; v = ""
    for (i = 1; i <= NF; i++) { if ($i == want) hit = 1; if ($i ~ /^verdict=/) v = $i }
    if (hit && v != "") last = $1 " " v }
  END { print last }' "$verdict_file")
last_ts=${last%% *}
last_verdict=${last#* }
[ "$last_verdict" = verdict=verified ] \
  || refuse "the last verdict for volume=$volume in $verdict_file is '${last_verdict:-none}', want verdict=verified"
[[ "$last_ts" > "$since" || "$last_ts" == "$since" ]] \
  || refuse "the verified verdict at $last_ts is older than --since $since, verify again after the switch"

"$here/verify.sh" --volume "$volume" --checks backup --backup "$backup" --backup-namespace "$backup_ns" \
  --backup-for "$backup_for" --since "$since" >/dev/null \
  || refuse "no completed $backup backup for $backup_for in $backup_ns since $since"

policy=$(kubectl get pv "$pv" -o jsonpath='{.spec.persistentVolumeReclaimPolicy}' 2>/dev/null) \
  || refuse "cannot read pv $pv"
[ "$policy" = Retain ] || refuse "pv $pv has reclaimPolicy=$policy, want Retain (run retain-pv.sh first)"

claim_ns=${claim%%/*}
claim_name=${claim#*/}

users=$(kubectl get pods -n "$claim_ns" -o json 2>/dev/null \
  | jq -r --arg c "$claim_name" '.items[] | select(any(.spec.volumes[]?; .persistentVolumeClaim.claimName == $c)) | .metadata.name' \
  | paste -sd, -) || refuse "cannot list pods in $claim_ns to check who mounts $claim_name"
[ -z "$users" ] || refuse "pod(s) still mount claim $claim: $users"

if [ "$execute" -ne 1 ]; then
  echo "dry run: would delete pvc $claim_name in $claim_ns, pv $pv, then hcloud volume $hcloud_id (add --execute)"
  exit 0
fi

kubectl delete pvc "$claim_name" -n "$claim_ns" --ignore-not-found || refuse "deleting pvc $claim failed"
kubectl delete pv "$pv" || refuse "deleting pv $pv failed"
hcloud volume delete "$hcloud_id" || refuse "deleting hcloud volume $hcloud_id failed (claim and pv are already gone)"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) volume=$volume destroyed pvc=$claim pv=$pv hcloud_volume=$hcloud_id"
