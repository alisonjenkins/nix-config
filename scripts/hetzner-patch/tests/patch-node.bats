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

# ---- steps -------------------------------------------------------------------

SET_DEFAULT_PRIOR="bootctl set-default $PRIOR_ID\$"
SET_DEFAULT_NEW="bootctl set-default $NEW_ID\$"
SET_ONESHOT_NEW="bootctl set-oneshot $NEW_ID\$"
REBOOT='sudo systemctl reboot$'
READLINK_PROBE='readlink /run/current-system$'

assert_only_allowed_hcloud() {
  ! grep '^hcloud ' "$FAKE_CALLLOG" | grep -Ev '^hcloud (server describe|image list|server reset)'
}

@test "happy path: boot-once sequence, default flipped to the new entry only after the health probe" {
  patch
  [ "$status" -eq 0 ]
  assert_order \
    "^nix path-info $TOP\$" \
    '^ssh .* nix path-info --all' \
    '^ssh .* sudo bootctl status$' \
    "^nix copy --no-check-sigs --to ssh-ng://$HOST $TOP\$" \
    "sudo nix-env -p /nix/var/nix/profiles/system --set $TOP\$" \
    "sudo $TOP/bin/switch-to-configuration boot\$" \
    'ls /boot/loader/entries$' \
    "test -e /boot/loader/entries/$PRIOR_ID\$" \
    "$SET_DEFAULT_PRIOR" "$SET_ONESHOT_NEW" "$REBOOT" "$READLINK_PROBE" ' true$' "$SET_DEFAULT_NEW"
  never_called 'bash -s|register-validity'
  never_called 'server reset'
  assert_only_allowed_hcloud
  [ "$(jq -r .outcome "$REC")" = patched ]
}

@test "the highest-numbered generation entry is chosen numerically, not lexically" {
  patch
  called "$SET_ONESHOT_NEW"
  never_called 'set-oneshot nixos-generation-9.conf'
  never_called 'set-oneshot .*specialisation'
}

@test "unregistered store: registers it, verifies, and sets a missing profile first" {
  rule ssh any '* nix path-info --all*' 0 0
  rule ssh any '* test -e /nix/var/nix/profiles/system' 1 ''
  patch
  [ "$status" -eq 0 ]
  assert_order \
    '^ssh .* nix path-info --all' \
    'bash -s -- /nix/store' \
    'sudo nix-store --register-validity' \
    ' nix path-info /run/current-system$' \
    'test -e /nix/var/nix/profiles/system$' \
    'sudo nix-env -p /nix/var/nix/profiles/system --set "\$\(readlink -f /run/current-system\)"$' \
    '^nix copy ' \
    "sudo nix-env -p /nix/var/nix/profiles/system --set $TOP\$" \
    "$SET_DEFAULT_NEW"
}

@test "registered store and present profile: neither is touched" {
  patch
  never_called 'register-validity'
  never_called 'readlink -f /run/current-system'
}

@test "registration that does not make the running system valid refuses before copying" {
  rule ssh any '* nix path-info --all*' 0 0
  rule ssh any '* nix path-info /run/current-system' 1 ''
  patch
  [ "$status" -eq 2 ]
  [[ "$output" == *"register-validity"* ]]
  never_called '^nix copy|switch-to-configuration|systemctl reboot|bootctl set-'
}

@test "copy failure refuses before activating anything" {
  rule nix any "copy --no-check-sigs --to ssh-ng://$HOST $TOP" 1 'boom'
  patch
  [ "$status" -eq 2 ]
  never_called 'switch-to-configuration|systemctl reboot|bootctl set-'
  [ "$(jq -r .outcome "$REC")" = refused ]
}

@test "switch-to-configuration failure restores the old default and refuses without rebooting" {
  rule ssh any '*switch-to-configuration boot' 1 ''
  patch
  [ "$status" -eq 2 ]
  called "$SET_DEFAULT_PRIOR"
  never_called "$REBOOT|set-oneshot"
}

@test "missing prior boot entry refuses without rebooting and never points the default at it" {
  rule ssh any "* test -e /boot/loader/entries/$PRIOR_ID" 1 ''
  patch
  [ "$status" -eq 2 ]
  never_called "$REBOOT|set-oneshot|$SET_DEFAULT_NEW|$SET_DEFAULT_PRIOR"
  [[ "$output" == *"$PRIOR_ID"* ]]
  [ "$(jq -r .outcome "$REC")" = refused ]
}

@test "a pruned booted entry falls back to the default entry as the rollback target" {
  rule ssh pre '* sudo bootctl status' 0 "Current Entry: nixos-generation-1.conf\nDefault Entry: $PRIOR_ID"
  rule ssh post '* sudo bootctl status' 0 "Current Entry: $NEW_ID\nDefault Entry: $NEW_ID"
  rule ssh any '* test -e /boot/loader/entries/nixos-generation-1.conf' 1 ''
  patch
  [ "$status" -eq 0 ]
  [[ "$output" == *"no longer in the ESP"* ]]
  called "$SET_DEFAULT_PRIOR"
  never_called 'set-default nixos-generation-1.conf'
}

@test "new entry equal to the prior entry refuses without rebooting" {
  rule ssh any '* ls /boot/loader/entries' 0 "$PRIOR_ID\nloader.conf"
  patch
  [ "$status" -eq 2 ]
  called "$SET_DEFAULT_PRIOR"
  never_called "$REBOOT|set-oneshot"
}

@test "the image's original entry nixos.efi counts as bootable via /boot/EFI/Linux" {
  rule ssh any '* sudo bootctl status' 0 "Current Entry: nixos.efi\nDefault Entry: $NEW_ID"
  patch
  [ "$status" -eq 0 ]
  assert_order 'test -e /boot/EFI/Linux/nixos.efi$' 'bootctl set-default nixos.efi$' "$SET_ONESHOT_NEW"
}

@test "nixos.efi missing from the ESP refuses without rebooting" {
  rule ssh any '* sudo bootctl status' 0 "Current Entry: nixos.efi\nDefault Entry: $NEW_ID"
  rule ssh any '* test -e /boot/EFI/Linux/nixos.efi' 1 ''
  patch
  [ "$status" -eq 2 ]
  never_called "$REBOOT|set-oneshot"
}

@test "an unreadable current boot entry refuses before copying" {
  rule ssh any '* sudo bootctl status' 0 'nothing useful'
  patch
  [ "$status" -eq 2 ]
  never_called '^nix copy|switch-to-configuration|systemctl reboot'
}

@test "a failed reboot command refuses and never probes health" {
  rule ssh any '* sudo systemctl reboot' 1 ''
  patch
  [ "$status" -eq 2 ]
  never_called "$SET_DEFAULT_NEW"
  called "$SET_DEFAULT_PRIOR"
}

@test "polls until healthy: waits through ssh outages, then flips the default" {
  rule ssh post '* readlink /run/current-system' 255 '' 3
  patch
  [ "$status" -eq 0 ]
  [ "$(grep -c "$READLINK_PROBE" "$FAKE_CALLLOG")" -ge 5 ]
  called '^sleep '
  assert_order "$REBOOT" "$READLINK_PROBE" "$SET_DEFAULT_NEW"
}

@test "never healthy: rolls back via rollback.sh, never sets the new default, exit 3" {
  rule ssh post '* readlink /run/current-system' 255 ''
  patch --health-timeout 60
  [ "$status" -eq 3 ]
  assert_order "$REBOOT" '^hcloud server reset '"$SID"'$'
  never_called "$SET_DEFAULT_NEW"
  assert_only_allowed_hcloud
  [ "$(cat "$FAKE_DIR/clock")" -ge $((CLOCK0 + 60)) ]
  jq -e '.outcome == "rolled-back" and .from == "'"$PRIOR_GEN"'" and .to == "'"$TOP"'"' "$REC"
}

@test "rollback.sh is called with host, server id and the prior generation" {
  stub_rollback 0
  rule ssh post '* readlink /run/current-system' 255 ''
  patch --health-timeout 30
  [ "$status" -eq 3 ]
  called "^rollback.sh --host $HOST --server-id $SID --expect-generation $PRIOR_GEN\$"
}

@test "rollback.sh failing gives exit 4 and outcome rollback-failed" {
  stub_rollback 4
  rule ssh post '* readlink /run/current-system' 255 ''
  patch --health-timeout 30
  [ "$status" -eq 4 ]
  never_called "$SET_DEFAULT_NEW"
  [ "$(jq -r .outcome "$REC")" = rollback-failed ]
}

@test "real rollback.sh that cannot get the old generation back also ends in exit 4" {
  rule ssh post '* readlink /run/current-system' 255 ''
  rule ssh reset '* readlink /run/current-system' 255 ''
  patch --health-timeout 30
  [ "$status" -eq 4 ]
  called "^hcloud server reset $SID\$"
  [[ "$output" == *"web console"* ]]
}

@test "ssh up on the wrong generation counts as unhealthy" {
  rule ssh post '* readlink /run/current-system' 0 "$PRIOR_GEN"
  patch --health-timeout 30
  [ "$status" -eq 3 ]
  never_called "$SET_DEFAULT_NEW"
  called "^hcloud server reset $SID\$"
}

@test "a failing --health-cmd on the host counts as unhealthy" {
  rule ssh any '* check-k3s' 1 ''
  patch --health-timeout 30 --health-cmd check-k3s
  [ "$status" -eq 3 ]
  called ' check-k3s$'
  never_called "$SET_DEFAULT_NEW"
}

@test "a passing --health-cmd runs on the host before the default is flipped" {
  rule ssh any '* check-k3s' 0 ''
  patch --health-cmd check-k3s
  [ "$status" -eq 0 ]
  assert_order "$REBOOT" ' check-k3s$' "$SET_DEFAULT_NEW"
}

@test "unlock-master.sh runs after the reboot, before the health probe, only with --unlock-via" {
  patch --unlock-via edge --unlock-jump jump.example
  [ "$status" -eq 0 ]
  assert_order "$REBOOT" "^unlock-master.sh --host $HOST --via edge --approve --jump jump.example\$" "$READLINK_PROBE" "$SET_DEFAULT_NEW"
}

@test "unlock-master.sh gets --approve: nobody can type at its tty mid-reboot, and --approve was already given" {
  patch --unlock-via public
  [ "$status" -eq 0 ]
  called "^unlock-master.sh --host $HOST --via public --approve\$"
}

@test "--unlock-via edge without --unlock-jump is a usage error before anything runs" {
  patch --unlock-via edge
  [ "$status" -eq 1 ]
  [[ "$output" == *"--unlock-jump"* ]]
  never_called '^ssh|^nix copy'
}

@test "--unlock-jump without --unlock-via edge is a usage error" {
  patch --unlock-via public --unlock-jump jump.example
  [ "$status" -eq 1 ]
}

@test "the remote store-registration probe stops when nix path-info itself fails" {
  patch
  called 'nix path-info --all >"\$t" && wc -l'
}

@test "a diverged booted and current system makes the default entry the rollback target" {
  rule ssh any '*booted-system*current-system*' 0 ''
  rule ssh any '* test -e /boot/loader/entries/nixos-generation-1.conf' 0 ''
  rule ssh pre '* sudo bootctl status' 0 "Current Entry: nixos-generation-1.conf\nDefault Entry: $PRIOR_ID"
  rule ssh post '* sudo bootctl status' 0 "Current Entry: $NEW_ID\nDefault Entry: $NEW_ID"
  patch
  [ "$status" -eq 0 ]
  called "$SET_DEFAULT_PRIOR"
  never_called 'set-default nixos-generation-1.conf'
}

@test "the live-or-reboot decision also compares kernel-params" {
  kernel_unchanged
  patch
  called 'kernel-params'
}

@test "without --unlock-via unlock-master.sh is never called" {
  patch
  never_called 'unlock-master'
}

@test "a failing unlock is unhealthy: rolled back, default never flipped" {
  echo 1 > "$FAKE_DIR/unlock.rc"
  patch --unlock-via public --health-timeout 30
  [ "$status" -eq 3 ]
  called "^unlock-master.sh --host $HOST --via public --approve\$"
  never_called "$SET_DEFAULT_NEW"
  called "^hcloud server reset $SID\$"
}

@test "an unconfirmed default after a healthy boot is reported, not silently accepted" {
  rule ssh any '* sudo bootctl status' 0 "Current Entry: $PRIOR_ID\nDefault Entry: $PRIOR_ID"
  patch
  [ "$status" -eq 5 ]
  [[ "$output" == *"step=confirm result=fail"* ]]
}

@test "a failing set-default NEW on a healthy host is reported, not silently accepted" {
  rule ssh any "* sudo bootctl set-default $NEW_ID" 1 ''
  patch
  [ "$status" -eq 5 ]
  [[ "$output" == *"step=commit result=fail"* ]]
}

@test "records a patched run as valid JSON with zero servers created or deleted" {
  patch
  [ "$(wc -l < "$REC")" -eq 1 ]
  jq -e --arg f "$PRIOR_GEN" --arg t "$TOP" '
    .outcome == "patched" and .from == $f and .to == $t and .gates_failed == []
    and .servers_created == 0 and .servers_deleted == 0' "$REC"
}

@test "all output of a full run is timestamped and the token never appears anywhere" {
  rule ssh post '* readlink /run/current-system' 255 ''
  patch --health-timeout 30
  assert_timestamped
  [[ "$output" != *"$TOKEN"* ]]
  ! grep -F "$TOKEN" "$REC" "$FAKE_CALLLOG"
}

@test "the default record file is under XDG_STATE_HOME" {
  rule nix any "path-info $TOP" 1 ''
  run_script patch-node.sh --host "$HOST" --server-id "$SID" --toplevel "$TOP" --approve
  [ -s "$XDG_STATE_HOME/hetzner-patch/runs.jsonl" ]
}

# ---- rebootless: kernel, initrd and modules unchanged --------------------

LIVE_SWITCH="sudo systemd-run .*--unit=hetzner-patch-switch .*$TOP/bin/switch-to-configuration test\$"
PRIOR_LIVE_SWITCH="sudo systemd-run .*--unit=hetzner-patch-switch .*$PRIOR_GEN/bin/switch-to-configuration test\$"
STOP_SWITCH_UNIT='systemctl stop hetzner-patch-switch'

kernel_unchanged() { rule ssh any '*/run/booted-system/*' 0 ''; }
switch_unit_state() { rule ssh any '*systemctl show hetzner-patch-switch*' 0 "ActiveState=$1\nSubState=$2\nResult=$3\nExecMainStatus=$4"; }

@test "rebootless: unchanged kernel activates live, never reboots, flips the default only when healthy" {
  kernel_unchanged
  patch
  [ "$status" -eq 0 ]
  assert_order "^nix copy " "$LIVE_SWITCH" "$READLINK_PROBE" ' true$' \
    "sudo nix-env -p /nix/var/nix/profiles/system --set $TOP\$" "switch-to-configuration boot\$" "$SET_DEFAULT_NEW"
  never_called "$REBOOT"
  never_called 'bootctl set-oneshot'
  never_called 'server reset'
  [[ "$output" == *"no reboot"* ]]
  [ "$(jq -r .outcome "$REC")" = patched ]
}

@test "rebootless: no generation or boot entry is written until the host is healthy" {
  kernel_unchanged
  rule ssh any '* check-k3s' 1 ''
  patch --health-timeout 30 --health-cmd check-k3s
  [ "$status" -eq 3 ]
  never_called 'nix-env'
  never_called 'switch-to-configuration boot'
  never_called 'bootctl set-'
}

@test "rebootless: a boot entry that cannot be written after a healthy switch is reported, not silent" {
  kernel_unchanged
  rule ssh any '*switch-to-configuration boot' 1 ''
  patch
  [ "$status" -eq 5 ]
  never_called "$SET_DEFAULT_NEW"
  [[ "$output" == *"boot entry"* ]]
  [ "$(jq -r .outcome "$REC")" = patched ]
}

@test "rebootless: a changed kernel still reboots" {
  patch
  [ "$status" -eq 0 ]
  called "$REBOOT"
  never_called "$LIVE_SWITCH"
}

@test "rebootless: --force-reboot reboots even when the kernel is unchanged" {
  kernel_unchanged
  patch --force-reboot
  [ "$status" -eq 0 ]
  called "$REBOOT"
  never_called "$LIVE_SWITCH"
}

@test "rebootless: a failing kernel comparison reboots rather than assuming it is unchanged" {
  rule ssh any '*/run/booted-system/*' 255 ''
  patch
  [ "$status" -eq 0 ]
  called "$REBOOT"
  never_called "$LIVE_SWITCH"
}

@test "rebootless: unhealthy after the live switch goes back live, with no reset and no reboot" {
  kernel_unchanged
  rule ssh any '* check-k3s' 1 ''
  patch --health-timeout 30 --health-cmd check-k3s
  [ "$status" -eq 3 ]
  assert_order "$LIVE_SWITCH" "$STOP_SWITCH_UNIT" "$PRIOR_LIVE_SWITCH"
  never_called "$REBOOT"
  never_called 'server reset'
  never_called "$SET_DEFAULT_NEW"
  [ "$(jq -r .outcome "$REC")" = rolled-back ]
}

@test "rebootless: a switch that failed after activating goes back live even though the probe passes" {
  kernel_unchanged
  switch_unit_state failed failed exit-code 4
  patch --health-timeout 30
  [ "$status" -eq 3 ]
  called "$PRIOR_LIVE_SWITCH"
  never_called 'server reset'
  never_called "$SET_DEFAULT_NEW"
}

@test "rebootless: a switch stuck on slow units is stopped after a bounded wait so the boot entry can be written" {
  kernel_unchanged
  switch_unit_state active running success 0
  patch
  [ "$status" -eq 0 ]
  [[ "$output" == *"still running"* ]]
  assert_order "$LIVE_SWITCH" "$STOP_SWITCH_UNIT" "sudo nix-env -p /nix/var/nix/profiles/system --set $TOP\$" "$SET_DEFAULT_NEW"
  [ "$(cat "$FAKE_DIR/clock")" -ge $((CLOCK0 + 60)) ]
}

@test "rebootless: a switch that finishes within the wait is left alone" {
  kernel_unchanged
  rule ssh any '*systemctl show hetzner-patch-switch*' 0 'ActiveState=active\nSubState=running\nResult=success\nExecMainStatus=0' 3
  patch
  [ "$status" -eq 0 ]
  [ "$(grep -c "$STOP_SWITCH_UNIT" "$FAKE_CALLLOG")" -eq 1 ]
  [[ "$output" == *"switch-to-configuration finished"* ]]
}

@test "a previous live switch still holding the lock refuses before copying anything" {
  rule ssh any '*systemctl show hetzner-patch-switch.service -p SubState --value*' 0 running
  patch
  [ "$status" -eq 2 ]
  [[ "$output" == *"hetzner-patch-switch.service"* ]]
  never_called '^nix copy|switch-to-configuration|systemctl reboot|bootctl set-|nix-env'
}

@test "rebootless: the switch unit failing to start refuses and has changed nothing on the host" {
  kernel_unchanged
  rule ssh any "*systemd-run*$TOP/bin/switch-to-configuration test" 1 ''
  patch
  [ "$status" -eq 2 ]
  never_called "$REBOOT"
  never_called 'bootctl set-|nix-env|switch-to-configuration boot'
}

@test "rebootless: a live rollback that fails falls back to the hard reset" {
  kernel_unchanged
  rule ssh any '* check-k3s' 1 ''
  rule ssh any "*systemd-run*$PRIOR_GEN/bin/switch-to-configuration test" 1 ''
  patch --health-timeout 30 --health-cmd check-k3s
  [ "$status" -eq 3 ]
  assert_order "$LIVE_SWITCH" "$PRIOR_LIVE_SWITCH" "^hcloud server reset $SID\$"
  never_called "$SET_DEFAULT_NEW"
}

@test "rebootless: unlock-master.sh is never called, since nothing was locked" {
  kernel_unchanged
  patch --unlock-via public
  [ "$status" -eq 0 ]
  never_called '^unlock-master.sh'
}

@test "--dry-run announces the rebootless branch" {
  patch --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"no reboot"* ]]
}
