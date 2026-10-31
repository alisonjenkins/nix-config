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
         [--unlock-via public|edge] [--health-timeout SECS] [--health-cmd CMD]
         [--no-snapshot-gate] [--dry-run] [--record-file FILE]
  env: HCLOUD_TOKEN (required), KUBECONFIG (optional, enables the node-readiness gate)
  exit: 0 patched and healthy; 1 usage; 2 refused (see output for anything already done);
        3 unhealthy, rolled back; 4 unhealthy and rollback failed
USAGE
}

host="" server_id="" toplevel="" approve=0 unlock_via="" dry_run=0 no_snapshot_gate=0
health_timeout=900 health_cmd=true
record_file="${XDG_STATE_HOME:-${HOME:-}/.local/state}/hetzner-patch/runs.jsonl"
min_esp_mib=60
max_snapshot_age_days=30


usage_error() { log args error "$1"; usage; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --host) host=${2:?--host needs a value}; shift 2 ;;
    --server-id) server_id=${2:?--server-id needs a value}; shift 2 ;;
    --toplevel) toplevel=${2:?--toplevel needs a value}; shift 2 ;;
    --approve) approve=1; shift ;;
    --unlock-via) unlock_via=${2:?--unlock-via needs a value}; shift 2 ;;
    --health-timeout) health_timeout=${2:?--health-timeout needs a value}; shift 2 ;;
    --health-cmd) health_cmd=${2:?--health-cmd needs a value}; shift 2 ;;
    --no-snapshot-gate) no_snapshot_gate=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    --record-file) record_file=${2:?--record-file needs a value}; shift 2 ;;
    *) usage_error "unknown argument: $1" ;;
  esac
done
HP_HOST=${host:--}
[ -n "$host" ] && [ -n "$server_id" ] && [ -n "$toplevel" ] \
  || usage_error "--host, --server-id and --toplevel are required"
case "$unlock_via" in "" | public | edge) ;; *) usage_error "--unlock-via must be public or edge, got $unlock_via" ;; esac
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
    "nix-env --set $toplevel, then $toplevel/bin/switch-to-configuration boot" \
    "check the new boot entry exists and the prior one is still bootable" \
    "bootctl set-default PRIOR, then bootctl set-oneshot NEW" \
    "systemctl reboot${unlock_via:+, then unlock-master.sh --via $unlock_via}" \
    "poll up to ${health_timeout}s for current-system=$toplevel and health-cmd" \
    "healthy: bootctl set-default NEW; unhealthy: rollback.sh (hcloud server reset id=$server_id)"; do
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

log steps refused "patch steps are not implemented yet; nothing on $host was changed"
finish refused 2
