# Harness for unlock-master.bats. Stubs go first on PATH:
#   ssh          simulates the master's systemd ask-password prompt over SSH
#   date, sleep  a fake clock ($FX/clock), so wait windows cost nothing
#   fake-pass    the passphrase command, answers from $FX/pass.queue
# Everything the script does is recorded under $FX/calls for assertions.

unlock_setup() {
  local tests_dir bash_path real_date
  tests_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  UNLOCK_SCRIPT="$tests_dir/../unlock-master.sh"
  FX="$BATS_TEST_TMPDIR/fx"
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$FX/remote/ask" "$FX/calls" "$BIN"
  printf '%s\n' 1800000000 >"$FX/clock"
  bash_path="$(command -v bash)"
  real_date="$(command -v date)"

  unlock_stub date <<EOF
now="\$(cat "\$UNLOCK_FX/clock")"
case " \$* " in
  *" +%s "*) printf '%s\n' "\$now" ;;
  *) exec "$real_date" -u -d "@\$now" +%Y-%m-%dT%H:%M:%SZ ;;
esac
EOF

  unlock_stub sleep <<'EOF'
now="$(cat "$UNLOCK_FX/clock")"
printf '%s\n' "$((now + $1))" >"$UNLOCK_FX/clock"
printf '%s\n' "$1" >>"$UNLOCK_FX/sleep.log"
EOF

  unlock_stub ssh <<'EOF'
fx="$UNLOCK_FX"
n=$(( $(cat "$fx/ssh.count" 2>/dev/null || echo 0) + 1 ))
printf '%s\n' "$n" >"$fx/ssh.count"
printf '%s\n' "$@" >"$fx/calls/argv.$n"
env >"$fx/calls/env.$n"
cat >"$fx/calls/stdin.$n"
cmd="${*: -1}"
case "$cmd" in
  *systemd-reply-password*)
    sock="${cmd##* }"
    ask="$(grep -l -x "Socket=$sock" "$fx"/remote/ask/ask.* 2>/dev/null | head -n 1)"
    if [[ -z "$ask" ]]; then
      echo "fake-ssh: no live socket $sock" >&2
      exit 1
    fi
    if cmp -s "$fx/remote/passphrase" "$fx/calls/stdin.$n"; then
      : >"$fx/remote/mapper"
      rm -f "$fx"/remote/ask/ask.*
    else
      rm -f "$ask"
      k=$(( $(cat "$fx/remote/wrong" 2>/dev/null || echo 0) + 1 ))
      printf '%s\n' "$k" >"$fx/remote/wrong"
      printf '[Ask]\nSocket=/run/systemd/ask-password//sck.wrong%s\nMessage=Unlock k3s state volume:\n' "$k" \
        >"$fx/remote/ask/ask.wrong$k"
      echo "luksOpen: No key available with this passphrase." >>"$fx/remote/journal"
    fi
    exit 0 ;;
  *mountpoint*)
    probes=$(( $(cat "$fx/remote/probes" 2>/dev/null || echo 0) + 1 ))
    printf '%s\n' "$probes" >"$fx/remote/probes"
    if [[ -e "$fx/remote/mapper" ]]; then echo unlocked; fi
    hide=0
    if [[ -f "$fx/remote/appear-after" ]] && (( probes <= $(cat "$fx/remote/appear-after") )); then
      hide=1
    fi
    if (( ! hide )); then
      for f in "$fx"/remote/ask/ask.*; do
        [[ -f "$f" ]] || continue
        echo "ask-file ${f##*/}"
        cat "$f"
      done
    fi
    exit 0 ;;
  *)
    echo "fake-ssh: unexpected remote command: $cmd" >&2
    exit 98 ;;
esac
EOF

  unlock_stub fake-pass <<'EOF'
fx="$UNLOCK_FX"
n=$(( $(cat "$fx/pass.count" 2>/dev/null || echo 0) + 1 ))
printf '%s\n' "$n" >"$fx/pass.count"
if (( n > $(wc -l <"$fx/pass.queue") )); then
  echo "fake-pass: queue exhausted" >&2
  exit 1
fi
line="$(sed -n "${n}p" "$fx/pass.queue")"
if [[ "$line" == __FAIL__ ]]; then
  echo "fake-pass: command failed" >&2
  exit 1
fi
printf '%s' "$line"
EOF

  export PATH="$BIN:$PATH"
  export UNLOCK_FX="$FX"
  export UNLOCK_TTY_DEVICE="$FX/no-such-tty"
  export UNLOCK_PASSPHRASE_CMD="fake-pass"
  export REAL_DATE="$real_date"
}

# unlock_stub NAME: writes stdin (after a bash shebang) to $BIN/NAME, executable.
unlock_stub() {
  local name="$1" bash_path
  bash_path="$(command -v bash)"
  { printf '#!%s\n' "$bash_path"; cat; } >"$BIN/$name"
  chmod +x "$BIN/$name"
}

# unlock_add_prompt NAME SOCKET [MESSAGE]: a pending ask-password file on the fake master.
unlock_add_prompt() {
  printf '[Ask]\nSocket=%s\nMessage=%s\n' "$2" "${3:-Unlock k3s state volume:}" \
    >"$FX/remote/ask/ask.$1"
}

# unlock_set_passphrase CORRECT [QUEUE_LINE...]: the master's real passphrase,
# and the answers fake-pass gives one per invocation (__FAIL__ = command fails).
unlock_set_passphrase() {
  local correct="$1"
  shift
  printf '%s' "$correct" >"$FX/remote/passphrase"
  : >"$FX/pass.queue"
  local line
  for line in "$@"; do
    printf '%s\n' "$line" >>"$FX/pass.queue"
  done
}

unlock_run() {
  run timeout 60 bash "$UNLOCK_SCRIPT" "$@"
}

unlock_ssh_calls() {
  cat "$FX/ssh.count" 2>/dev/null || echo 0
}

unlock_reply_calls() {
  grep -l systemd-reply-password "$FX"/calls/argv.* 2>/dev/null | wc -l | tr -d ' '
}

unlock_pass_calls() {
  cat "$FX/pass.count" 2>/dev/null || echo 0
}

# unlock_assert_timestamped TEXT: fails unless every line of TEXT starts with an
# ISO 8601 UTC timestamp. Pass "$output" from the test.
unlock_assert_timestamped() {
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if ! [[ "$line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z[[:space:]] ]]; then
      echo "output line lacks an ISO 8601 UTC timestamp: $line"
      return 1
    fi
  done <<<"$1"
}
