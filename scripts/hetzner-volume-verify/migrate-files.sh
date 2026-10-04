#!/usr/bin/env bash
# Copy a files volume onto its encrypted replacement (spec 004 T062).
# Refuses unless the service is scaled to zero and no pod mounts either claim. Runs copy-job.yaml
# (rsync -a --checksum old -> new), waits for it, and saves a path, size and sha256 manifest of
# each claim for verify.sh --old-manifest/--new-manifest. Dry run unless --execute is given.
# The finished Job is left in place as a record and so a re-run refuses; delete it to run again.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() {
  cat >&2 <<'EOF'
usage: migrate-files.sh --namespace NS --service NAME --old-claim PVC --new-claim PVC
         --manifest-dir DIR [--execute]
  --service is the Deployment or StatefulSet that uses the claims; it must be scaled to zero.
  Writes DIR/old.manifest and DIR/new.manifest (tab separated path, bytes, sha256, sorted by path).
  Environment: COPY_IMAGE (job image, needs rsync and sha256sum), MIGRATE_TIMEOUT_SECONDS,
  MIGRATE_POLL_INTERVAL.
EOF
  exit 2
}

namespace="" service="" old_claim="" new_claim="" manifest_dir="" execute=0
while [ $# -gt 0 ]; do
  case "$1" in
    --execute) execute=1; shift; continue ;;
    --namespace | --service | --old-claim | --new-claim | --manifest-dir) ;;
    *) echo "migrate-files: unknown option $1" >&2; usage ;;
  esac
  [ $# -ge 2 ] || usage
  case "$1" in
    --namespace) namespace=$2 ;;
    --service) service=$2 ;;
    --old-claim) old_claim=$2 ;;
    --new-claim) new_claim=$2 ;;
    --manifest-dir) manifest_dir=$2 ;;
  esac
  shift 2
done
for req in namespace:--namespace service:--service old_claim:--old-claim new_claim:--new-claim \
  manifest_dir:--manifest-dir; do
  name=${req%%:*}
  [ -n "${!name}" ] || { echo "migrate-files: ${req##*:} is required" >&2; usage; }
done

# Pinned because the cluster's policy rejects floating tags; see the header of copy-job.yaml.
image=${COPY_IMAGE:-docker.io/instrumentisto/rsync-ssh:alpine3.20-r0}
timeout_seconds=${MIGRATE_TIMEOUT_SECONDS:-3600}
poll_interval=${MIGRATE_POLL_INTERVAL:-10}
job_name=$(printf 'migrate-files-%s' "$service" | cut -c1-63)

refuse() {
  echo "migrate-files: refusing step=$1 namespace=$namespace service=$service old-claim=$old_claim new-claim=$new_claim: $2" >&2
  exit 1
}

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

# Step scale-check: the service is at zero replicas and nothing mounts either claim.
replicas=$(kubectl get deployment "$service" -n "$namespace" -o jsonpath='{.spec.replicas}' 2>/dev/null) \
  || replicas=$(kubectl get statefulset "$service" -n "$namespace" -o jsonpath='{.spec.replicas}' 2>/dev/null) \
  || refuse scale-check "no deployment or statefulset $namespace/$service"
[ "$replicas" = 0 ] || refuse scale-check "$namespace/$service has replicas=${replicas:-unset}, want 0 (scale it down first)"

users=$(kubectl get pods -n "$namespace" -o json 2>/dev/null \
  | jq -r --arg o "$old_claim" --arg n "$new_claim" '.items[]
      | select(any(.spec.volumes[]?; .persistentVolumeClaim.claimName == $o or .persistentVolumeClaim.claimName == $n))
      | .metadata.name' | paste -sd, -) \
  || refuse scale-check "cannot list pods in $namespace to check who mounts the claims"
[ -z "$users" ] || refuse scale-check "pod(s) still mount a claim: $users"

# Step job-exists: one copy job per service, never overwritten.
if kubectl get job "$job_name" -n "$namespace" -o jsonpath='{.status.succeeded}/{.status.failed}' >/dev/null 2>&1; then
  refuse job-exists "job $job_name already exists in $namespace (delete it to copy again)"
fi

if [ "$execute" -ne 1 ]; then
  echo "dry run: would run job $job_name in $namespace copying claim $old_claim to $new_claim (rsync -a --checksum) and save manifests in $manifest_dir (add --execute)"
  exit 0
fi

# Step run-copy-job.
# shellcheck disable=SC2016 # the variable names are for envsubst, not the shell
env NAMESPACE="$namespace" JOB_NAME="$job_name" OLD_CLAIM="$old_claim" NEW_CLAIM="$new_claim" IMAGE="$image" \
  envsubst '$NAMESPACE $JOB_NAME $OLD_CLAIM $NEW_CLAIM $IMAGE' <"$here/copy-job.yaml" \
  | kubectl apply -f - >&2 \
  || refuse run-copy-job "rendering or applying job $job_name failed"

# Step wait-copy-job: poll until the Job reports success or failure.
deadline=$((SECONDS + timeout_seconds))
while :; do
  status=$(kubectl get job "$job_name" -n "$namespace" -o jsonpath='{.status.succeeded}/{.status.failed}' 2>/dev/null) \
    || refuse wait-copy-job "cannot read job $job_name"
  case "$status" in
    1/*) break ;;
    */[1-9]*)
      tail_lines=$(kubectl logs "job/$job_name" -n "$namespace" --tail=20 2>&1 | tr '\n' '|') || tail_lines="(no logs)"
      refuse copy-job "job $job_name failed; last log lines: $tail_lines" ;;
  esac
  [ "$SECONDS" -lt "$deadline" ] || refuse wait-copy-job "job $job_name not finished after ${timeout_seconds}s"
  sleep "$poll_interval"
done

# Step read-manifest: pull both manifests out of the job log.
kubectl logs "job/$job_name" -n "$namespace" >"$workdir/job.log" 2>/dev/null \
  || refuse read-manifest "cannot read logs of job $job_name"
for claim in old new; do
  if ! grep -qx "MIGRATE-MANIFEST-BEGIN $claim" "$workdir/job.log" || ! grep -qx "MIGRATE-MANIFEST-END $claim" "$workdir/job.log"; then
    refuse read-manifest "no $claim manifest between its markers in the logs of job $job_name"
  fi
  awk -v want="$claim" '
    $0 == "MIGRATE-MANIFEST-BEGIN " want { on = 1; next }
    $0 == "MIGRATE-MANIFEST-END " want { on = 0; next }
    on' "$workdir/job.log" | LC_ALL=C sort -t "$(printf '\t')" -k1,1 >"$workdir/$claim.manifest"
done
mkdir -p "$manifest_dir"
mv "$workdir/old.manifest" "$manifest_dir/old.manifest"
mv "$workdir/new.manifest" "$manifest_dir/new.manifest"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) copied claim=$old_claim to claim=$new_claim namespace=$namespace service=$service manifests=$manifest_dir files=$(wc -l <"$manifest_dir/old.manifest" | tr -d ' ')"
