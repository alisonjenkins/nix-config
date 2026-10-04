#!/usr/bin/env bats
# migrate-files.sh (spec 004 T062): copy one claim to another only while the service is down, and
# refuse on any failure. kubectl is the fixture-driven fake in tests/bin; envsubst is real.

setup() {
  script="${BATS_TEST_DIRNAME}/../migrate-files.sh"
  export FIXTURES="${BATS_TEST_TMPDIR}/fixtures"
  mkdir -p "$FIXTURES"
  export PATH="${BATS_TEST_DIRNAME}/bin:${PATH}"
  export MIGRATE_POLL_INTERVAL=0 MIGRATE_TIMEOUT_SECONDS=5
  : > "$FIXTURES/kubectl.calls"
  manifests="${BATS_TEST_TMPDIR}/manifests"
  echo 0 > "$FIXTURES/replicas-deployment-svc"
  echo '{"items":[]}' > "$FIXTURES/pods.json"
  echo '1/' > "$FIXTURES/job.result"
  {
    echo 'step=rsync ok'
    echo 'MIGRATE-MANIFEST-BEGIN old'
    printf './sub/b\t5\tbbb\n./a\t6\taaa\n'
    echo 'MIGRATE-MANIFEST-END old'
    echo 'MIGRATE-MANIFEST-BEGIN new'
    printf './sub/b\t5\tbbb\n./a\t6\taaa\n'
    echo 'MIGRATE-MANIFEST-END new'
  } > "$FIXTURES/job.logs"
}

# bats does not fail a test on a bare `! cmd`, so assert the count instead.
no_kubectl_call() {
  [ "$(grep -c "$1" "$FIXTURES/kubectl.calls" || true)" -eq 0 ]
}

args() {
  echo --namespace matrix --service svc --old-claim old-claim --new-claim new-claim --manifest-dir "$manifests"
}

@test "refuses when the deployment still has replicas" {
  echo 1 > "$FIXTURES/replicas-deployment-svc"
  run "$script" $(args) --execute
  [ "$status" -eq 1 ]
  [[ "$output" == *"step=scale-check"* ]]
  [[ "$output" == *"replicas=1"* ]]
  no_kubectl_call '^apply'
}

@test "refuses when a pod still mounts the old claim" {
  echo '{"items":[{"metadata":{"name":"svc-0"},"spec":{"volumes":[{"persistentVolumeClaim":{"claimName":"old-claim"}}]}}]}' > "$FIXTURES/pods.json"
  run "$script" $(args) --execute
  [ "$status" -eq 1 ]
  [[ "$output" == *"step=scale-check"* ]]
  [[ "$output" == *"svc-0"* ]]
  no_kubectl_call '^apply'
}

@test "refuses when a pod still mounts the new claim" {
  echo '{"items":[{"metadata":{"name":"other"},"spec":{"volumes":[{"persistentVolumeClaim":{"claimName":"new-claim"}}]}}]}' > "$FIXTURES/pods.json"
  run "$script" $(args) --execute
  [ "$status" -eq 1 ]
  [[ "$output" == *"other"* ]]
  no_kubectl_call '^apply'
}

@test "refuses when the service is neither a deployment nor a statefulset" {
  rm "$FIXTURES/replicas-deployment-svc"
  run "$script" $(args) --execute
  [ "$status" -eq 1 ]
  [[ "$output" == *"step=scale-check"* ]]
  [[ "$output" == *"matrix/svc"* ]]
  no_kubectl_call '^apply'
}

@test "accepts a statefulset scaled to zero" {
  rm "$FIXTURES/replicas-deployment-svc"
  echo 0 > "$FIXTURES/replicas-statefulset-svc"
  run "$script" $(args) --execute
  [ "$status" -eq 0 ]
}

@test "refuses when the copy job already exists" {
  echo '1/' > "$FIXTURES/job.status"
  run "$script" $(args) --execute
  [ "$status" -eq 1 ]
  [[ "$output" == *"step=job-exists"* ]]
  no_kubectl_call '^apply'
}

@test "dry run changes nothing and says so" {
  run "$script" $(args)
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry run"* ]]
  no_kubectl_call '^apply'
  no_kubectl_call '^logs'
  [ ! -e "$manifests/old.manifest" ]
}

@test "dry run still refuses a service that is not scaled to zero" {
  echo 2 > "$FIXTURES/replicas-deployment-svc"
  run "$script" $(args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"step=scale-check"* ]]
}

@test "a failed job is refused with the step and inputs named" {
  echo '/1' > "$FIXTURES/job.result"
  echo 'step=rsync failed status=23' > "$FIXTURES/job.logs"
  run "$script" $(args) --execute
  [ "$status" -eq 1 ]
  [[ "$output" == *"step=copy-job"* ]]
  [[ "$output" == *"old-claim"* ]]
  [[ "$output" == *"new-claim"* ]]
  [[ "$output" == *"step=rsync failed status=23"* ]]
  [ ! -e "$manifests/old.manifest" ]
}

@test "a job that never finishes is refused as a timeout" {
  echo '/' > "$FIXTURES/job.result"
  MIGRATE_TIMEOUT_SECONDS=0 run "$script" $(args) --execute
  [ "$status" -eq 1 ]
  [[ "$output" == *"step=wait-copy-job"* ]]
}

@test "a finished job without manifests in its logs is refused" {
  echo 'step=rsync ok' > "$FIXTURES/job.logs"
  run "$script" $(args) --execute
  [ "$status" -eq 1 ]
  [[ "$output" == *"step=read-manifest"* ]]
}

@test "happy path applies the job and writes both manifests sorted by path" {
  run "$script" $(args) --execute
  [ "$status" -eq 0 ]
  [ "$(printf './a\t6\taaa\n./sub/b\t5\tbbb\n')" = "$(cat "$manifests/old.manifest")" ]
  [ "$(printf './a\t6\taaa\n./sub/b\t5\tbbb\n')" = "$(cat "$manifests/new.manifest")" ]
}

@test "the rendered job mounts old read-only, new writable, rsyncs, and sets limits" {
  run "$script" $(args) --execute
  [ "$status" -eq 0 ]
  grep -q 'claimName: old-claim' "$FIXTURES/applied.yaml"
  grep -q 'claimName: new-claim' "$FIXTURES/applied.yaml"
  grep -q 'rsync -a --checksum /old/ /new/' "$FIXTURES/applied.yaml"
  grep -q 'limits:' "$FIXTURES/applied.yaml"
  grep -q 'readOnly: true' "$FIXTURES/applied.yaml"
  grep -q 'namespace: matrix' "$FIXTURES/applied.yaml"
  # envsubst must not eat the shell variables inside the job script
  grep -q 'sha256sum' "$FIXTURES/applied.yaml"
  [ "$(grep -c '\${NAMESPACE}' "$FIXTURES/applied.yaml" || true)" -eq 0 ]
}

@test "a missing option is a usage error" {
  run "$script" --namespace matrix --service svc --old-claim old-claim --manifest-dir "$manifests"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--new-claim"* ]]
}

@test "an unknown option is a usage error" {
  run "$script" --bogus x
  [ "$status" -eq 2 ]
}
