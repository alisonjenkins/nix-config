#!/usr/bin/env bash
# shellcheck disable=SC2034
# Patch one Hetzner NixOS server in place: copy the closure, boot it once, keep it only if healthy.
# Only hcloud server describe / image list / server reset are ever called.
set -euo pipefail

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$DIR/lib.sh"

usage() {
  cat >&2 <<'USAGE'
usage: patch-node.sh --host HOST --server-id ID --toplevel STOREPATH [--approve]
         [--unlock-via public|edge [--unlock-jump JUMPHOST]] [--health-timeout SECS] [--health-cmd CMD]
         [--no-snapshot-gate] [--force-reboot] [--dry-run] [--record-file FILE]
  If the new kernel, initrd and modules match the booted system the generation is activated
  live with no reboot; --force-reboot always reboots.
  env: HCLOUD_TOKEN (required), KUBECONFIG (optional, enables the node-readiness gate)
  exit: 0 patched and healthy; 1 usage; 2 refused (see output for anything already done);
        3 unhealthy, rolled back; 4 unhealthy and rollback failed;
        5 patched and healthy, but the boot default was not set (the next reboot returns to the prior entry)
USAGE
}

host="" server_id="" toplevel="" approve=0 unlock_via="" unlock_jump="" dry_run=0 no_snapshot_gate=0 force_reboot=0
health_timeout=900 health_cmd=true
record_file="${XDG_STATE_HOME:-${HOME:-}/.local/state}/hetzner-patch/runs.jsonl"
min_esp_mib=60
max_snapshot_age_days=30
poll_interval=10


usage_error() { log args error "$1"; usage; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --host) host=${2:?--host needs a value}; shift 2 ;;
    --server-id) server_id=${2:?--server-id needs a value}; shift 2 ;;
    --toplevel) toplevel=${2:?--toplevel needs a value}; shift 2 ;;
    --approve) approve=1; shift ;;
    --unlock-via) unlock_via=${2:?--unlock-via needs a value}; shift 2 ;;
    --unlock-jump) unlock_jump=${2:?--unlock-jump needs a value}; shift 2 ;;
    --health-timeout) health_timeout=${2:?--health-timeout needs a value}; shift 2 ;;
    --health-cmd) health_cmd=${2:?--health-cmd needs a value}; shift 2 ;;
    --no-snapshot-gate) no_snapshot_gate=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    --force-reboot) force_reboot=1; shift ;;
    --record-file) record_file=${2:?--record-file needs a value}; shift 2 ;;
    *) usage_error "unknown argument: $1" ;;
  esac
done
HP_HOST=${host:--}
[ -n "$host" ] && [ -n "$server_id" ] && [ -n "$toplevel" ] \
  || usage_error "--host, --server-id and --toplevel are required"
case "$unlock_via" in "" | public | edge) ;; *) usage_error "--unlock-via must be public or edge, got $unlock_via" ;; esac
[ "$unlock_via" != edge ] || [ -n "$unlock_jump" ] || usage_error "--unlock-via edge requires --unlock-jump JUMPHOST"
[ -z "$unlock_jump" ] || [ "$unlock_via" = edge ] || usage_error "--unlock-jump only applies to --unlock-via edge"
case "$health_timeout" in "" | *[!0-9]*) usage_error "--health-timeout must be whole seconds, got $health_timeout" ;; esac

prior_gen=""
failed_gates=()

record() {
  local gates
  gates=$(printf '%s\n' "${failed_gates[@]}" | jq -R . | jq -sc 'map(select(length > 0))')
  mkdir -p "$(dirname "$record_file")"
  jq -nc --arg time "$(hp_ts)" --arg host "$host" --arg from "$prior_gen" --arg to "$toplevel" \
    --arg outcome "$1" --argjson gates "$gates" \
    '{time: $time, host: $host, from: $from, to: $to, outcome: $outcome, gates_failed: $gates,
      servers_created: 0, servers_deleted: 0}' >> "$record_file"
}

finish() { record "$1"; exit "$2"; }

gate_ok() { log "$1" ok "$2"; }
gate_skip() { log "$1" skipped "$2"; }
gate_fail() { failed_gates+=("$1"); log "$1" fail "$2"; }

run_gates() {
  local out status newest now age nodes avail

  if [ "$dry_run" -eq 1 ]; then
    gate_skip G1 "approval not required for --dry-run"
  elif [ "$approve" -eq 1 ]; then
    gate_ok G1 "--approve given"
  else
    gate_fail G1 "--approve not given"
  fi

  if [ -z "${HCLOUD_TOKEN:-}" ]; then
    gate_fail G2 "HCLOUD_TOKEN is not set"
  elif ! out=$(hcloud server describe "$server_id" -o json 2>/dev/null); then
    gate_fail G2 "hcloud server describe id=$server_id failed"
  elif status=$(jq -r '.status' <<<"$out" 2>/dev/null) && [ "$status" = running ]; then
    gate_ok G2 "server id=$server_id is running"
  else
    gate_fail G2 "server id=$server_id status=${status:-unparseable}, need running"
  fi

  if prior_gen=$(rssh readlink /run/current-system 2>/dev/null) && [ -n "$prior_gen" ]; then
    gate_ok G3 "current generation $prior_gen"
  else
    prior_gen=""
    gate_fail G3 "ssh $host readlink /run/current-system failed"
  fi

  if nix path-info "$toplevel" >/dev/null 2>&1; then
    gate_ok G4 "toplevel $toplevel is in the local store"
  else
    gate_fail G4 "nix path-info $toplevel failed"
  fi

  if ! command -v kubectl >/dev/null 2>&1; then
    gate_skip G5 "kubectl not on PATH"
  elif [ -z "${KUBECONFIG:-}" ]; then
    gate_skip G5 "KUBECONFIG not set"
  elif ! nodes=$(kubectl get nodes --no-headers 2>/dev/null) || [ -z "$nodes" ]; then
    gate_fail G5 "kubectl get nodes failed or returned no nodes"
  elif awk '$2 != "Ready" { bad = 1 } END { exit bad }' <<<"$nodes"; then
    gate_ok G5 "all nodes Ready"
  else
    gate_fail G5 "a node is not Ready: $(awk '$2 != "Ready" { printf "%s=%s ", $1, $2 }' <<<"$nodes")"
  fi

  if [ "$no_snapshot_gate" -eq 1 ]; then
    gate_skip G6 "WARNING snapshot gate DISABLED by --no-snapshot-gate: no restore point is guaranteed"
  elif ! out=$(hcloud image list --type snapshot -o json 2>/dev/null); then
    gate_fail G6 "hcloud image list --type snapshot failed"
  else
    now=$(date +%s)
    newest=$(jq -r --arg id "$server_id" '
      [.[] | select((.created_from.id | tostring) == $id)
           | (.created | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601)]
      | max // empty' <<<"$out" 2>/dev/null || true)
    if [ -z "$newest" ]; then
      gate_fail G6 "no snapshot with created_from.id=$server_id"
    else
      age=$(((now - newest) / 86400))
      if [ $((now - newest)) -lt $((max_snapshot_age_days * 86400)) ]; then
        gate_ok G6 "newest snapshot is ${age}d old"
      else
        gate_fail G6 "newest snapshot is ${age}d old, limit ${max_snapshot_age_days}d"
      fi
    fi
  fi

  if out=$(rssh df --output=avail -B1M /boot 2>/dev/null) \
    && avail=$(tail -n1 <<<"$out" | tr -dc '0-9') && [ -n "$avail" ]; then
    if [ "$avail" -ge "$min_esp_mib" ]; then
      gate_ok G7 "ESP has ${avail} MiB free"
    else
      gate_fail G7 "ESP has ${avail} MiB free, need ${min_esp_mib}"
    fi
  else
    gate_fail G7 "ssh $host df /boot failed or was unparseable"
  fi
}

plan() {
  local step
  for step in \
    "register the Nix store on $host if its database is empty" \
    "ensure /nix/var/nix/profiles/system exists" \
    "record the prior boot entry from bootctl status" \
    "nix copy --no-check-sigs --to ssh-ng://$host $toplevel" \
    "if kernel, initrd and modules match the booted system (unless --force-reboot): run $toplevel/bin/switch-to-configuration test as a transient unit, no reboot, and write no generation or boot entry yet" \
    "otherwise: nix-env --set $toplevel, $toplevel/bin/switch-to-configuration boot, check the new boot entry exists and the prior one is still bootable" \
    "otherwise: bootctl set-default PRIOR, bootctl set-oneshot NEW" \
    "otherwise: systemctl reboot${unlock_via:+, then unlock-master.sh --via $unlock_via}" \
    "poll up to ${health_timeout}s for current-system=$toplevel and health-cmd" \
    "healthy: (live only) nix-env --set and switch-to-configuration boot; then bootctl set-default NEW" \
    "unhealthy: live path switches back with no reboot, else rollback.sh (hcloud server reset id=$server_id)"; do
    log plan dry-run "$step"
  done
}

run_gates
if [ "${#failed_gates[@]}" -gt 0 ]; then
  log gates refused "failed: ${failed_gates[*]}; nothing on $host was changed"
  finish refused 2
fi
log gates ok "all gates passed"

if [ "$dry_run" -eq 1 ]; then
  plan
  log finish dry-run "no mutating call was made"
  exit 0
fi

prior_entry="" new_entry="" done_so_far="nothing on $host has changed yet"
reg_file=$(mktemp)
trap 'rm -f "$reg_file"' EXIT

refuse() {
  log "$1" refused "$2; done so far: $done_so_far"
  finish refused 2
}

# Setting the default explicitly matters: a stale EFI default variable overrides loader.conf.
# Never point it at an entry whose file is gone (configurationLimit prunes old ones).
restore_default() {
  if [ -z "$prior_entry" ] || ! rssh test -e "$(entry_path "$prior_entry")" 2>/dev/null; then
    log restore fail "prior entry ${prior_entry:-unknown} is missing from the ESP, leaving the default alone; check the boot default by hand on $host"
  elif rssh sudo bootctl set-default "$prior_entry" >/dev/null 2>&1; then
    log restore ok "default set back to $prior_entry"
    done_so_far="$done_so_far; default restored to $prior_entry"
  else
    log restore fail "could not set default back to $prior_entry; check the boot default by hand on $host"
  fi
}

refuse_restoring() { restore_default; refuse "$1" "$2"; }

entry_path() {
  case "$1" in
    nixos.efi) echo /boot/EFI/Linux/nixos.efi ;;
    *) echo "/boot/loader/entries/$1" ;;
  esac
}

register_store() {
  local count
  # shellcheck disable=SC2016  # the remote shell must expand $t and $rc, not this one
  if ! count=$(rssh 't=$(mktemp) && nix path-info --all >"$t" && wc -l <"$t"; rc=$?; rm -f "$t"; exit $rc' 2>/dev/null | tr -dc '0-9') || [ -z "$count" ]; then
    refuse register "ssh $host nix path-info --all failed"
  fi
  if [ "$count" -ne 0 ]; then
    log register skipped "nix database already holds $count paths"
    return
  fi
  log register start "nix database on $host is empty; generating registration"
  if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" bash -s -- /nix/store \
    < "$DIR/register-store.sh" > "$reg_file" || [ ! -s "$reg_file" ]; then
    refuse register "register-store.sh on $host produced no registration"
  fi
  if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" sudo nix-store --register-validity < "$reg_file"; then
    refuse register "nix-store --register-validity failed on $host"
  fi
  done_so_far="registered the store paths on $host (harmless)"
  rssh nix path-info /run/current-system >/dev/null 2>&1 \
    || refuse register "nix path-info /run/current-system still fails on $host after register-validity"
  log register ok "store registered"
}

ensure_profile() {
  if rssh test -e /nix/var/nix/profiles/system 2>/dev/null; then
    log profile skipped "system profile exists"
    return
  fi
  # shellcheck disable=SC2016
  rssh 'sudo nix-env -p /nix/var/nix/profiles/system --set "$(readlink -f /run/current-system)"' \
    || refuse profile "creating the system profile from the running system failed on $host"
  done_so_far="$done_so_far; created system profile for the running system"
  log profile ok "system profile set to the running system"
}

probe() {
  local got
  if ! got=$(rssh readlink /run/current-system 2>/dev/null) || [ -z "$got" ]; then
    probe_state="ssh unavailable"
    return 1
  fi
  if [ "$got" != "$toplevel" ]; then
    probe_state="current-system=$got"
    return 1
  fi
  if ! rssh "$health_cmd" >/dev/null 2>&1; then
    probe_state="health-cmd failed"
    return 1
  fi
}

wait_healthy() {
  local deadline
  deadline=$(($(date +%s) + health_timeout))
  while :; do
    probe && return 0
    log health waiting "$probe_state"
    [ "$(date +%s)" -lt "$deadline" ] || return 1
    sleep "$poll_interval"
  done
}

roll_back() {
  log rollback start "unhealthy: $probe_state; hard reset boots the prior default entry $prior_entry"
  if "$DIR/rollback.sh" --host "$host" --server-id "$server_id" --expect-generation "$prior_gen"; then
    finish rolled-back 3
  fi
  finish rollback-failed 4
}

# Same test NixOS uses to decide a reboot is needed. Any failure answers "changed", i.e. reboot.
kernel_unchanged() {
  rssh "for f in kernel initrd kernel-modules; do [ \"\$(readlink -f /run/booted-system/\$f)\" = \"\$(readlink -f $toplevel/\$f)\" ] || exit 1; done; cmp -s /run/booted-system/kernel-params $toplevel/kernel-params" >/dev/null 2>&1
}

switch_unit=hetzner-patch-switch

# switch-to-configuration test waits for every queued systemd job, and a unit that never
# finishes would hang it. As a transient unit it also outlives an ssh drop; health is judged
# by probing, not by waiting for it to return.
start_switch() {
  rssh "sudo systemctl stop $switch_unit.service; sudo systemctl reset-failed $switch_unit.service" >/dev/null 2>&1 || true
  rssh sudo systemd-run --quiet --unit="$switch_unit" --service-type=exec --property=RemainAfterExit=yes \
    "$1/bin/switch-to-configuration" test
}

wait_on_generation() {
  local deadline
  deadline=$(($(date +%s) + $2))
  while :; do
    [ "$(rssh readlink /run/current-system 2>/dev/null)" = "$1" ] && return 0
    [ "$(date +%s)" -lt "$deadline" ] || return 1
    sleep "$poll_interval"
  done
}

# Time a healthy host's switch gets to finish before it is stopped: it only waits on queued units.
switch_settle=60

# After a healthy probe: a switch that already failed is still a failed deploy.
check_switch() {
  local out active sub result status waited=0
  while :; do
    out=$(rssh systemctl show "$switch_unit.service" -p ActiveState -p SubState -p Result -p ExecMainStatus 2>/dev/null || true)
    active=$(sed -n 's/^ActiveState=//p' <<<"$out")
    sub=$(sed -n 's/^SubState=//p' <<<"$out")
    result=$(sed -n 's/^Result=//p' <<<"$out")
    status=$(sed -n 's/^ExecMainStatus=//p' <<<"$out")
    { [ "$sub" = running ] && [ "$waited" -lt "$switch_settle" ]; } || break
    sleep "$poll_interval"
    waited=$((waited + poll_interval))
  done
  if [ "$active" = failed ] || { [ -n "$result" ] && [ "$result" != success ]; }; then
    probe_state="switch-to-configuration test ${result:-failed} (exit ${status:-unknown})"
    live_roll_back
  elif [ "$sub" = running ]; then
    # Activation is done (current-system moved and the probe passed); it is only waiting on units,
    # and while it runs it holds the switch lock that writing the boot entry needs.
    log live warn "switch-to-configuration is still running after ${waited}s; the host answers the health probe, so stopping it to free the switch lock"
    rssh sudo systemctl stop "$switch_unit.service" >/dev/null 2>&1 \
      || log live warn "could not stop $switch_unit.service; writing the boot entry may fail on the switch lock"
  elif [ -z "$out" ]; then
    log live warn "could not read the state of $switch_unit.service; relying on the health probe"
  else
    log live ok "switch-to-configuration finished"
  fi
}

# Undo a live switch without a reboot; the hard reset is the fallback if that does not work.
live_roll_back() {
  log rollback start "unhealthy after the live switch: $probe_state; switching back to $prior_gen without a reboot"
  if start_switch "$prior_gen" && wait_on_generation "$prior_gen" 120; then
    log rollback ok "back on $prior_gen; no generation or boot entry had been written, default is still $prior_entry"
    finish rolled-back 3
  fi
  log rollback warn "live switch back to $prior_gen failed; falling back to a hard reset"
  roll_back
}

probe_state=""

register_store
ensure_profile

status_out=$(rssh sudo bootctl status 2>/dev/null || true)
prior_entry=$(sed -n 's/^ *Current Entry: *//p' <<<"$status_out" | head -n1)
[ -n "$prior_entry" ] || refuse entries "no 'Current Entry:' line in sudo bootctl status on $host"
# Live patches leave the booted entry behind the default, and configurationLimit may have pruned it.
default_entry=$(sed -n 's/^ *Default Entry: *//p' <<<"$status_out" | head -n1)
if ! rssh test -e "$(entry_path "$prior_entry")" 2>/dev/null \
  && [ -n "$default_entry" ] && [ "$default_entry" != "$prior_entry" ] \
  && rssh test -e "$(entry_path "$default_entry")" 2>/dev/null; then
  log entries warn "booted entry $prior_entry is no longer in the ESP; using default entry $default_entry as the rollback target"
  prior_entry=$default_entry
fi
# shellcheck disable=SC2016  # the remote shell must expand the substitutions, not this one
live_patched() { rssh 'test "$(readlink /run/booted-system)" != "$(readlink /run/current-system)"' 2>/dev/null; }
# A healthy live patch moves the default past the booted entry; a hard reset then boots the default.
if [ -n "$default_entry" ] && [ "$default_entry" != "$prior_entry" ] \
  && live_patched \
  && rssh test -e "$(entry_path "$default_entry")" 2>/dev/null; then
  log entries warn "$host runs a live-patched generation; using default entry $default_entry as the rollback target, not booted entry $prior_entry"
  prior_entry=$default_entry
fi
log entries ok "prior generation $prior_gen, prior entry $prior_entry"

# A leftover live switch holds the switch-to-configuration lock, so activation would fail halfway.
if [ "$(rssh systemctl show "$switch_unit.service" -p SubState --value 2>/dev/null)" = running ]; then
  refuse switch "a previous live switch ($switch_unit.service) is still running on $host and holds the switch lock; check systemctl list-jobs, then systemctl stop $switch_unit.service"
fi

nix copy --no-check-sigs --to "ssh-ng://$host" "$toplevel" \
  || refuse copy "nix copy $toplevel to $host failed (store paths may be partly copied; harmless)"
done_so_far="$done_so_far; copied the closure to $host"
log copy ok "closure copied"

live=0
if [ "$force_reboot" -eq 0 ] && kernel_unchanged; then live=1; fi

# Each failure handler exits: refuse_restoring before a reboot, boot_entry_unwritten after a live switch.
write_boot_entry() {
  local fail=$1 entries
  rssh sudo nix-env -p /nix/var/nix/profiles/system --set "$toplevel" \
    || "$fail" activate "nix-env --set $toplevel failed on $host"
  done_so_far="$done_so_far; system profile points at the new generation"
  rssh sudo "$toplevel/bin/switch-to-configuration" boot \
    || "$fail" activate "switch-to-configuration boot failed on $host; the bootloader may be partly updated"
  done_so_far="$done_so_far; boot entry written"
  log activate ok "boot entry written"

  entries=$(rssh ls /boot/loader/entries 2>/dev/null || true)
  new_entry=$(grep -E '^nixos-generation-[0-9]+\.conf$' <<<"$entries" | sort -V | tail -n1 || true)
  [ -n "$new_entry" ] || "$fail" entries "no nixos-generation-N.conf in /boot/loader/entries on $host"
  [ "$new_entry" != "$prior_entry" ] \
    || "$fail" entries "newest entry $new_entry equals the prior entry; no new entry was written"
  rssh test -e "$(entry_path "$prior_entry")" 2>/dev/null \
    || "$fail" entries "prior entry $prior_entry is not bootable: $(entry_path "$prior_entry") is missing"
  log entries ok "new entry $new_entry, prior entry $prior_entry still bootable"
}

# The live switch is already healthy here; only persisting it across a reboot failed.
# shellcheck disable=SC2329  # called as $fail by write_boot_entry
boot_entry_unwritten() {
  log "$1" fail "could not write the boot entry: $2; $host runs $toplevel but the next reboot returns to $prior_entry"
  failed_gates+=(boot-entry-not-written)
  finish patched 5
}

if [ "$live" -eq 1 ]; then
  start_switch "$toplevel" \
    || refuse live "could not start $switch_unit.service on $host"
  done_so_far="$done_so_far; live switch started, default still $prior_entry"
  log live ok "switch-to-configuration test started as $switch_unit.service; no reboot: kernel, initrd and modules match the booted system"
else
  write_boot_entry refuse_restoring
  rssh sudo bootctl set-default "$prior_entry" \
    || refuse entries "bootctl set-default $prior_entry failed; loader.conf may already name $new_entry, fix by hand before any reboot"
  rssh sudo bootctl set-oneshot "$new_entry" \
    || refuse_restoring entries "bootctl set-oneshot $new_entry failed"
  done_so_far="$done_so_far; default $prior_entry, one-shot $new_entry"
  log bootonce ok "default=$prior_entry oneshot=$new_entry"

  rc=0
  rssh sudo systemctl reboot >/dev/null 2>&1 || rc=$?
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 255 ]; then
    refuse_restoring reboot "ssh $host sudo systemctl reboot exited $rc"
  fi
  log reboot ok "reboot issued"

  if [ -n "$unlock_via" ]; then
    # G1 already holds --approve, and no one can type at unlock's tty mid-reboot
    unlock_args=(--host "$host" --via "$unlock_via" --approve)
    [ -z "$unlock_jump" ] || unlock_args+=(--jump "$unlock_jump")
    if ! "$DIR/unlock-master.sh" "${unlock_args[@]}"; then
      probe_state="unlock-master.sh --via $unlock_via failed"
      roll_back
    fi
    log unlock ok "unlocked via $unlock_via"
  fi
fi

if ! wait_healthy; then
  if [ "$live" -eq 1 ]; then live_roll_back; fi
  roll_back
fi
log health ok "current-system=$toplevel and health-cmd passed"
if [ "$live" -eq 1 ]; then
  check_switch
  write_boot_entry boot_entry_unwritten
fi

if ! rssh sudo bootctl set-default "$new_entry" >/dev/null; then
  log commit fail "healthy, but bootctl set-default $new_entry failed; the next reboot returns to $prior_entry"
  failed_gates+=(default-not-set)
  finish patched 5
fi
status_out=$(rssh sudo bootctl status 2>/dev/null || true)
default_now=$(sed -n 's/^ *Default Entry: *//p' <<<"$status_out" | head -n1)
if [ "$default_now" != "$new_entry" ]; then
  log confirm fail "bootctl status shows Default Entry '${default_now:-none}', expected $new_entry"
  failed_gates+=(default-not-confirmed)
  finish patched 5
fi
log confirm ok "default is $new_entry"
finish patched 0
