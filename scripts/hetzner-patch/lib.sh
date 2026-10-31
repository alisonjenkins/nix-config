# shellcheck shell=bash
# Shared helpers for patch-node.sh and rollback.sh. Sourced, not executed.

HP_HOST=-

hp_ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# log STEP RESULT [MESSAGE]: one line on stderr, ISO 8601 UTC time first.
log() {
  printf '%s host=%s step=%s result=%s msg="%s"\n' "$(hp_ts)" "$HP_HOST" "$1" "$2" "${3:-}" >&2
}

# rssh CMD...: run on $HP_HOST without reading stdin.
rssh() { ssh -o BatchMode=yes -o ConnectTimeout=10 -n "$HP_HOST" "$@"; }
