#!/usr/bin/env bash
set -euo pipefail

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$DIR/lib.sh"

usage() {
  cat >&2 <<'USAGE'
usage: rollback.sh --host HOST --server-id ID --expect-generation STOREPATH [--wait SECS]
  Hard-resets the Hetzner server (HCLOUD_TOKEN in env), waits for SSH and verifies
  /run/current-system equals STOREPATH. Exit 0 ok, 4 if it did not come back on it.
USAGE
}

host="" server_id="" expect="" wait_secs=300
poll_interval=5

while [ $# -gt 0 ]; do
  case "$1" in
    --host) host=${2:?}; shift 2 ;;
    --server-id) server_id=${2:?}; shift 2 ;;
    --expect-generation) expect=${2:?}; shift 2 ;;
    --wait) wait_secs=${2:?}; shift 2 ;;
    *) log args error "unknown argument: $1"; usage; exit 1 ;;
  esac
done
# shellcheck disable=SC2034
HP_HOST=${host:--}
if [ -z "$host" ] || [ -z "$server_id" ] || [ -z "$expect" ]; then
  log args error "--host, --server-id and --expect-generation are required"
  usage
  exit 1
fi
if [ -z "${HCLOUD_TOKEN:-}" ]; then
  log args error "HCLOUD_TOKEN is not set"
  exit 1
fi

fail() {
  log verify failed "$1"
  log recovery manual "automatic rollback failed for server $server_id; recover by hand in this order:"
  log recovery manual "1. Hetzner web console for server $server_id: watch the boot and pick entry $expect"
  log recovery manual "2. rescue mode: boot the rescue system, mount the ESP and root, inspect /boot/loader"
  log recovery manual "3. last resort: restore the most recent snapshot of server $server_id"
  exit 4
}

log reset start "hcloud server reset id=$server_id"
if ! hcloud server reset "$server_id" >/dev/null; then
  fail "hcloud server reset id=$server_id failed"
fi

# The failed generation's link is still the profile's current one; repoint it at what booted.
# Best effort: boot is already correct, so a failure here warns instead of failing the rollback.
align_profile() {
  local listing gen
  # shellcheck disable=SC2016  # the remote shell must expand $l, not this one
  if ! listing=$(rssh 'for l in /nix/var/nix/profiles/system-*-link; do printf "%s %s\n" "$l" "$(readlink -f "$l")"; done' 2>/dev/null); then
    log profile warn "could not list the system profile generations; profile may still point at the failed one"
    return 0
  fi
  gen=$(printf '%s\n' "$listing" | awk -v want="$expect" '$2 == want { n = $1; sub(/.*system-/, "", n); sub(/-link$/, "", n); print n }' | sort -n | tail -n 1)
  if [ -z "$gen" ]; then
    log profile warn "no system profile generation links to $expect; profile may still point at the failed one"
    return 0
  fi
  if rssh sudo nix-env -p /nix/var/nix/profiles/system --switch-generation "$gen" >/dev/null 2>&1; then
    log profile ok "system profile switched to generation $gen"
  else
    log profile warn "nix-env --switch-generation $gen failed; profile may still point at the failed one"
  fi
}

deadline=$(($(date +%s) + wait_secs))
got=""
while :; do
  if got=$(rssh readlink /run/current-system 2>/dev/null) && [ "$got" = "$expect" ]; then
    log verify ok "on expected generation $expect"
    align_profile
    exit 0
  fi
  [ "$(date +%s)" -lt "$deadline" ] || break
  sleep "$poll_interval"
done

if [ -n "$got" ]; then
  fail "ssh answers but current-system=$got expected=$expect after ${wait_secs}s"
fi
fail "no ssh answer from $host within ${wait_secs}s after reset"
