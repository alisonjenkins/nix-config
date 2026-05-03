#!/usr/bin/env bats
# Tests for scripts/luks-discover.sh.
#
# Strategy: feed the script known-bad lsblk output (the kind that
# tripped the original `pick_luks_device` 4-column awk filter) and
# verify the script still picks out the crypto_LUKS rows. Each test
# writes a fixture to a tempfile and points the script at it via the
# LUKS_DISCOVER_LSBLK_CMD test hook.
#
# Run from repo root:
#   nix run nixpkgs#bats -- scripts/tests/luks-discover.bats

SCRIPT="${BATS_TEST_DIRNAME}/../luks-discover.sh"

setup() {
  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"
}

teardown() {
  cd /
  rm -rf "$TMPDIR_TEST"
}

# Write a faked `lsblk -lnp -o FSTYPE,NAME` output. lsblk pads columns
# with runs of spaces, NOT tabs. Empty FSTYPE rows have no leading
# token at all (lsblk just prints the NAME with leading whitespace).
# We mimic both forms to exercise the regression that motivated the
# fix.
write_lsblk_fixture() {
  local f="$1"
  shift
  printf '%s\n' "$@" > "$f"
}

# -----------------------------------------------------------------------------
# regression: the original 4-column NAME,SIZE,MODEL,FSTYPE filter
# silently dropped these rows. Confirm the new 2-column filter finds
# the LUKS partition in each case.
# -----------------------------------------------------------------------------

@test "Steam Deck NVMe post-disko (empty MODEL on partition rows) → finds /dev/nvme0n1p3" {
  # Mirrors what `lsblk -lnp -o FSTYPE,NAME` prints on a Steam Deck
  # immediately after `disko --mode destroy,format,mount` for
  # ali-steam-deck. Disk has no FSTYPE, p1 (BIOS boot) has no FSTYPE,
  # p2 is vfat, p3 is crypto_LUKS, dm-mapper child is btrfs.
  write_lsblk_fixture lsblk.txt \
    "            /dev/nvme0n1" \
    "            /dev/nvme0n1p1" \
    "vfat        /dev/nvme0n1p2" \
    "crypto_LUKS /dev/nvme0n1p3" \
    "btrfs       /dev/mapper/crypted"

  LUKS_DISCOVER_LSBLK_CMD="cat lsblk.txt" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/nvme0n1p3" ]
}

@test "SATA SSD with multi-word MODEL → still finds /dev/sda3" {
  # The multi-word MODEL ("Samsung SSD 990 PRO 2TB") would have shifted
  # FSTYPE out of $4 in the old filter. The 2-column form is immune.
  write_lsblk_fixture lsblk.txt \
    "            /dev/sda" \
    "            /dev/sda1" \
    "vfat        /dev/sda2" \
    "crypto_LUKS /dev/sda3"

  LUKS_DISCOVER_LSBLK_CMD="cat lsblk.txt" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/sda3" ]
}

# -----------------------------------------------------------------------------
# negative + multi-device cases
# -----------------------------------------------------------------------------

@test "no LUKS device on system → exit 0, empty stdout" {
  write_lsblk_fixture lsblk.txt \
    "            /dev/sda" \
    "ext4        /dev/sda1" \
    "swap        /dev/sda2"

  LUKS_DISCOVER_LSBLK_CMD="cat lsblk.txt" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "two LUKS partitions on different disks → both printed, sorted" {
  write_lsblk_fixture lsblk.txt \
    "            /dev/sdb" \
    "crypto_LUKS /dev/sdb1" \
    "            /dev/nvme0n1" \
    "crypto_LUKS /dev/nvme0n1p3"

  LUKS_DISCOVER_LSBLK_CMD="cat lsblk.txt" run "$SCRIPT"
  [ "$status" -eq 0 ]
  # `sort` puts /dev/nvme0n1p3 before /dev/sdb1 alphabetically.
  [ "$output" = "$(printf '%s\n%s' '/dev/nvme0n1p3' '/dev/sdb1')" ]
}

@test "non-LUKS rows containing the literal string 'crypto_LUKS' do not match" {
  # Defensive: a NAME column whose path happens to contain the string
  # "crypto_LUKS" must not be falsely identified. The filter pins it
  # to $1 (FSTYPE), so the path-substring case can't trigger.
  write_lsblk_fixture lsblk.txt \
    "ext4        /dev/sda1" \
    "vfat        /dev/sdb-crypto_LUKS-decoy"

  LUKS_DISCOVER_LSBLK_CMD="cat lsblk.txt" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "open dm-mapper btrfs (child of LUKS) is NOT mistaken for LUKS itself" {
  # After disko opens the LUKS partition, lsblk shows both the parent
  # crypto_LUKS row AND the dm-mapper btrfs child. Only the parent
  # should appear in the result.
  write_lsblk_fixture lsblk.txt \
    "            /dev/nvme0n1" \
    "crypto_LUKS /dev/nvme0n1p3" \
    "btrfs       /dev/mapper/crypted"

  LUKS_DISCOVER_LSBLK_CMD="cat lsblk.txt" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/nvme0n1p3" ]
}

# -----------------------------------------------------------------------------
# real-tool invocation path (no test hook)
# -----------------------------------------------------------------------------

@test "without LUKS_DISCOVER_LSBLK_CMD the script invokes sudo lsblk" {
  # Stub `sudo` and `lsblk` on PATH so we can prove the default path
  # actually shells out to the real tool name. Our stubs just print
  # one fake LUKS row and exit.
  mkdir bin
  cat > bin/sudo <<'EOF'
#!/usr/bin/env bash
# Strip the leading `sudo` and exec the rest. That keeps the script's
# invocation `sudo lsblk -lnp -o FSTYPE,NAME` honest — we still go
# through a `sudo` binary, just not the privileged one.
exec "$@"
EOF
  cat > bin/lsblk <<'EOF'
#!/usr/bin/env bash
# Verify the args match what the script promises in its comment.
# If anyone changes the script's lsblk invocation, this test will
# trip on the args check before the output check.
expected=(-lnp -o FSTYPE,NAME)
if [ "$#" -ne ${#expected[@]} ]; then
  echo "lsblk stub: arg count mismatch: got $* want ${expected[*]}" >&2
  exit 99
fi
i=0
for a in "$@"; do
  if [ "$a" != "${expected[$i]}" ]; then
    echo "lsblk stub: arg $i mismatch: got $a want ${expected[$i]}" >&2
    exit 99
  fi
  i=$((i + 1))
done
echo "crypto_LUKS /dev/sda1"
EOF
  chmod +x bin/sudo bin/lsblk

  PATH="$PWD/bin:$PATH" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/sda1" ]
}
