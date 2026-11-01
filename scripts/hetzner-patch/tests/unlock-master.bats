#!/usr/bin/env bats
# Tests for scripts/hetzner-patch/unlock-master.sh.
#
# The master's k3s state volume waits for a LUKS passphrase after reboot and is
# not on Tailscale until unlocked, so ssh, date, sleep and the passphrase
# command are stubs (see unlock-helpers.bash).
#
# Run from repo root:
#   nix shell nixpkgs#bats -c bats scripts/hetzner-patch/tests/unlock-master.bats

load 'unlock-helpers'

setup() {
  unlock_setup
  # Not exported: an exported canary would show up in the stubs' env dumps.
  CANARY="canary-$$-$RANDOM-$RANDOM"
}

# -----------------------------------------------------------------------------
# prompt detection, approval gate, flags
# -----------------------------------------------------------------------------

@test "no prompt: exits 3 after the wait window and sends nothing" {
  unlock_run --host m1 --via public --approve --wait-prompt 30
  [ "$status" -eq 3 ]
  [[ "$output" == *"status=no-prompt"* ]]
  [ "$(unlock_reply_calls)" -eq 0 ]
  [ "$(( $(cat "$FX/clock") - 1800000000 ))" -ge 30 ]
  unlock_assert_timestamped "$output"
}

@test "prompt pending, no --approve and no tty: exits 2 before any ssh call" {
  unlock_add_prompt a "/run/systemd/ask-password//sck.one"
  unlock_run --host m1 --via public
  [ "$status" -eq 2 ]
  [ "$(unlock_ssh_calls)" -eq 0 ]
  [ "$(unlock_reply_calls)" -eq 0 ]
  unlock_assert_timestamped "$output"
}

@test "interactive approval: typing unlock on the tty approves" {
  printf 'unlock\n' >"$FX/tty"
  UNLOCK_TTY_DEVICE="$FX/tty"
  unlock_run --host m1 --via public --wait-prompt 5
  [ "$status" -eq 3 ]
  [ "$(unlock_ssh_calls)" -ge 1 ]
}

@test "interactive approval: any other answer refuses with zero ssh calls" {
  printf 'yes\n' >"$FX/tty"
  UNLOCK_TTY_DEVICE="$FX/tty"
  unlock_run --host m1 --via public --wait-prompt 5
  [ "$status" -eq 2 ]
  [ "$(unlock_ssh_calls)" -eq 0 ]
}

@test "already unlocked: exits 0 and sends nothing" {
  : >"$FX/remote/mapper"
  unlock_run --host m1 --via public --approve
  [ "$status" -eq 0 ]
  [ "$(unlock_reply_calls)" -eq 0 ]
  unlock_assert_timestamped "$output"
}

@test "a pending prompt for another LUKS device is not ours: exits 3, sends nothing" {
  unlock_add_prompt a "/run/systemd/ask-password//sck.other" "Please enter passphrase for disk root:"
  unlock_run --host m1 --via public --approve --wait-prompt 5
  [ "$status" -eq 3 ]
  [ "$(unlock_reply_calls)" -eq 0 ]
}

@test "--via edge without --jump: exits 2 with usage and no ssh call" {
  unlock_run --host m1 --via edge --approve
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
  [ "$(unlock_ssh_calls)" -eq 0 ]
  unlock_assert_timestamped "$output"
}

@test "--via edge --jump J: ssh argv carries -J J" {
  unlock_run --host m1 --via edge --jump edge1 --approve --wait-prompt 5
  [ "$status" -eq 3 ]
  [ "$(sed -n '/^-J$/{n;p}' "$FX/calls/argv.1")" = "edge1" ]
  grep -qx 'm1' "$FX/calls/argv.1"
}

@test "--via public: ssh argv carries no -J" {
  unlock_run --host m1 --via public --approve --wait-prompt 5
  [ "$status" -eq 3 ]
  if grep -qx -- '-J' "$FX/calls/argv.1"; then
    echo "public path must not use a jump host"
    return 1
  fi
}

@test "unknown flag: exits 2 with usage" {
  unlock_run --host m1 --via public --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
  [ "$(unlock_ssh_calls)" -eq 0 ]
  unlock_assert_timestamped "$output"
}

# -----------------------------------------------------------------------------
# sending the passphrase, attempt bounds, passphrase command failures
# -----------------------------------------------------------------------------

@test "happy path: sends once to the socket of our ask file and exits 0" {
  unlock_set_passphrase "$CANARY" "$CANARY"
  unlock_add_prompt a "/run/systemd/ask-password//sck.other" "Please enter passphrase for disk root:"
  unlock_add_prompt b "/run/systemd/ask-password//sck.ours"
  unlock_run --host m1 --via public --approve
  [ "$status" -eq 0 ]
  [ "$(unlock_reply_calls)" -eq 1 ]
  [ "$(unlock_pass_calls)" -eq 1 ]
  local argv
  argv="$(unlock_reply_argv)"
  [[ "$(tail -n 1 "$argv")" == *" 1 /run/systemd/ask-password//sck.ours" ]]
  printf '%s' "$CANARY" >"$FX/expected"
  cmp -s "$FX/expected" "$(unlock_call_stdin "$argv")"
  unlock_assert_timestamped "$output"
}

@test "wrong then right: two sends, the second to the re-prompt's socket, exits 0" {
  unlock_set_passphrase "$CANARY" "wrong-$RANDOM" "$CANARY"
  unlock_add_prompt a "/run/systemd/ask-password//sck.one"
  unlock_run --host m1 --via public --approve
  [ "$status" -eq 0 ]
  [ "$(unlock_reply_calls)" -eq 2 ]
  [ "$(unlock_pass_calls)" -eq 2 ]
  local second
  second="$(grep -l systemd-reply-password "$FX"/calls/argv.* | sort | tail -n 1)"
  [[ "$(tail -n 1 "$second")" == *"sck.wrong1" ]]
  printf '%s' "$CANARY" >"$FX/expected"
  cmp -s "$FX/expected" "$(unlock_call_stdin "$second")"
}

@test "always wrong: exits 4 after exactly --max-attempts sends, prompt still pending" {
  unlock_set_passphrase "$CANARY" "wrong-1" "wrong-2" "wrong-3"
  unlock_add_prompt a "/run/systemd/ask-password//sck.one"
  unlock_run --host m1 --via public --approve
  [ "$status" -eq 4 ]
  [ "$(unlock_reply_calls)" -eq 2 ]
  [ "$(unlock_pass_calls)" -eq 2 ]
  [[ "$output" == *"prompt is still pending"* ]]
  unlock_assert_timestamped "$output"
}

@test "--max-attempts 1 with a wrong passphrase: one send, exits 4" {
  unlock_set_passphrase "$CANARY" "wrong-1" "$CANARY"
  unlock_add_prompt a "/run/systemd/ask-password//sck.one"
  unlock_run --host m1 --via public --approve --max-attempts 1
  [ "$status" -eq 4 ]
  [ "$(unlock_reply_calls)" -eq 1 ]
}

@test "already unlocked before any send: exits 0, no passphrase command run" {
  : >"$FX/remote/mapper"
  unlock_set_passphrase "$CANARY" "$CANARY"
  unlock_add_prompt a "/run/systemd/ask-password//sck.one"
  unlock_run --host m1 --via public --approve
  [ "$status" -eq 0 ]
  [ "$(unlock_reply_calls)" -eq 0 ]
  [ "$(unlock_pass_calls)" -eq 0 ]
}

@test "passphrase command fails: exits 5 and nothing is sent" {
  unlock_set_passphrase "$CANARY" "__FAIL__"
  unlock_add_prompt a "/run/systemd/ask-password//sck.one"
  unlock_run --host m1 --via public --approve
  [ "$status" -eq 5 ]
  [ "$(unlock_reply_calls)" -eq 0 ]
  unlock_assert_timestamped "$output"
}

@test "passphrase command prints nothing: exits 5 and nothing is sent" {
  unlock_set_passphrase "$CANARY" ""
  unlock_add_prompt a "/run/systemd/ask-password//sck.one"
  unlock_run --host m1 --via public --approve
  [ "$status" -eq 5 ]
  [ "$(unlock_reply_calls)" -eq 0 ]
}

@test "passphrase secrecy: the canary reaches only a reply's stdin" {
  unlock_set_passphrase "$CANARY" "wrong-1" "$CANARY"
  unlock_add_prompt a "/run/systemd/ask-password//sck.one"
  unlock_run --host m1 --via public --approve
  [ "$status" -eq 0 ]
  [[ "$output" != *"$CANARY"* ]]
  local f n
  for f in "$FX"/calls/argv.* "$FX"/calls/env.*; do
    if grep -qF -- "$CANARY" "$f"; then
      echo "canary leaked into $f"
      return 1
    fi
  done
  for f in "$FX"/calls/stdin.*; do
    if grep -qF -- "$CANARY" "$f"; then
      n="${f##*.}"
      if ! grep -q systemd-reply-password "$FX/calls/argv.$n"; then
        echo "canary sent on a non-reply ssh call: $f"
        return 1
      fi
    fi
  done
  local last
  last="$(grep -l systemd-reply-password "$FX"/calls/argv.* | sort | tail -n 1)"
  grep -qF -- "$CANARY" "$(unlock_call_stdin "$last")"
}
