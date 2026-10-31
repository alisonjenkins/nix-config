#!/usr/bin/env bash
# Prove a livepatch module on a running host: the behaviour changes while it is loaded, reverts
# when it is not, and the host never reboots.
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: verify-on-host.sh --host HOST --ko FILE.ko --check 'CMD' --expect REGEX [--wait SECS] [--keep]
  CMD runs on HOST (ssh). Its output must NOT match REGEX before the patch, must match it while the
  patch is loaded, and must not match again after the patch is disabled and unloaded.
  --keep leaves the patch loaded (the revert step is skipped).
  exit: 0 proven; 1 usage; 2 refused before loading (kernel mismatch, or CMD already matches);
        3 load or transition failed; 4 CMD did not change; 5 did not revert or unload;
        6 the host rebooted
USAGE
}

log() { printf '%s host=%s step=%s result=%s msg="%s"\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${host:--}" "$1" "$2" "${3:-}" >&2; }

host="" ko="" check="" expect="" wait_secs=30 keep=0
while [ $# -gt 0 ]; do
  case "$1" in
    --host) host=${2:?}; shift 2 ;;
    --ko) ko=${2:?}; shift 2 ;;
    --check) check=${2:?}; shift 2 ;;
    --expect) expect=${2:?}; shift 2 ;;
    --wait) wait_secs=${2:?}; shift 2 ;;
    --keep) keep=1; shift ;;
    *) log args error "unknown argument: $1"; usage; exit 1 ;;
  esac
done
if [ -z "$host" ] || [ -z "$ko" ] || [ -z "$check" ] || [ -z "$expect" ]; then
  log args error "--host, --ko, --check and --expect are required"
  usage
  exit 1
fi
[ -f "$ko" ] || { log args error "no such module: $ko"; exit 1; }

name=$(basename "$ko" .ko)
name=${name//-/_}
sysfs=/sys/kernel/livepatch/$name
remote_ko=/tmp/$name.ko
rssh() { ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" "$@"; }

wait_transition() {
  local t
  for _ in $(seq 1 "$wait_secs"); do
    t=$(rssh "cat $sysfs/transition" 2>/dev/null || echo 1)
    [ "$t" = 0 ] && return 0
    sleep 1
  done
  return 1
}

# Disable first: a livepatch module cannot be removed while it is enabled.
unload() {
  rssh "echo 0 | sudo tee $sysfs/enabled >/dev/null" 2>/dev/null || true
  wait_transition || true
  rssh "sudo rmmod $name" 2>/dev/null || { log unload warn "rmmod $name failed"; return 1; }
  rssh "rm -f $remote_ko" 2>/dev/null || true
}

want=$(modinfo -F vermagic "$ko" | awk '{ print $1 }')
have=$(rssh "uname -r")
if [ "$want" != "$have" ]; then
  log kernel refused "module is built for $want, host runs $have"
  exit 2
fi
boot_before=$(rssh "cat /proc/sys/kernel/random/boot_id")

if before=$(rssh "$check" 2>&1) && grep -Eq -- "$expect" <<<"$before"; then
  log before refused "the check already matches /$expect/ without the patch, so it proves nothing"
  exit 2
fi
log before ok "check does not match /$expect/ yet"

scp -q -o BatchMode=yes "$ko" "$host:$remote_ko"
if ! rssh "sudo insmod $remote_ko"; then
  log load failed "insmod $remote_ko failed"
  exit 3
fi
if ! wait_transition; then
  log load failed "transition of $name did not finish in ${wait_secs}s; disabling it"
  unload || true
  exit 3
fi
log load ok "$name loaded, transition complete"

after=$(rssh "$check" 2>&1 || true)
if ! grep -Eq -- "$expect" <<<"$after"; then
  log check failed "check output does not match /$expect/ with the patch loaded; unloading"
  unload || true
  exit 4
fi
log check ok "behaviour changed: $after"

if [ "$(rssh "cat /proc/sys/kernel/random/boot_id")" != "$boot_before" ]; then
  log boot failed "boot_id changed: the host rebooted"
  exit 6
fi

if [ "$keep" -eq 1 ]; then
  log revert skipped "--keep: $name stays loaded"
  exit 0
fi

unload || { log revert failed "could not unload $name"; exit 5; }
reverted=$(rssh "$check" 2>&1 || true)
if grep -Eq -- "$expect" <<<"$reverted"; then
  log revert failed "check still matches /$expect/ after unloading"
  exit 5
fi
if [ "$(rssh "cat /proc/sys/kernel/random/boot_id")" != "$boot_before" ]; then
  log boot failed "boot_id changed: the host rebooted"
  exit 6
fi
log revert ok "behaviour reverted, boot_id unchanged"
