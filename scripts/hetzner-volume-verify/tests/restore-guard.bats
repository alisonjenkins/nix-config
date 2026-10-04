#!/usr/bin/env bats
# check-restored-pvcs.sh: after a Velero restore into a scratch namespace and before any restored pod
# runs, no restored PVC may point at a volume that belongs to another claim. Found 2026-10-04: a
# partial restore that left out PersistentVolumes kept spec.volumeName, so the scratch PVCs named the
# LIVE Prometheus and Alertmanager volumes, and a restored pod would have written backup data into them.

setup() {
  script="${BATS_TEST_DIRNAME}/../check-restored-pvcs.sh"
  export FIXTURES="${BATS_TEST_TMPDIR}/fixtures"
  mkdir -p "$FIXTURES"
  export PATH="${BATS_TEST_DIRNAME}/bin:${PATH}"
}

pvcs() { # name volumeName ...
  local items="" sep=""
  while [ $# -gt 0 ]; do
    items="$items$sep{\"metadata\":{\"name\":\"$1\",\"namespace\":\"scratch\"},\"spec\":{\"volumeName\":\"$2\"}}"
    sep=","; shift 2
  done
  printf '{"items":[%s]}\n' "$items" > "$FIXTURES/pvcs.json"
}

@test "a restored PVC with no volume yet is fine" {
  pvcs data ""
  run "$script" scratch
  [ "$status" -eq 0 ]
  [[ "$output" == *"data"* ]]
}

@test "a PVC bound to a volume whose claim is that PVC is fine" {
  pvcs data pv-1
  echo "scratch/data" > "$FIXTURES/pv-pv-1.claimref"
  run "$script" scratch
  [ "$status" -eq 0 ]
}

@test "a PVC naming a volume that belongs to another claim fails and names both" {
  pvcs data pv-live
  echo "monitoring/prometheus-db" > "$FIXTURES/pv-pv-live.claimref"
  run "$script" scratch
  [ "$status" -eq 1 ]
  [[ "$output" == *"pv-live"* ]]
  [[ "$output" == *"monitoring/prometheus-db"* ]]
}

@test "a PVC naming a volume that cannot be read fails closed" {
  pvcs data pv-missing
  run "$script" scratch
  [ "$status" -eq 1 ]
  [[ "$output" == *"pv-missing"* ]]
}

@test "one bad PVC among good ones fails the run" {
  pvcs a "" b pv-live c pv-1
  echo "other/live" > "$FIXTURES/pv-pv-live.claimref"
  echo "scratch/c" > "$FIXTURES/pv-pv-1.claimref"
  run "$script" scratch
  [ "$status" -eq 1 ]
  [ "$(grep -c 'FAIL' <<<"$output")" -eq 1 ]
}

@test "an unreadable namespace fails closed" {
  rm -f "$FIXTURES/pvcs.json"
  run "$script" scratch
  [ "$status" -eq 1 ]
  [[ "$output" == *"scratch"* ]]
}

@test "no namespace argument is a usage error" {
  run "$script"
  [ "$status" -eq 2 ]
}
