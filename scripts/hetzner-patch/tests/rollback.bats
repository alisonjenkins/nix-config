#!/usr/bin/env bats

load helpers

setup() {
  base_setup
  install_scripts rollback.sh lib.sh
  ARGS=(--host "$HOST" --server-id "$SID" --expect-generation "$PRIOR_GEN")
  rule ssh any '*for l in /nix/var/nix/profiles/system-*-link*' 0 \
    "/nix/var/nix/profiles/system-2-link $PRIOR_GEN\n/nix/var/nix/profiles/system-3-link $TOP"
  rule ssh any '* sudo nix-env -p /nix/var/nix/profiles/system --switch-generation*' 0 ''
}

teardown() { base_teardown; }

@test "resets the server by id, waits for ssh and exits 0 on the expected generation" {
  run_script rollback.sh "${ARGS[@]}"
  [ "$status" -eq 0 ]
  assert_order "^hcloud server reset $SID\$" "^ssh .* $HOST readlink /run/current-system\$"
  [[ "$output" == *"result=ok"* ]]
}

@test "keeps polling while ssh is down, then succeeds" {
  rule ssh reset '* readlink /run/current-system' 255 '' 3
  run_script rollback.sh "${ARGS[@]}"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'readlink /run/current-system' "$FAKE_CALLLOG")" -eq 4 ]
  called '^sleep '
}

@test "exit 4 when ssh comes back on a different generation, with manual recovery steps" {
  rule ssh reset '* readlink /run/current-system' 0 "$TOP"
  run_script rollback.sh "${ARGS[@]}"
  [ "$status" -eq 4 ]
  [[ "$output" == *"$TOP"* ]]
  [[ "$output" == *"web console"* ]]
  [[ "$output" == *"rescue"* ]]
  [[ "$output" == *"snapshot"* ]]
}

@test "exit 4 when the server never answers within --wait" {
  rule ssh reset '* readlink /run/current-system' 255 ''
  run_script rollback.sh "${ARGS[@]}" --wait 60
  [ "$status" -eq 4 ]
  [[ "$output" == *"web console"* ]]
  [ "$(cat "$FAKE_DIR/clock")" -ge $((CLOCK0 + 60)) ]
}

@test "exit 4 and no ssh probe when the reset itself fails" {
  rule hcloud any "server reset $SID" 1 'api error'
  run_script rollback.sh "${ARGS[@]}"
  [ "$status" -eq 4 ]
  never_called '^ssh '
  [[ "$output" == *"web console"* ]]
}

@test "only describe/list/reset hcloud calls are ever made" {
  run_script rollback.sh "${ARGS[@]}"
  [ "$status" -eq 0 ]
  ! grep '^hcloud ' "$FAKE_CALLLOG" | grep -Ev '^hcloud (server reset|server describe|image list)'
}

@test "the harness flags a forbidden hcloud call" {
  run env PATH="$TPATH" hcloud server delete 1
  [ "$status" -eq 99 ]
  [ -s "$FORBIDDEN" ]
  rm "$FORBIDDEN"
}

@test "missing HCLOUD_TOKEN exits 1 without calling anything" {
  unset HCLOUD_TOKEN
  run_script rollback.sh "${ARGS[@]}"
  [ "$status" -eq 1 ]
  [ ! -s "$FAKE_CALLLOG" ]
}

@test "the token never appears in output or the call log" {
  run_script rollback.sh "${ARGS[@]}"
  [[ "$output" != *"$TOKEN"* ]]
  ! grep -F "$TOKEN" "$FAKE_CALLLOG"
}

@test "every output line starts with an ISO 8601 UTC time and names the host" {
  run_script rollback.sh "${ARGS[@]}"
  assert_timestamped
  [[ "$output" == *"host=$HOST step="* ]]
}

@test "unknown flag and missing required flag exit 1 with usage" {
  run_script rollback.sh "${ARGS[@]}" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
  run_script rollback.sh --host "$HOST" --server-id "$SID"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "points the system profile back at the booted generation after verifying it" {
  run_script rollback.sh "${ARGS[@]}"
  [ "$status" -eq 0 ]
  assert_order "^hcloud server reset $SID\$" \
    "^ssh .* readlink /run/current-system\$" \
    "^ssh .* sudo nix-env -p /nix/var/nix/profiles/system --switch-generation 2\$"
}

@test "picks the highest-numbered link when several point at the booted generation" {
  rule ssh any '*for l in /nix/var/nix/profiles/system-*-link*' 0 \
    "/nix/var/nix/profiles/system-2-link $PRIOR_GEN\n/nix/var/nix/profiles/system-10-link $PRIOR_GEN\n/nix/var/nix/profiles/system-11-link $TOP"
  run_script rollback.sh "${ARGS[@]}"
  [ "$status" -eq 0 ]
  called '--switch-generation 10$'
}

@test "no link for the booted generation: exit 0 with a profile warning and no switch" {
  rule ssh any '*for l in /nix/var/nix/profiles/system-*-link*' 0 \
    "/nix/var/nix/profiles/system-3-link $TOP"
  run_script rollback.sh "${ARGS[@]}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"step=profile result=warn"* ]]
  never_called 'switch-generation'
}

@test "a failing switch-generation is a warning, not a rollback failure" {
  rule ssh any '* sudo nix-env -p /nix/var/nix/profiles/system --switch-generation*' 1 ''
  run_script rollback.sh "${ARGS[@]}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"step=profile result=warn"* ]]
}

@test "the profile is left alone when the server is not on the expected generation" {
  rule ssh reset '* readlink /run/current-system' 0 "$TOP"
  run_script rollback.sh "${ARGS[@]}"
  [ "$status" -eq 4 ]
  never_called 'switch-generation'
}

@test "reminds that the LUKS state volume stays locked until unlock-master.sh runs" {
  run_script rollback.sh "${ARGS[@]}"
  [[ "$output" == *"unlock-master.sh"* ]]
}
