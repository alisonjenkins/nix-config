#!/usr/bin/env bats

# ssh, scp, modinfo and sleep are stubs. The ssh stub models a host: a patch is "loaded" between
# insmod and disable, and the check command answers "patched" only while it is loaded.

setup() {
  SD=$BATS_TEST_DIRNAME/..
  W=$BATS_TEST_TMPDIR
  mkdir -p "$W/bin"
  KO=$W/lp_example.ko
  : > "$KO"
  echo boot-1 > "$W/boot_id"
  echo 0 > "$W/transition"
  : > "$W/calls"
  cat > "$W/bin/ssh" <<EOF
#!$(command -v bash)
cmd="\${*: -1}"
echo "ssh \$cmd" >> "$W/calls"
case "\$cmd" in
  *boot_id*) if [ -f "$W/boot.ssh.fails" ] && [ -f "$W/loaded" ]; then exit 255; fi; if [ -f "$W/rebooted" ]; then echo boot-2; else cat "$W/boot_id"; fi ;;
  "uname -r") [ -f "$W/uname.ssh.fails" ] && exit 255; cat "$W/uname" 2>/dev/null || echo 6.18.59 ;;
  *insmod*) [ -f "$W/insmod.fails" ] && exit 1; touch "$W/loaded"; [ ! -f "$W/reboot.on.load" ] || touch "$W/rebooted" ;;
  *livepatch/lp_example/transition*) cat "$W/transition" ;;
  *"tee /sys/kernel/livepatch"*) [ -f "$W/disable.fails" ] || rm -f "$W/loaded" ;;
  *rmmod*) [ -f "$W/rmmod.fails" ] && exit 1; [ -f "$W/disable.fails" ] || rm -f "$W/loaded" ;;
  *CHECK*) if [ -f "$W/loaded" ] || [ -f "$W/stuck" ]; then echo "this is PATCHED"; else echo "this is original"; fi ;;
  *) echo "stub ssh: unexpected: \$cmd" >&2; exit 97 ;;
esac
EOF
  printf '#!/bin/sh\necho "scp $*" >> "%s"\n' "$W/calls" > "$W/bin/scp"
  printf '#!/bin/sh\necho "6.18.59 SMP preempt mod_unload"\n' > "$W/bin/modinfo"
  printf '#!/bin/sh\nexit 0\n' > "$W/bin/sleep"
  chmod +x "$W/bin/"*
  export PATH="$W/bin:$PATH"
}

verify() { run "$SD/verify-on-host.sh" --host h1 --ko "$KO" --check 'CHECK' --expect 'PATCHED' "$@"; }
calls() { grep -n -- "$1" "$W/calls" | head -n1 | cut -d: -f1; }

@test "happy path: loads, sees the change, unloads, reverts, and the host never rebooted" {
  verify
  [ "$status" -eq 0 ]
  [ "$(calls scp)" -lt "$(calls insmod)" ]
  [ "$(calls insmod)" -lt "$(calls 'tee /sys')" ]
  [ "$(calls 'tee /sys')" -lt "$(calls rmmod)" ]
  [ ! -e "$W/loaded" ]
}

@test "a check that already matches before loading is refused: it proves nothing" {
  touch "$W/stuck"
  verify
  [ "$status" -eq 2 ]
  ! grep -q insmod "$W/calls"
}

@test "a kernel that differs from the module's vermagic is refused before copying" {
  echo 6.18.60 > "$W/uname"
  verify
  [ "$status" -eq 2 ]
  ! grep -q '^scp' "$W/calls"
}

@test "insmod failure exits 3 without running the check against the patched host" {
  touch "$W/insmod.fails"
  verify
  [ "$status" -eq 3 ]
  [ "$(grep -c 'CHECK' "$W/calls")" -eq 1 ]
}

@test "a transition that never completes exits 3 and disables the patch" {
  echo 1 > "$W/transition"
  verify --wait 3
  [ "$status" -eq 3 ]
  grep -q 'tee /sys' "$W/calls"
}

@test "a patch that does not change the check exits 4 and is unloaded again" {
  verify --expect 'NEVER-APPEARS'
  [ "$status" -eq 4 ]
  grep -q 'rmmod' "$W/calls"
  [ ! -e "$W/loaded" ]
}

@test "behaviour that does not revert after disabling exits 5" {
  touch "$W/disable.fails"
  verify
  [ "$status" -eq 5 ]
}

@test "a changed boot_id means the host rebooted: exit 6" {
  touch "$W/reboot.on.load"
  verify
  [ "$status" -eq 6 ]
}

@test "--keep leaves the patch loaded and does not unload it" {
  verify --keep
  [ "$status" -eq 0 ]
  [ -e "$W/loaded" ]
  ! grep -q 'rmmod' "$W/calls"
}

@test "missing flags exit 1 with usage" {
  run "$SD/verify-on-host.sh" --host h1
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "a failed boot_id read is an ssh failure (exit 7), not a reboot, and the patch is unloaded" {
  touch "$W/boot.ssh.fails"
  verify
  [ "$status" -eq 7 ]
  [[ "$output" != *"host rebooted"* ]]
  [ ! -e "$W/loaded" ]
}

@test "an unreachable host before loading exits 7, not a bare ssh status" {
  touch "$W/uname.ssh.fails"
  verify
  [ "$status" -eq 7 ]
  ! grep -q insmod "$W/calls"
}
