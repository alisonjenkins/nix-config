#!/usr/bin/env bats
# One group of tests per part of specs/004-hetzner-encrypted-volumes/contracts/verification.md.
# kubectl, lsblk, cryptsetup and curl are fixture-driven fakes in tests/bin.

setup() {
  script="${BATS_TEST_DIRNAME}/../verify.sh"
  export FIXTURES="${BATS_TEST_TMPDIR}/fixtures"
  mkdir -p "$FIXTURES" "${BATS_TEST_TMPDIR}/old" "${BATS_TEST_TMPDIR}/new"
  export PATH="${BATS_TEST_DIRNAME}/bin:${PATH}"
  export VERIFY_HEALTH_INTERVAL=0
  device="${BATS_TEST_TMPDIR}/device.img"
  head -c 4096 /dev/urandom > "$device"
  printf 'crypto_LUKS\n' > "$FIXTURES/fstype.txt"
  printf 'c2VjcmV0\n' > "$FIXTURES/secret.b64"
}

enc_args() {
  echo --volume vol1 --checks encryption --device "$device" --mapping pvc-1 --secret kube-system/hcloud-volume-passphrase
}

# --- output contract ---

@test "passing run prints one line per check and verdict=verified" {
  run "$script" $(enc_args)
  [ "$status" -eq 0 ]
  [[ "$output" =~ [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z\ volume=vol1\ check=encryption\ result=pass ]]
  [[ "$output" == *"volume=vol1 verdict=verified"* ]]
}

@test "failing run ends with verdict=failed, names the check and exits non-zero" {
  printf 'ext4\n' > "$FIXTURES/fstype.txt"
  run "$script" $(enc_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"check=encryption result=fail"* ]]
  [[ "$output" == *"volume=vol1 verdict=failed"* ]]
}

@test "missing --volume is a usage error" {
  run "$script" --checks encryption
  [ "$status" -eq 2 ]
  [[ "$output" == *"--volume"* ]]
}

# --- part 0: encryption is real ---

@test "encryption fails for a plain filesystem" {
  printf 'ext4\n' > "$FIXTURES/fstype.txt"
  run "$script" $(enc_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"ext4"* ]]
}

@test "encryption fails when the mapping is not active" {
  touch "$FIXTURES/mapping-inactive"
  run "$script" $(enc_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"pvc-1"* ]]
}

@test "encryption fails when the passphrase Secret is missing" {
  rm "$FIXTURES/secret.b64"
  run "$script" $(enc_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"kube-system/hcloud-volume-passphrase"* ]]
}

@test "encryption fails when the passphrase Secret is empty" {
  : > "$FIXTURES/secret.b64"
  run "$script" $(enc_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"empty"* ]]
}

@test "encryption fails when the raw device carries an ext4 superblock magic" {
  head -c 1080 /dev/zero > "$device"
  printf '\x53\xef' >> "$device"
  head -c 3000 /dev/zero >> "$device"
  run "$script" $(enc_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"magic"* ]]
}

# --- part 1: data comparison ---

files_args() {
  echo --volume vol1 --checks compare --kind files --old-dir "${BATS_TEST_TMPDIR}/old" --new-dir "${BATS_TEST_TMPDIR}/new"
}

@test "files compare passes on identical trees" {
  for d in old new; do mkdir -p "${BATS_TEST_TMPDIR}/$d/sub"; echo hello > "${BATS_TEST_TMPDIR}/$d/a"; echo deep > "${BATS_TEST_TMPDIR}/$d/sub/b"; done
  run "$script" $(files_args)
  [ "$status" -eq 0 ]
  [[ "$output" == *"files=2"* ]]
}

@test "files compare fails when one file's content differs" {
  echo hello > "${BATS_TEST_TMPDIR}/old/a"; echo hellp > "${BATS_TEST_TMPDIR}/new/a"
  run "$script" $(files_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"a"* ]]
}

@test "files compare fails when a file is missing from the new tree" {
  echo x > "${BATS_TEST_TMPDIR}/old/a"; echo y > "${BATS_TEST_TMPDIR}/old/b"; echo x > "${BATS_TEST_TMPDIR}/new/a"
  run "$script" $(files_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"b"* ]]
}

db_args() {
  echo --volume db1 --checks compare --kind database --namespace matrix --old-pod shared-postgres-1 --new-pod shared-postgres-2 --db synapse
}

@test "database compare passes on identical row counts and checksums" {
  printf 'users|10|abc\nrooms|4|def\n' > "$FIXTURES/psql-shared-postgres-1.txt"
  cp "$FIXTURES/psql-shared-postgres-1.txt" "$FIXTURES/psql-shared-postgres-2.txt"
  run "$script" $(db_args)
  [ "$status" -eq 0 ]
  [[ "$output" == *"tables=2"* ]]
}

@test "database compare fails on one differing checksum and names the table" {
  printf 'users|10|abc\nrooms|4|def\n' > "$FIXTURES/psql-shared-postgres-1.txt"
  printf 'users|10|abc\nrooms|4|xyz\n' > "$FIXTURES/psql-shared-postgres-2.txt"
  run "$script" $(db_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"rooms"* ]]
}

@test "database compare fails on a differing row count" {
  printf 'users|10|abc\n' > "$FIXTURES/psql-shared-postgres-1.txt"
  printf 'users|9|abc\n'  > "$FIXTURES/psql-shared-postgres-2.txt"
  run "$script" $(db_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"users"* ]]
}

# --- part 2: service health ---

health_args() {
  echo --volume vol1 --checks health --namespace matrix --selector app=synapse --health-url http://synapse.test/health --health-seconds 2
}

ready_pod_json() {
  printf '{"items":[{"metadata":{"name":"p1"},"status":{"containerStatuses":[{"ready":true,"restartCount":%s}]}}]}\n' "$1"
}

@test "health passes for a ready pod with no restarts and a healthy endpoint" {
  ready_pod_json 0 > "$FIXTURES/pods.json"
  run "$script" $(health_args)
  [ "$status" -eq 0 ]
}

@test "health fails when a pod has restarted since the switch" {
  ready_pod_json 1 > "$FIXTURES/pods.json"
  run "$script" $(health_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"restart"* ]]
}

@test "health fails when the endpoint stops answering" {
  ready_pod_json 0 > "$FIXTURES/pods.json"
  echo 22 > "$FIXTURES/curl.rc"
  run "$script" $(health_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"http://synapse.test/health"* ]]
}

@test "health fails when the logs show a volume error" {
  ready_pod_json 0 > "$FIXTURES/pods.json"
  echo "ERROR permission denied opening /data/media" > "$FIXTURES/logs.txt"
  run "$script" $(health_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"logs"* ]]
}

# --- part 3: functional ---

@test "matrix functional fails clearly when the verify-bot credentials are not exported" {
  unset VERIFY_BOT_PASSWORD
  run "$script" --volume vol1 --checks functional --service matrix --homeserver https://matrix.test
  [ "$status" -eq 1 ]
  [[ "$output" == *"VERIFY_BOT_PASSWORD"* ]]
}

@test "photos functional fails clearly when the test account credentials are not exported" {
  unset VERIFY_PHOTOS_PASSWORD
  run "$script" --volume vol1 --checks functional --service photos --photos-url https://photos.test
  [ "$status" -eq 1 ]
  [[ "$output" == *"VERIFY_PHOTOS_PASSWORD"* ]]
}

@test "matrix functional fails when the homeserver stops answering" {
  export VERIFY_BOT_PASSWORD=pw
  echo 22 > "$FIXTURES/curl.rc"
  run "$script" --volume vol1 --checks functional --service matrix --homeserver https://matrix.test
  [ "$status" -eq 1 ]
  [[ "$output" == *"https://matrix.test"* ]]
}

@test "monitoring functional fails when Prometheus does not answer" {
  echo 22 > "$FIXTURES/curl.rc"
  run "$script" --volume vol1 --checks functional --service monitoring --prometheus-url http://prom.test
  [ "$status" -eq 1 ]
  [[ "$output" == *"http://prom.test"* ]]
}

@test "monitoring functional passes when Prometheus answers a query" {
  echo '{"status":"success","data":{"result":[{"value":[0,"1"]}]}}' > "$FIXTURES/curl.out"
  run "$script" --volume vol1 --checks functional --service monitoring --prometheus-url http://prom.test
  [ "$status" -eq 0 ]
}

@test "an unknown service is a usage error" {
  run "$script" --volume vol1 --checks functional --service nonsense
  [ "$status" -eq 2 ]
  [[ "$output" == *"nonsense"* ]]
}

# --- part 4: fresh backup ---

@test "backup fails when no completed Velero backup is listed" {
  echo '{"items":[{"metadata":{"name":"b1"},"status":{"phase":"InProgress"}}]}' > "$FIXTURES/backups.json"
  run "$script" --volume vol1 --checks backup --backup velero --backup-namespace velero
  [ "$status" -eq 1 ]
  [[ "$output" == *"no completed"* ]]
}

@test "backup passes with a completed Velero backup" {
  echo '{"items":[{"metadata":{"name":"b1"},"status":{"phase":"Completed"}}]}' > "$FIXTURES/backups.json"
  run "$script" --volume vol1 --checks backup --backup velero --backup-namespace velero
  [ "$status" -eq 0 ]
}

@test "backup fails when no completed CNPG backup is listed" {
  echo '{"items":[]}' > "$FIXTURES/backups.json"
  run "$script" --volume vol1 --checks backup --backup cnpg --backup-namespace matrix
  [ "$status" -eq 1 ]
}

@test "backup passes with a completed CNPG backup" {
  echo '{"items":[{"metadata":{"name":"b1"},"status":{"phase":"completed"}}]}' > "$FIXTURES/backups.json"
  run "$script" --volume vol1 --checks backup --backup cnpg --backup-namespace matrix
  [ "$status" -eq 0 ]
}
