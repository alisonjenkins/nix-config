#!/usr/bin/env bats
# retain-pv.sh and destroy-old-volume.sh (spec FR-007): nothing is deleted
# unless verification passed, a fresh backup exists and the PV is Retain.

setup() {
  dir="${BATS_TEST_DIRNAME}/.."
  export FIXTURES="${BATS_TEST_TMPDIR}/fixtures"
  mkdir -p "$FIXTURES"
  export PATH="${BATS_TEST_DIRNAME}/bin:${PATH}"
  : > "$FIXTURES/kubectl.calls"
  verdict="${BATS_TEST_TMPDIR}/verdict.txt"
  echo '2026-10-03T14:09:55Z volume=vol1 verdict=verified' > "$verdict"
  echo '{"items":[{"metadata":{"name":"b1"},"spec":{"includedNamespaces":["matrix"]},"status":{"phase":"Completed","completionTimestamp":"2026-10-03T14:05:00Z"}}]}' > "$FIXTURES/backups.json"
  echo Retain > "$FIXTURES/pv-pvc-old.policy"
  echo '{"items":[]}' > "$FIXTURES/pods.json"
}

# bats does not fail a test on a bare `! cmd`, so assert the count instead.
no_kubectl_call() {
  [ "$(grep -c "$1" "$FIXTURES/kubectl.calls" || true)" -eq 0 ]
}

destroy_args() {
  echo --volume vol1 --pv pvc-old --claim matrix/old-claim --hcloud-volume 12345 \
    --verdict-file "$verdict" --backup velero --backup-namespace velero --backup-for matrix --since 2026-10-03T14:00:00Z
}

# --- retain-pv.sh ---

@test "retain-pv patches the reclaim policy to Retain" {
  echo Delete > "$FIXTURES/pv-pvc-old.policy"
  run "$dir/retain-pv.sh" pvc-old
  [ "$status" -eq 0 ]
  grep -q 'patch pv pvc-old' "$FIXTURES/kubectl.calls"
  grep -q 'Retain' "$FIXTURES/kubectl.calls"
}

@test "retain-pv refuses an unknown PV and patches nothing" {
  run "$dir/retain-pv.sh" pvc-missing
  [ "$status" -eq 1 ]
  [[ "$output" == *"pvc-missing"* ]]
  no_kubectl_call patch
}

@test "retain-pv without an argument is a usage error" {
  run "$dir/retain-pv.sh"
  [ "$status" -eq 2 ]
}

# --- destroy-old-volume.sh ---

@test "destroy refuses when the verdict file says failed" {
  echo '2026-10-03T14:09:55Z volume=vol1 verdict=failed' > "$verdict"
  run "$dir/destroy-old-volume.sh" $(destroy_args) --execute
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict"* ]]
  no_kubectl_call delete
  [ ! -e "$FIXTURES/hcloud.calls" ]
}

@test "destroy refuses when the verdict is for another volume" {
  echo '2026-10-03T14:09:55Z volume=other verdict=verified' > "$verdict"
  run "$dir/destroy-old-volume.sh" $(destroy_args) --execute
  [ "$status" -eq 1 ]
  no_kubectl_call delete
}

@test "destroy refuses when the verdict file is missing" {
  rm "$verdict"
  run "$dir/destroy-old-volume.sh" $(destroy_args) --execute
  [ "$status" -eq 1 ]
  [[ "$output" == *"$verdict"* ]]
}

@test "destroy refuses when no completed backup is listed" {
  echo '{"items":[]}' > "$FIXTURES/backups.json"
  run "$dir/destroy-old-volume.sh" $(destroy_args) --execute
  [ "$status" -eq 1 ]
  [[ "$output" == *"backup"* ]]
  no_kubectl_call delete
}

@test "destroy refuses when the PV is not Retain" {
  echo Delete > "$FIXTURES/pv-pvc-old.policy"
  run "$dir/destroy-old-volume.sh" $(destroy_args) --execute
  [ "$status" -eq 1 ]
  [[ "$output" == *"Retain"* ]]
  no_kubectl_call delete
}

@test "destroy without --execute only prints what it would do" {
  run "$dir/destroy-old-volume.sh" $(destroy_args)
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry run"* ]]
  no_kubectl_call delete
  [ ! -e "$FIXTURES/hcloud.calls" ]
}

@test "destroy --execute deletes the claim, the PV and the Hetzner volume in that order" {
  run "$dir/destroy-old-volume.sh" $(destroy_args) --execute
  [ "$status" -eq 0 ]
  grep -q 'delete pvc old-claim -n matrix' "$FIXTURES/kubectl.calls"
  grep -q 'delete pv pvc-old' "$FIXTURES/kubectl.calls"
  grep -q 'volume delete 12345' "$FIXTURES/hcloud.calls"
  claim=$(grep -n 'delete pvc' "$FIXTURES/kubectl.calls" | cut -d: -f1)
  pv=$(grep -n 'delete pv ' "$FIXTURES/kubectl.calls" | cut -d: -f1)
  [ "$claim" -lt "$pv" ]
}

# --- found in review: stale verdicts, regex names, stale backups, claims in use ---

@test "destroy uses the last verdict line for the volume, not an earlier verified one" {
  printf '%s\n%s\n' \
    '2026-10-03T14:09:55Z volume=vol1 verdict=verified' \
    '2026-10-03T15:30:00Z volume=vol1 verdict=failed' > "$verdict"
  run "$dir/destroy-old-volume.sh" $(destroy_args) --execute
  [ "$status" -eq 1 ]
  no_kubectl_call delete
}

@test "destroy matches the volume name literally, not as a regular expression" {
  echo '2026-10-03T14:09:55Z volume=volX1 verdict=verified' > "$verdict"
  run "$dir/destroy-old-volume.sh" --volume vol.1 --pv pvc-old --claim matrix/old-claim --hcloud-volume 12345 \
    --verdict-file "$verdict" --backup velero --backup-namespace velero --backup-for matrix --since 2026-10-03T14:00:00Z --execute
  [ "$status" -eq 1 ]
  no_kubectl_call delete
}

@test "destroy requires --since so an old backup cannot count as fresh" {
  run "$dir/destroy-old-volume.sh" --volume vol1 --pv pvc-old --claim matrix/old-claim --hcloud-volume 12345 \
    --verdict-file "$verdict" --backup velero --backup-namespace velero --backup-for matrix --execute
  [ "$status" -eq 2 ]
  [[ "$output" == *"--since"* ]]
}

@test "destroy refuses when the only completed backup is older than --since" {
  echo '2026-10-03T17:00:00Z volume=vol1 verdict=verified' > "$verdict"
  run "$dir/destroy-old-volume.sh" $(destroy_args | sed 's/--since [^ ]*/--since 2026-10-03T16:00:00Z/') --execute
  [ "$status" -eq 1 ]
  [[ "$output" == *"since"* ]]
  no_kubectl_call delete
}

@test "destroy refuses while a pod still mounts the claim" {
  echo '{"items":[{"metadata":{"name":"synapse-0"},"spec":{"volumes":[{"persistentVolumeClaim":{"claimName":"old-claim"}}]}}]}' > "$FIXTURES/pods.json"
  run "$dir/destroy-old-volume.sh" $(destroy_args) --execute
  [ "$status" -eq 1 ]
  [[ "$output" == *"synapse-0"* ]]
  no_kubectl_call delete
}

@test "destroy refuses when the only completed backup is of another namespace" {
  echo '{"items":[{"metadata":{"name":"b1"},"spec":{"includedNamespaces":["couchdb"]},"status":{"phase":"Completed","completionTimestamp":"2026-10-03T14:05:00Z"}}]}' > "$FIXTURES/backups.json"
  run "$dir/destroy-old-volume.sh" $(destroy_args) --execute
  [ "$status" -eq 1 ]
  [[ "$output" == *"matrix"* ]]
  no_kubectl_call delete
}

@test "destroy requires --backup-for" {
  run "$dir/destroy-old-volume.sh" --volume vol1 --pv pvc-old --claim matrix/old-claim --hcloud-volume 12345 \
    --verdict-file "$verdict" --backup velero --backup-namespace velero --since 2026-10-03T14:00:00Z --execute
  [ "$status" -eq 2 ]
  [[ "$output" == *"--backup-for"* ]]
}

@test "destroy refuses a verified verdict that is older than --since" {
  echo '{"items":[{"metadata":{"name":"b1"},"spec":{"includedNamespaces":["matrix"]},"status":{"phase":"Completed","completionTimestamp":"2026-10-03T16:30:00Z"}}]}' > "$FIXTURES/backups.json"
  run "$dir/destroy-old-volume.sh" $(destroy_args | sed 's/--since [^ ]*/--since 2026-10-03T16:00:00Z/') --execute
  [ "$status" -eq 1 ]
  [[ "$output" == *"older than"* ]]
  no_kubectl_call delete
}

@test "destroy --execute tolerates a claim the operator already removed" {
  run "$dir/destroy-old-volume.sh" $(destroy_args) --execute
  [ "$status" -eq 0 ]
  grep -q 'delete pvc old-claim -n matrix --ignore-not-found' "$FIXTURES/kubectl.calls"
}
