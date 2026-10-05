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
  printf 'kube-system/hcloud-volume-passphrase\n' > "$FIXTURES/sc.ref"
  printf 'hcloud-volumes-encrypted\n' > "$FIXTURES/pv-pvc-1.class"
}

enc_args() {
  echo --volume vol1 --checks encryption --device "$device" --mapping pvc-1 --pv pvc-1 \
    --secret kube-system/hcloud-volume-passphrase --storageclass hcloud-volumes-encrypted
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

@test "missing --checks is a usage error that names the option" {
  run "$script" --volume vol1
  [ "$status" -eq 2 ]
  [[ "$output" == *"--checks"* ]]
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

@test "encryption runs lsblk, cryptsetup and the raw read through --node-exec" {
  run "$script" $(enc_args) --node-exec "${BATS_TEST_DIRNAME}/bin/on-node"
  [ "$status" -eq 0 ]
  grep -q 'lsblk' "$FIXTURES/on-node.calls"
  grep -q 'cryptsetup status pvc-1' "$FIXTURES/on-node.calls"
  grep -q 'dd if=' "$FIXTURES/on-node.calls"
}

@test "encryption fails when the StorageClass references a different Secret" {
  printf 'kube-system/some-other-secret\n' > "$FIXTURES/sc.ref"
  run "$script" $(enc_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"some-other-secret"* ]]
  [[ "$output" == *"hcloud-volume-passphrase"* ]]
}

@test "encryption fails when the StorageClass cannot be read" {
  rm "$FIXTURES/sc.ref"
  run "$script" $(enc_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"hcloud-volumes-encrypted"* ]]
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

manifest_args() {
  echo --volume vol1 --checks compare --kind files --old-manifest "${BATS_TEST_TMPDIR}/old.manifest" --new-manifest "${BATS_TEST_TMPDIR}/new.manifest"
}

write_manifests() {
  printf './a\t6\taaa\t5984:5984\n./sub/b\t5\tbbb\t5984:5984\n' > "${BATS_TEST_TMPDIR}/old.manifest"
  printf './a\t6\taaa\t5984:5984\n./sub/b\t5\tbbb\t5984:5984\n' > "${BATS_TEST_TMPDIR}/new.manifest"
}

@test "manifest compare passes on identical manifests" {
  write_manifests
  run "$script" $(manifest_args)
  [ "$status" -eq 0 ]
  [[ "$output" == *"files=2 bytes=11"* ]]
}

@test "manifest compare fails when a file is missing from the new manifest" {
  write_manifests
  printf './a\t6\taaa\t5984:5984\n' > "${BATS_TEST_TMPDIR}/new.manifest"
  run "$script" $(manifest_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"differing paths: ./sub/b"* ]]
}

@test "manifest compare fails when a file size changed" {
  write_manifests
  printf './a\t7\taaa\t5984:5984\n./sub/b\t5\tbbb\t5984:5984\n' > "${BATS_TEST_TMPDIR}/new.manifest"
  run "$script" $(manifest_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"differing paths: ./a"* ]]
}

@test "manifest compare fails when only a checksum changed" {
  write_manifests
  printf './a\t6\taaa\t5984:5984\n./sub/b\t5\tccc\t5984:5984\n' > "${BATS_TEST_TMPDIR}/new.manifest"
  run "$script" $(manifest_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"differing paths: ./sub/b"* ]]
}

@test "manifest compare fails when only a file owner changed" {
  write_manifests
  printf './a\t6\taaa\t0:0\n./sub/b\t5\tbbb\t5984:5984\n' > "${BATS_TEST_TMPDIR}/new.manifest"
  run "$script" $(manifest_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"differing paths: ./a"* ]]
}

@test "manifest compare fails when a manifest cannot be read" {
  write_manifests
  rm "${BATS_TEST_TMPDIR}/new.manifest"
  run "$script" $(manifest_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot read"* ]]
}

@test "files compare needs both manifests or both directories" {
  run "$script" --volume vol1 --checks compare --kind files --old-manifest "${BATS_TEST_TMPDIR}/old.manifest"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--new-manifest"* ]]
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

@test "health fails closed when the logs cannot be read" {
  ready_pod_json 0 > "$FIXTURES/pods.json"
  touch "$FIXTURES/logs.fail"
  run "$script" $(health_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"app=synapse"* ]]
  [[ "$output" == *"logs"* ]]
}

@test "health fails when the logs show a volume error" {
  ready_pod_json 0 > "$FIXTURES/pods.json"
  echo "ERROR permission denied opening /data/media" > "$FIXTURES/logs.txt"
  run "$script" $(health_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"logs"* ]]
}

@test "health ignores LOG-level CNPG JSON lines that mention the database" {
  ready_pod_json 0 > "$FIXTURES/pods.json"
  cat > "$FIXTURES/logs.txt" <<'EOF'
{"level":"info","logger":"postgres","record":{"error_severity":"LOG","database_name":"ente","message":"database system was interrupted; last known up at 2026-10-04 10:00:00 UTC"}}
{"level":"info","logger":"postgres","record":{"error_severity":"LOG","message":"database system is ready to accept read-only connections"}}
EOF
  run "$script" $(health_args)
  [ "$status" -eq 0 ]
}

@test "health ignores the FATAL 57P03 startup line during a replica start" {
  ready_pod_json 0 > "$FIXTURES/pods.json"
  echo '{"logger":"postgres","record":{"error_severity":"FATAL","sql_state_code":"57P03","message":"the database system is starting up"}}' > "$FIXTURES/logs.txt"
  run "$script" $(health_args)
  [ "$status" -eq 0 ]
}

@test "health fails on a JSON ERROR record and reports its message" {
  ready_pod_json 0 > "$FIXTURES/pods.json"
  echo '{"logger":"postgres","record":{"error_severity":"ERROR","sql_state_code":"53100","message":"could not write to file: No space left on device"}}' > "$FIXTURES/logs.txt"
  run "$script" $(health_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"logs show"* ]]
  [[ "$output" == *"No space left on device"* ]]
}

@test "health still fails on a plain-text read-only file system line" {
  ready_pod_json 0 > "$FIXTURES/pods.json"
  echo "open /data/x: read-only file system" > "$FIXTURES/logs.txt"
  run "$script" $(health_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"logs show"* ]]
}

# --- part 3: functional ---

@test "matrix functional fails clearly when the verify-bot token is not exported" {
  unset VERIFY_BOT_TOKEN
  run "$script" --volume vol1 --checks functional --service matrix --homeserver https://matrix.test
  [ "$status" -eq 1 ]
  [[ "$output" == *"VERIFY_BOT_TOKEN"* ]]
}

@test "matrix functional never puts the token on a curl command line" {
  export VERIFY_BOT_TOKEN=tok-should-not-leak-123 VERIFY_BOT_ROOM='!room:matrix.test'
  echo '{"chunk":[{"content":{"body":"unrelated"}}]}' > "$FIXTURES/curl.out"
  run "$script" --volume vol1 --checks functional --service matrix --homeserver https://matrix.test
  [ -s "$FIXTURES/curl.calls" ]
  [ "$(grep -c 'tok-should-not-leak-123' "$FIXTURES/curl.calls" || true)" -eq 0 ]
  [ "$(grep -c 'Bearer' "$FIXTURES/curl.calls" || true)" -eq 0 ]
}

@test "photos functional fails clearly when the test account credentials are not exported" {
  unset VERIFY_PHOTOS_PASSWORD
  run "$script" --volume vol1 --checks functional --service photos --photos-url https://photos.test
  [ "$status" -eq 1 ]
  [[ "$output" == *"VERIFY_PHOTOS_PASSWORD"* ]]
}

@test "matrix functional fails when the homeserver stops answering" {
  export VERIFY_BOT_TOKEN=tok VERIFY_BOT_ROOM='!room:matrix.test'
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

ntfy_args() {
  echo --volume vol1 --checks functional --service notifications --ntfy-url https://ntfy.test --ntfy-topic verify
}

@test "notifications functional requires the ntfy url and topic" {
  run "$script" --volume vol1 --checks functional --service notifications
  [ "$status" -eq 2 ]
  [[ "$output" == *"--ntfy-url"* ]]
}

@test "notifications functional passes when the posted message is polled back" {
  touch "$FIXTURES/curl.echo.https___ntfy_test_verify_json_poll_1_since_all"
  run "$script" $(ntfy_args)
  [ "$status" -eq 0 ]
  [[ "$output" == *"check=functional result=pass"* ]]
  grep -q 'https://ntfy.test/verify/json?poll=1&since=all' "$FIXTURES/curl.calls"
}

@test "notifications functional fails when the message is not polled back" {
  echo '{"message":"something else"}' > "$FIXTURES/curl.out.https___ntfy_test_verify_json_poll_1_since_all"
  run "$script" $(ntfy_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"not read back"* ]]
}

@test "notifications functional fails when ntfy does not accept the post" {
  echo 22 > "$FIXTURES/curl.rc"
  run "$script" $(ntfy_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"https://ntfy.test"* ]]
}

couch_args() {
  echo --volume vol1 --checks functional --service documents --couchdb-url https://couch.test --couchdb-db notes
}

couch_env() {
  export VERIFY_COUCHDB_USER=verify-user VERIFY_COUCHDB_PASSWORD=pw-should-not-leak-456
  touch "$FIXTURES/curl.couch"
}

@test "documents functional fails clearly when the CouchDB credentials are not exported" {
  unset VERIFY_COUCHDB_USER VERIFY_COUCHDB_PASSWORD
  run "$script" $(couch_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"VERIFY_COUCHDB_PASSWORD"* ]]
}

@test "documents functional requires the CouchDB url and database" {
  run "$script" --volume vol1 --checks functional --service documents
  [ "$status" -eq 2 ]
  [[ "$output" == *"--couchdb-url"* ]]
}

@test "documents functional passes after create, read back and delete by rev" {
  couch_env
  run "$script" $(couch_args)
  [ "$status" -eq 0 ]
  [[ "$output" == *"check=functional result=pass"* ]]
  grep -q -- '-X DELETE .*rev=1-abc$' "$FIXTURES/curl.calls"
}

@test "documents functional never puts the password on a curl command line" {
  couch_env
  run "$script" $(couch_args)
  [ -s "$FIXTURES/curl.calls" ]
  [ "$(grep -c 'pw-should-not-leak-456' "$FIXTURES/curl.calls" || true)" -eq 0 ]
  [[ "$output" != *"pw-should-not-leak-456"* ]]
}

@test "documents functional fails when the document cannot be created" {
  couch_env
  touch "$FIXTURES/curl.couch.fail.PUT"
  run "$script" $(couch_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"create"* ]]
}

@test "documents functional fails when the document cannot be read back" {
  couch_env
  touch "$FIXTURES/curl.couch.fail.GET"
  run "$script" $(couch_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"read back"* ]]
}

@test "documents functional fails when the document cannot be deleted" {
  couch_env
  touch "$FIXTURES/curl.couch.fail.DELETE"
  run "$script" $(couch_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"delete"* ]]
}

@test "an unknown service is a usage error" {
  run "$script" --volume vol1 --checks functional --service nonsense
  [ "$status" -eq 2 ]
  [[ "$output" == *"nonsense"* ]]
}

# --- part 4: fresh backup ---

velero_backup() {
  printf '{"items":[{"metadata":{"name":"b1"},"spec":{"includedNamespaces":%s},"status":{"phase":"%s"}}]}\n' "$1" "$2" > "$FIXTURES/backups.json"
}

cnpg_backup() {
  printf '{"items":[{"metadata":{"name":"b1"},"spec":{"cluster":{"name":"%s"}},"status":{"phase":"%s"}}]}\n' "$1" "$2" > "$FIXTURES/backups.json"
}

@test "backup fails when no completed Velero backup is listed" {
  velero_backup '["matrix"]' InProgress
  run "$script" --volume vol1 --checks backup --backup velero --backup-namespace velero --backup-for matrix
  [ "$status" -eq 1 ]
  [[ "$output" == *"no completed"* ]]
}

@test "backup passes with a completed Velero backup that includes the workload namespace" {
  velero_backup '["couchdb","matrix"]' Completed
  run "$script" --volume vol1 --checks backup --backup velero --backup-namespace velero --backup-for matrix
  [ "$status" -eq 0 ]
}

@test "backup passes with a completed Velero backup of every namespace" {
  velero_backup '[]' Completed
  run "$script" --volume vol1 --checks backup --backup velero --backup-namespace velero --backup-for matrix
  [ "$status" -eq 0 ]
}

@test "backup fails when the only completed Velero backup is of another namespace" {
  velero_backup '["couchdb"]' Completed
  run "$script" --volume vol1 --checks backup --backup velero --backup-namespace velero --backup-for matrix
  [ "$status" -eq 1 ]
  [[ "$output" == *"matrix"* ]]
}

@test "backup fails when no completed CNPG backup is listed" {
  echo '{"items":[]}' > "$FIXTURES/backups.json"
  run "$script" --volume vol1 --checks backup --backup cnpg --backup-namespace matrix --backup-for shared-postgres
  [ "$status" -eq 1 ]
}

@test "backup passes with a completed CNPG backup of the named cluster" {
  cnpg_backup shared-postgres completed
  run "$script" --volume vol1 --checks backup --backup cnpg --backup-namespace matrix --backup-for shared-postgres
  [ "$status" -eq 0 ]
}

@test "backup fails when the only completed CNPG backup is of another cluster" {
  cnpg_backup other-db completed
  run "$script" --volume vol1 --checks backup --backup cnpg --backup-namespace matrix --backup-for shared-postgres
  [ "$status" -eq 1 ]
  [[ "$output" == *"shared-postgres"* ]]
}

@test "backup without --backup-for is a usage error" {
  run "$script" --volume vol1 --checks backup --backup velero --backup-namespace velero
  [ "$status" -eq 2 ]
  [[ "$output" == *"--backup-for"* ]]
}

# --- several databases in one run: one line each, one verdict ---

@test "database compare over a list of databases prints a line per database and one verdict" {
  printf 'users|10|abc\n' > "$FIXTURES/psql-shared-postgres-1.txt"
  cp "$FIXTURES/psql-shared-postgres-1.txt" "$FIXTURES/psql-shared-postgres-2.txt"
  run "$script" --volume db1 --checks compare --kind database --namespace matrix \
    --old-pod shared-postgres-1 --new-pod shared-postgres-2 --db synapse,mas,niks3
  [ "$status" -eq 0 ]
  [ "$(grep -c 'check=compare result=pass' <<<"$output")" -eq 3 ]
  [ "$(grep -c 'verdict=' <<<"$output")" -eq 1 ]
  [[ "$output" == *"db=mas"* ]]
}

@test "one differing database in the list fails the run and is named" {
  printf 'users|10|abc\n' > "$FIXTURES/psql-shared-postgres-1.txt"
  cp "$FIXTURES/psql-shared-postgres-1.txt" "$FIXTURES/psql-shared-postgres-2.txt"
  printf 'users|10|zzz\n' > "$FIXTURES/psql-shared-postgres-2-mas.txt"
  run "$script" --volume db1 --checks compare --kind database --namespace matrix \
    --old-pod shared-postgres-1 --new-pod shared-postgres-2 --db synapse,mas,niks3
  [ "$status" -eq 1 ]
  [ "$(grep -c 'check=compare result=fail' <<<"$output")" -eq 1 ]
  [[ "$output" == *"db=mas"*"result=fail"* || "$output" == *"result=fail"*"mas"* ]]
  [[ "$output" == *"verdict=failed"* ]]
}

# --- found in review: the class must come from the volume, and a LUKS header is not an ext4 hit ---

@test "encryption fails when the PV was provisioned from a different class" {
  printf 'hcloud-volumes\n' > "$FIXTURES/pv-pvc-1.class"
  run "$script" $(enc_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"pvc-1"* ]]
  [[ "$output" == *"hcloud-volumes-encrypted"* ]]
}

@test "encryption fails when the PV cannot be read" {
  rm "$FIXTURES/pv-pvc-1.class"
  run "$script" $(enc_args)
  [ "$status" -eq 1 ]
  [[ "$output" == *"pvc-1"* ]]
}

@test "encryption without --pv is a usage error" {
  run "$script" --volume vol1 --checks encryption --device "$device" --mapping pvc-1 \
    --secret kube-system/hcloud-volume-passphrase --storageclass hcloud-volumes-encrypted
  [ "$status" -eq 2 ]
  [[ "$output" == *"--pv"* ]]
}

@test "bytes 53 ef at offset 1080 of a device with a LUKS header are not an ext4 hit" {
  printf 'LUKS\xba\xbe' > "$device"
  head -c $((1080 - 6)) /dev/zero >> "$device"
  printf '\x53\xef' >> "$device"
  head -c 3000 /dev/zero >> "$device"
  run "$script" $(enc_args)
  [ "$status" -eq 0 ]
}
