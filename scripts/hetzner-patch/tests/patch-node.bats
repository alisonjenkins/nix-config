#!/usr/bin/env bats

load helpers

setup() {
  base_setup
  install_scripts patch-node.sh rollback.sh lib.sh
  ARGS=(--host "$HOST" --server-id "$SID" --toplevel "$TOP" --approve --record-file "$REC")
}

teardown() { base_teardown; }

patch() { run_script patch-node.sh "${ARGS[@]}" "$@"; }

assert_refused_untouched() {
  [ "$status" -eq 2 ]
  never_called "$MUT_RE"
  [ "$(jq -r .outcome "$REC")" = refused ]
}

# ---- arguments ----------------------------------------------------------

@test "unknown flag exits 1 with usage" {
  patch --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
  [ ! -s "$FAKE_CALLLOG" ]
}

@test "each missing required flag exits 1 with usage" {
  local flag
  for flag in --host --server-id --toplevel; do
    local args=()
    [ "$flag" = --host ] || args+=(--host "$HOST")
    [ "$flag" = --server-id ] || args+=(--server-id "$SID")
    [ "$flag" = --toplevel ] || args+=(--toplevel "$TOP")
    run_script patch-node.sh "${args[@]}" --approve
    [ "$status" -eq 1 ]
    [[ "$output" == *"usage:"* ]]
  done
}

# ---- gates: each fails alone, exits 2, mutates nothing --------------------

@test "G1: refuses without --approve" {
  run_script patch-node.sh --host "$HOST" --server-id "$SID" --toplevel "$TOP" --record-file "$REC"
  assert_refused_untouched
  [[ "$output" == *"step=G1 result=fail"* ]]
}

@test "G2: refuses when HCLOUD_TOKEN is unset" {
  unset HCLOUD_TOKEN
  patch
  assert_refused_untouched
  [[ "$output" == *"step=G2 result=fail"* ]]
}

@test "G2: refuses when hcloud server describe fails" {
  rule hcloud any "server describe $SID -o json" 1 'boom'
  patch
  assert_refused_untouched
  [[ "$output" == *"step=G2 result=fail"* ]]
}

@test "G2: refuses when the server is not running" {
  rule hcloud any "server describe $SID -o json" 0 '{"status":"off"}'
  patch
  assert_refused_untouched
  [[ "$output" == *"step=G2 result=fail"* ]]
}

@test "G3: refuses when ssh cannot read the current generation" {
  rule ssh any '* readlink /run/current-system' 255 ''
  patch
  assert_refused_untouched
  [[ "$output" == *"step=G3 result=fail"* ]]
}

@test "G4: refuses when the toplevel is not in the local store" {
  rule nix any "path-info $TOP" 1 'path is not valid'
  patch
  assert_refused_untouched
  [[ "$output" == *"step=G4 result=fail"* ]]
}

@test "G5: refuses when a node is not Ready" {
  rule kubectl any 'get nodes --no-headers' 0 'n1   Ready   cp   9d   v1\nn2   NotReady   worker   9d   v1'
  patch
  assert_refused_untouched
  [[ "$output" == *"step=G5 result=fail"* ]]
}

@test "G5: fails closed when kubectl itself fails" {
  rule kubectl any 'get nodes --no-headers' 1 ''
  patch
  assert_refused_untouched
  [[ "$output" == *"step=G5 result=fail"* ]]
}

@test "G5: skipped and says so when KUBECONFIG is unset" {
  unset KUBECONFIG
  rule kubectl any 'get nodes --no-headers' 0 'n1   NotReady   cp   9d   v1'
  patch --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"G5"*"skipped"* ]]
  never_called '^kubectl '
}

@test "G5: skipped and says so when kubectl is not installed" {
  rm "$STUBS/kubectl"
  patch --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"G5"*"skipped"* ]]
}

@test "G6: refuses when no snapshot of the server exists" {
  rule hcloud any 'image list --type snapshot -o json' 0 '[]'
  patch
  assert_refused_untouched
  [[ "$output" == *"step=G6 result=fail"* ]]
}

@test "G6: refuses when the only snapshot belongs to another server" {
  rule hcloud any 'image list --type snapshot -o json' 0 \
    '[{"id":7,"created":"2026-10-20T12:00:00+00:00","created_from":{"id":999,"name":"x"}}]'
  patch
  assert_refused_untouched
  [[ "$output" == *"step=G6 result=fail"* ]]
}

@test "G6: refuses when the snapshot is 30 days old or more" {
  local old
  old=$("$REAL_DATE" -u -d "@$((CLOCK0 - 31 * 86400))" +%Y-%m-%dT%H:%M:%S+00:00)
  rule hcloud any 'image list --type snapshot -o json' 0 \
    "[{\"id\":7,\"created\":\"$old\",\"created_from\":{\"id\":$SID,\"name\":\"m\"}}]"
  patch
  assert_refused_untouched
  [[ "$output" == *"step=G6 result=fail"* ]]
}

@test "G6: --no-snapshot-gate skips it and logs loudly" {
  rule hcloud any 'image list --type snapshot -o json' 0 '[]'
  patch --no-snapshot-gate --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING"*"snapshot gate DISABLED"* ]]
  never_called 'image list'
}

@test "G7: refuses when the ESP has less than 60 MiB free" {
  rule ssh any '* df --output=avail -B1M /boot' 0 'Avail\n  59M'
  patch
  assert_refused_untouched
  [[ "$output" == *"step=G7 result=fail"* ]]
}

@test "G7: exactly 60 MiB free passes" {
  rule ssh any '* df --output=avail -B1M /boot' 0 'Avail\n  60M'
  patch --dry-run
  [ "$status" -eq 0 ]
}

@test "several failing gates are all reported and recorded" {
  rule ssh any '* df --output=avail -B1M /boot' 0 'Avail\n  1M'
  rule nix any "path-info $TOP" 1 ''
  patch
  [ "$status" -eq 2 ]
  jq -e '.gates_failed | contains(["G4","G7"])' "$REC"
}

# ---- dry run ---------------------------------------------------------------

@test "--dry-run runs the gates, prints the plan and makes no mutating call" {
  patch --dry-run
  [ "$status" -eq 0 ]
  never_called "$MUT_RE"
  never_called 'bootctl'
  [[ "$output" == *"dry-run"* ]]
  [[ "$output" == *"switch-to-configuration boot"* ]]
  [ ! -e "$REC" ]
}

@test "--dry-run does not require --approve" {
  run_script patch-node.sh --host "$HOST" --server-id "$SID" --toplevel "$TOP" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"G1"*"skipped"* ]]
}

@test "--dry-run still exits 2 when a gate fails" {
  rule nix any "path-info $TOP" 1 ''
  patch --dry-run
  [ "$status" -eq 2 ]
  never_called "$MUT_RE"
}

# ---- output and record -----------------------------------------------------

@test "every output line starts with an ISO 8601 UTC time then host and step" {
  rule nix any "path-info $TOP" 1 ''
  patch
  assert_timestamped
  [[ "$output" == *" host=$HOST step="* ]]
}

@test "the token never appears in output, record or call log" {
  rule nix any "path-info $TOP" 1 ''
  patch
  [[ "$output" != *"$TOKEN"* ]]
  ! grep -F "$TOKEN" "$REC" "$FAKE_CALLLOG"
}

@test "a refusal appends one valid JSON line with the fixed fields" {
  rule nix any "path-info $TOP" 1 ''
  patch
  [ "$(wc -l < "$REC")" -eq 1 ]
  jq -e --arg h "$HOST" --arg t "$TOP" --arg f "$PRIOR_GEN" '
    .host == $h and .to == $t and .from == $f and .outcome == "refused"
    and .servers_created == 0 and .servers_deleted == 0
    and (.time | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
    and .gates_failed == ["G4"]' "$REC"
  patch
  [ "$(wc -l < "$REC")" -eq 2 ]
}

@test "the default record file is under XDG_STATE_HOME" {
  rule nix any "path-info $TOP" 1 ''
  run_script patch-node.sh --host "$HOST" --server-id "$SID" --toplevel "$TOP" --approve
  [ -s "$XDG_STATE_HOME/hetzner-patch/runs.jsonl" ]
}
