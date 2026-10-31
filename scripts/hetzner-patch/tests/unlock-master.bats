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
