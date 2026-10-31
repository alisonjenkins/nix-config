# shellcheck shell=bash disable=SC2034,SC2154
# Shared bats harness for the hetzner-patch scripts.
#
# Every external tool the scripts call (ssh, nix, hcloud, kubectl, sleep, date) is a stub that
# appends its invocation to $FAKE_CALLLOG and answers from a rules file the test controls.
# The scripts run with a hermetic PATH (stubs + a symlink farm of coreutils), so a real ssh,
# nix or hcloud can never be reached.

HOST=h1.example
SID=4242
TOP=/nix/store/aaaa-nixos-system-new
PRIOR_GEN=/nix/store/bbbb-nixos-system-old
PRIOR_ID=nixos-generation-2.conf
NEW_ID=nixos-generation-10.conf
TOKEN=tok-SECRET-0123456789
CLOCK0=1793000000

TS_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z '
MUT_RE='nix copy|switch-to-configuration|systemctl reboot|bootctl set-|nix-env|register-validity|bash -s|server reset'

_write_stub() {
  local name=$1
  {
    printf '#!%s\n' "$BASH_BIN"
    cat <<'EOF'
name=${0##*/}
args="$*"
printf '%s %s\n' "$name" "$args" >> "$FAKE_CALLLOG"
state=$(cat "$FAKE_DIR/state")
case "$name" in
  sleep)
    n=$(cat "$FAKE_DIR/sleeps" 2>/dev/null || echo 0)
    echo $((n + 1)) > "$FAKE_DIR/sleeps"
    [ "$n" -lt 5000 ] || { echo "stub sleep: runaway loop" >&2; exit 99; }
    echo $(($(cat "$FAKE_DIR/clock") + $1)) > "$FAKE_DIR/clock"
    exit 0 ;;
  hcloud)
    case "$1 $2" in
      "server describe" | "image list" | "server reset") ;;
      *) echo "$args" >> "$FAKE_DIR/FORBIDDEN"
         echo "forbidden hcloud call: $args" >&2; exit 99 ;;
    esac
    [ -n "${HCLOUD_TOKEN:-}" ] || { echo "hcloud: no token" >&2; exit 1; } ;;
  ssh)
    case " $args " in *" -n "*) ;; *) cat >/dev/null ;; esac ;;
esac
rules="$FAKE_DIR/$name.rules"
if [ -f "$rules" ]; then
  while IFS=$'\037' read -r when glob rc out max; do
    [ "$when" = any ] || case " $when " in *" $state "*) ;; *) continue ;; esac
    # shellcheck disable=SC2254
    case "$args" in $glob) ;; *) continue ;; esac
    if [ -n "${max:-}" ]; then
      key="$FAKE_DIR/count.$(printf '%s' "$when$glob" | cksum | cut -d' ' -f1)"
      used=$(cat "$key" 2>/dev/null || echo 0)
      [ "$used" -lt "$max" ] || continue
      echo $((used + 1)) > "$key"
    fi
    [ -z "$out" ] || printf '%b\n' "$out"
    [ "$name" != hcloud ] || [ "$1 $2" != "server reset" ] || echo reset > "$FAKE_DIR/state"
    [ "$name" != ssh ] || case "$args" in *"systemctl reboot"*) [ "$state" != pre ] || echo post > "$FAKE_DIR/state" ;; esac
    exit "$rc"
  done < "$rules"
fi
echo "stub $name: no rule for: $args" >&2
exit 97
EOF
  } > "$STUBS/$name"
  chmod +x "$STUBS/$name"
}

# rule NAME WHEN GLOB RC OUTPUT [MAXUSES]: later rules win; WHEN is any or a list of pre/post/reset.
rule() {
  local name=$1 when=$2 glob=$3 rc=$4 out=${5:-} max=${6:-}
  local f="$FAKE_DIR/$name.rules"
  { printf '%s\037%s\037%s\037%s\037%s\n' "$when" "$glob" "$rc" "$out" "$max"; [ ! -f "$f" ] || cat "$f"; } > "$f.new"
  mv "$f.new" "$f"
}

happy_rules() {
  local created
  created=$("$REAL_DATE" -u -d "@$((CLOCK0 - 10 * 86400))" +%Y-%m-%dT%H:%M:%S+00:00)
  rule ssh any '* sudo bootctl status' 0 "Current Entry: $PRIOR_ID\nDefault Entry: $NEW_ID"
  rule ssh any '* ls /boot/loader/entries' 0 "nixos-generation-1.conf\nnixos-generation-2.conf\nnixos-generation-9.conf\n$NEW_ID\nnixos-generation-10-specialisation-x.conf\nloader.conf"
  rule ssh any '* df --output=avail -B1M /boot' 0 'Avail\n  120M'
  rule ssh pre '* readlink /run/current-system' 0 "$PRIOR_GEN"
  rule ssh reset '* readlink /run/current-system' 0 "$PRIOR_GEN"
  rule ssh post '* readlink /run/current-system' 0 "$TOP"
  rule ssh any '* nix path-info --all*' 0 598
  rule ssh any '* nix path-info /run/current-system' 0 ''
  rule ssh any '* test -e /nix/var/nix/profiles/system' 0 ''
  rule ssh any "* test -e /boot/loader/entries/$PRIOR_ID" 0 ''
  rule ssh any '* test -e /boot/EFI/Linux/nixos.efi' 0 ''
  rule ssh any '* sudo nix-env -p /nix/var/nix/profiles/system --set*' 0 ''
  rule ssh any '*switch-to-configuration boot' 0 ''
  rule ssh any '* sudo bootctl set-default*' 0 ''
  rule ssh any '* sudo bootctl set-oneshot*' 0 ''
  rule ssh any '* sudo systemctl reboot' 255 ''
  rule ssh any '* true' 0 ''
  rule ssh any '* bash -s -- /nix/store' 0 'REGISTRATION'
  rule ssh any '* sudo nix-store --register-validity' 0 ''
  rule nix any "path-info $TOP" 0 ''
  rule nix any "copy --no-check-sigs --to ssh-ng://$HOST $TOP" 0 ''
  rule hcloud any "server describe $SID -o json" 0 '{"status":"running"}'
  rule hcloud any "server reset $SID" 0 ''
  rule hcloud any 'image list --type snapshot -o json' 0 \
    "[{\"id\":7,\"created\":\"$created\",\"created_from\":{\"id\":$SID,\"name\":\"m\"}}]"
  rule kubectl any 'get nodes --no-headers' 0 'n1   Ready   control-plane   9d   v1.31'
}

base_setup() {
  BASH_BIN=$(command -v bash)
  REAL_DATE=$(command -v date)
  export REAL_DATE
  FAKE_DIR="$BATS_TEST_TMPDIR/fake"
  STUBS="$FAKE_DIR/bin"
  FARM="$FAKE_DIR/farm"
  SD="$BATS_TEST_TMPDIR/scripts"
  REC="$BATS_TEST_TMPDIR/runs.jsonl"
  mkdir -p "$STUBS" "$FARM" "$SD"
  export FAKE_DIR
  export FAKE_CALLLOG="$FAKE_DIR/calls.log"
  : > "$FAKE_CALLLOG"
  echo "$CLOCK0" > "$FAKE_DIR/clock"
  echo pre > "$FAKE_DIR/state"
  local t p
  for t in bash jq sed grep sort tail head tr wc mktemp rm mkdir dirname basename readlink ls env cp cat cut awk tee cksum mv; do
    p=$(command -v "$t") || { echo "harness: tool $t not found" >&2; return 1; }
    ln -sf "$p" "$FARM/$t"
  done
  for t in ssh nix hcloud kubectl sleep date; do _write_stub "$t"; done
  cat > "$STUBS/date" <<EOF
#!$BASH_BIN
for a in "\$@"; do [ "\$a" = -d ] && exec "$REAL_DATE" "\$@"; done
clock=\$(cat "$FAKE_DIR/clock")
case "\$*" in
  *+%s*) echo "\$clock" ;;
  *) exec "$REAL_DATE" -u -d "@\$clock" "\${@: -1}" ;;
esac
EOF
  TPATH="$STUBS:$FARM"
  export HCLOUD_TOKEN=$TOKEN
  export KUBECONFIG="$BATS_TEST_TMPDIR/kubeconfig"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  happy_rules
  FORBIDDEN="$FAKE_DIR/FORBIDDEN"
}

install_scripts() {
  local here=$BATS_TEST_DIRNAME/..
  local f
  for f in "$@"; do install -m 0755 "$here/$f" "$SD/$f"; done
  printf '# stub register-store\n' > "$SD/register-store.sh"
  cat > "$SD/unlock-master.sh" <<EOF
#!$BASH_BIN
echo "unlock-master.sh \$*" >> "$FAKE_CALLLOG"
exit "\$(cat "$FAKE_DIR/unlock.rc" 2>/dev/null || echo 0)"
EOF
  chmod +x "$SD/unlock-master.sh"
}

stub_rollback() {
  cat > "$SD/rollback.sh" <<EOF
#!$BASH_BIN
echo "rollback.sh \$*" >> "$FAKE_CALLLOG"
exit $1
EOF
  chmod +x "$SD/rollback.sh"
}

base_teardown() {
  if [ -e "$FORBIDDEN" ]; then
    echo "FORBIDDEN hcloud call(s) seen:" >&2
    cat "$FORBIDDEN" >&2
    return 1
  fi
}

# run_script SCRIPT ARGS...: hermetic PATH, merged stdout+stderr in $output.
run_script() {
  local s=$1
  shift
  run env PATH="$TPATH" "$BASH_BIN" "$SD/$s" "$@"
}

called() { grep -Eq -- "$1" "$FAKE_CALLLOG"; }

never_called() {
  if grep -En -- "$1" "$FAKE_CALLLOG"; then
    echo "expected no call matching: $1" >&2
    return 1
  fi
}

assert_order() {
  local prev=0 pat n
  for pat in "$@"; do
    n=$(tail -n +$((prev + 1)) "$FAKE_CALLLOG" | grep -En -- "$pat" | head -n1 | cut -d: -f1 || true)
    if [ -z "$n" ]; then
      echo "call matching '$pat' not found after log line $prev" >&2
      cat "$FAKE_CALLLOG" >&2
      return 1
    fi
    prev=$((prev + n))
  done
}

assert_timestamped() {
  local line
  while IFS= read -r line; do
    [[ $line =~ $TS_RE ]] || { echo "line without ISO 8601 UTC prefix: $line" >&2; return 1; }
  done <<<"$output"
}
