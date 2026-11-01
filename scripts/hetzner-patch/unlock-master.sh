#!/usr/bin/env bash
# Answers the LUKS passphrase prompt of the k3s state volume on a Hetzner master
# that is not on Tailscale yet, reached over plain SSH.
#
# Exit codes: 0 unlocked; 2 refused (bad flags, not approved); 3 no prompt
# within --wait-prompt; 4 not unlocked after --max-attempts; 5 passphrase
# command failed or empty.
set -euo pipefail

readonly PROMPT_MSG="Unlock k3s state volume:"
readonly ASK_DIR="/run/systemd/ask-password"
readonly REPLY_BIN="/run/current-system/sw/lib/systemd/systemd-reply-password"
readonly DEFAULT_PASS_CMD='op item get ifnbgrbsk6ltkwry3g7r4obtwi --fields label=password --reveal'
readonly POLL_PROMPT_SECS=5
readonly POLL_UNLOCK_SECS=2

# Remote probe: prints "unlocked" once the mapper and mount exist, then each
# pending ask file as an "ask-file NAME" marker followed by its contents.
readonly PROBE_CMD="if [ -e /dev/mapper/k3s-state ] && mountpoint -q /var/lib/rancher/k3s; then echo unlocked; fi; for f in $ASK_DIR/ask.*; do [ -f \"\$f\" ] || continue; echo \"ask-file \${f##*/}\"; cat \"\$f\"; done 2>/dev/null; exit 0"

log() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
}

usage() {
  log "usage: unlock-master.sh --host HOST --via public|edge [--jump JUMPHOST] [--approve] [--wait-prompt SECS] [--wait-unlock SECS] [--max-attempts N]"
}

fail_usage() {
  log "error=$1"
  usage
  exit 2
}

valid_host() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._@:-]*$ ]]
}

host=""
via=""
jump=""
approve=0
wait_prompt=600
wait_unlock=120
max_attempts=2

while (( $# > 0 )); do
  case "$1" in
    --host|--via|--jump|--wait-prompt|--wait-unlock|--max-attempts)
      (( $# >= 2 )) || fail_usage "missing value for $1"
      case "$1" in
        --host) host="$2" ;;
        --via) via="$2" ;;
        --jump) jump="$2" ;;
        --wait-prompt) wait_prompt="$2" ;;
        --wait-unlock) wait_unlock="$2" ;;
        --max-attempts) max_attempts="$2" ;;
      esac
      shift 2
      ;;
    --approve)
      approve=1
      shift
      ;;
    *)
      fail_usage "unknown argument: $1"
      ;;
  esac
done

[[ -n "$host" ]] || fail_usage "--host is required"
valid_host "$host" || fail_usage "invalid --host: $host"
case "$via" in
  public)
    [[ -z "$jump" ]] || fail_usage "--jump only applies to --via edge"
    ;;
  edge)
    [[ -n "$jump" ]] || fail_usage "--via edge requires --jump JUMPHOST"
    valid_host "$jump" || fail_usage "invalid --jump: $jump"
    ;;
  *)
    fail_usage "--via must be public or edge, got: $via"
    ;;
esac
[[ "$wait_prompt" =~ ^[0-9]+$ ]] || fail_usage "--wait-prompt must be whole seconds, got: $wait_prompt"
[[ "$wait_unlock" =~ ^[0-9]+$ ]] || fail_usage "--wait-unlock must be whole seconds, got: $wait_unlock"
if ! [[ "$max_attempts" =~ ^[0-9]+$ ]] || (( max_attempts < 1 )); then
  fail_usage "--max-attempts must be at least 1, got: $max_attempts"
fi

ssh_cmd=(ssh -T -o BatchMode=yes -o ConnectTimeout=15)
if [[ "$via" == edge ]]; then
  ssh_cmd+=(-J "$jump")
fi

# Approval gate: decided before the host is touched. --approve, or type
# "unlock" on the tty (UNLOCK_TTY_DEVICE overrides /dev/tty for tests).
approved=0
if (( approve )); then
  approved=1
else
  tty="${UNLOCK_TTY_DEVICE:-/dev/tty}"
  log "event=approval-wait type=unlock tty=$tty"
  answer=""
  if read -r answer 2>/dev/null <"$tty" && [[ "$answer" == unlock ]]; then
    approved=1
  fi
fi
if (( ! approved )); then
  log "status=refused reason=not-approved hint=pass --approve or type unlock on $tty"
  exit 2
fi

PROBE_UNLOCKED=0
PROBE_SOCKET=""

# Runs one probe. Sets PROBE_UNLOCKED and PROBE_SOCKET (the socket of the ask
# file whose Message= matches). Returns 1 when the host cannot be reached.
probe() {
  local out="" rc=0 sock=""
  PROBE_UNLOCKED=0
  PROBE_SOCKET=""
  out="$("${ssh_cmd[@]}" "$host" "$PROBE_CMD" </dev/null 2>/dev/null)" || rc=$?
  if (( rc != 0 )); then
    log "event=probe status=unreachable host=$host ssh_exit=$rc"
    return 1
  fi
  if grep -qx unlocked <<<"$out"; then
    PROBE_UNLOCKED=1
  fi
  sock="$(awk -v want="$PROMPT_MSG" '
    function flush() {
      if (sock != "" && msg == want) { found = found (found == "" ? "" : " ") sock }
      sock = ""; msg = ""
    }
    /^ask-file / { flush(); next }
    /^Socket=/ { sock = substr($0, 8) }
    /^Message=/ { msg = substr($0, 9) }
    END { flush(); print found }
  ' <<<"$out")"
  if [[ "$sock" == *" "* ]]; then
    log "event=probe status=ignored reason=multiple-prompts"
    sock=""
  elif [[ -n "$sock" ]] && ! [[ "$sock" =~ ^/run/systemd/ask-password//?sck\.[A-Za-z0-9]+$ ]]; then
    log "event=probe status=ignored reason=unexpected-socket"
    sock=""
  fi
  PROBE_SOCKET="$sock"
  return 0
}

# Polls until the volume is unlocked or our prompt is pending. Returns 3 on deadline.
await_prompt() {
  local deadline=$(( $(date +%s) + $1 ))
  while :; do
    if probe && { (( PROBE_UNLOCKED )) || [[ -n "$PROBE_SOCKET" ]]; }; then
      return 0
    fi
    if (( $(date +%s) >= deadline )); then
      return 3
    fi
    sleep "$POLL_PROMPT_SECS"
  done
}

# Runs the passphrase command for one attempt and prints its output. Re-run per
# attempt so the source is read at the moment of sending.
fetch_passphrase() {
  local cmd="${UNLOCK_PASSPHRASE_CMD:-$DEFAULT_PASS_CMD}" out="" rc=0
  # stderr is dropped: it can echo arguments, and the exit code is what we log.
  out="$(bash -c "$cmd" 2>/dev/null)" || rc=$?
  if (( rc != 0 )); then
    log "status=passphrase-unavailable reason=command-failed exit=$rc"
    return 1
  fi
  if [[ -z "$out" ]]; then
    log "status=passphrase-unavailable reason=empty-output"
    return 1
  fi
  printf '%s' "$out"
}

# The passphrase travels on stdin only; the remote argv names the socket.
send_passphrase() {
  local sock="$1"
  log "event=send socket=$sock attempt=$attempts host=$host"
  if ! printf '%s' "$pass" | "${ssh_cmd[@]}" "$host" "sudo $REPLY_BIN 1 $sock" >&2; then
    log "event=send status=failed host=$host"
  fi
}

# Returns 0 once unlocked or the prompt moved to a new socket (a wrong passphrase
# re-prompts); returns 1 when neither happens within the window.
await_result() {
  local sock="$1" deadline=$(( $(date +%s) + $2 ))
  while :; do
    if probe && { (( PROBE_UNLOCKED )) || [[ -n "$PROBE_SOCKET" && "$PROBE_SOCKET" != "$sock" ]]; }; then
      return 0
    fi
    if (( $(date +%s) >= deadline )); then
      return 1
    fi
    sleep "$POLL_UNLOCK_SECS"
  done
}

attempts=0
pass=""
while :; do
  await_prompt "$wait_prompt" || {
    log "status=no-prompt waited_secs=$wait_prompt host=$host"
    exit 3
  }

  if (( PROBE_UNLOCKED )); then
    log "status=unlocked host=$host sent=$attempts"
    exit 0
  fi

  if (( attempts >= max_attempts )); then
    log "status=not-unlocked host=$host sent=$attempts wrong passphrase? the prompt is still pending, ask the owner"
    exit 4
  fi

  sock="$PROBE_SOCKET"
  pass="$(fetch_passphrase)" || exit 5
  attempts=$(( attempts + 1 ))
  send_passphrase "$sock"
  unset pass
  await_result "$sock" "$wait_unlock" || true
done
