#!/usr/bin/env bats
# Tests for scripts/flash-installer-iso.sh.
#
# Strategy: drive the script end-to-end against a regular tempfile via
# FLASH_ALLOW_FILE=1 + FLASH_SUDO= (no sudo). The script's write/verify and
# strict-uefi MBR-zeroing paths run for real against the file; only the
# block-device validation, lsblk/diskutil, and wipefs/partprobe calls are
# stubbed to no-ops by the test-mode env vars. Real USB enumeration is
# replaced by FLASH_TEST_DEVICES (newline-separated <path>\t<desc>).
#
# Run from repo root:
#   nix run nixpkgs#bats -- scripts/tests/flash-installer-iso.bats

SCRIPT="${BATS_TEST_DIRNAME}/../flash-installer-iso.sh"

setup() {
  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"
  export FLASH_ALLOW_FILE=1
  export FLASH_SUDO=
}

teardown() {
  cd /
  rm -rf "$TMPDIR_TEST"
}

# Build a 2 MiB fixture ISO with distinctive byte patterns at the structurally
# meaningful offsets so tests can verify what the script touched and what it
# left alone:
#   0-445   : 0xAA boot-code stub
#   446-509 : 0xBB hybrid-MBR partition entries (zeroed by --strict-uefi)
#   510-511 : 0x55 0xAA boot signature (must be preserved)
#   512+    : 0xCC body (GPT header territory; must be preserved)
make_fixture_iso() {
  local out="$1"
  python3 - "$out" <<'PY'
import sys
path = sys.argv[1]
size = 2 * 1024 * 1024
buf = bytearray(b'\xCC' * size)
buf[0:446] = b'\xAA' * 446
buf[446:510] = b'\xBB' * 64
buf[510] = 0x55
buf[511] = 0xAA
with open(path, 'wb') as f:
    f.write(buf)
PY
}

byte_at() {
  # byte_at <file> <offset>  → prints decimal value of that byte
  local f="$1" off="$2"
  python3 -c "import sys; f=open(sys.argv[1],'rb'); f.seek(int(sys.argv[2])); sys.stdout.write(str(f.read(1)[0]))" "$f" "$off"
}

# -----------------------------------------------------------------------------
# arg parsing
# -----------------------------------------------------------------------------

@test "too many args → exit 2" {
  run "$SCRIPT" /tmp/dev /tmp/iso /tmp/extra
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "unknown flag → exit 2" {
  run "$SCRIPT" --bogus /tmp/dev
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown flag"* ]]
  [[ "$output" == *"usage:"* ]]
}

@test "--help prints usage and exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage:"* ]]
}

@test "missing ISO file → exit 1 with 'iso not found'" {
  : > target
  run "$SCRIPT" target /does/not/exist.iso
  [ "$status" -eq 1 ]
  [[ "$output" == *"iso not found"* ]]
}

@test "missing device file (FLASH_ALLOW_FILE) → exit 1 with 'file not found'" {
  make_fixture_iso fixture.iso
  run "$SCRIPT" /does/not/exist/target fixture.iso
  [ "$status" -eq 1 ]
  [[ "$output" == *"file not found"* ]]
}

# -----------------------------------------------------------------------------
# ISO auto-discovery
# -----------------------------------------------------------------------------

@test "no ISO in result/iso → exit 1 with helpful message" {
  : > target
  run bash -c "echo yes | '$SCRIPT' target"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no ISO found in ./result/iso"* ]]
}

@test "multiple ISOs in result/iso → exit 1 listing both" {
  mkdir -p result/iso
  : > result/iso/a.iso
  : > result/iso/b.iso
  : > target
  run bash -c "echo yes | '$SCRIPT' target"
  [ "$status" -eq 1 ]
  [[ "$output" == *"multiple ISOs"* ]]
  [[ "$output" == *"a.iso"* ]]
  [[ "$output" == *"b.iso"* ]]
}

@test "single ISO in result/iso → autodiscovered" {
  mkdir -p result/iso
  make_fixture_iso result/iso/installer.iso
  : > target
  run bash -c "echo yes | '$SCRIPT' target"
  [ "$status" -eq 0 ]
  [[ "$output" == *"installer.iso"* ]]
  [[ "$output" == *"OK — bootable ISO written"* ]]
}

# -----------------------------------------------------------------------------
# device enumeration / picker
# -----------------------------------------------------------------------------

@test "--list with no test devices → '(none found)' exit 0" {
  run "$SCRIPT" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removable USB devices:"* ]]
  [[ "$output" == *"(none found)"* ]]
}

@test "--list with FLASH_TEST_DEVICES → enumerates each, exit 0" {
  : > stick-a; : > stick-b
  FLASH_TEST_DEVICES="$(printf '%s\t%s\n%s\t%s' \
    "$PWD/stick-a" "16GB SanDisk Cruzer" \
    "$PWD/stick-b" "32GB Kingston DT")" \
    run "$SCRIPT" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"1) $PWD/stick-a"* ]]
  [[ "$output" == *"SanDisk Cruzer"* ]]
  [[ "$output" == *"2) $PWD/stick-b"* ]]
  [[ "$output" == *"Kingston DT"* ]]
}

@test "no device + no test devices → 'plug in a USB stick' exit 1" {
  make_fixture_iso fixture.iso
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"plug in a USB stick"* ]]
}

@test "no device + picker selects a valid entry → flashes that target" {
  : > stick-a
  : > stick-b
  export FLASH_TEST_DEVICES="$(printf '%s\t%s\n%s\t%s' \
    "$PWD/stick-a" "16GB Stick A" \
    "$PWD/stick-b" "32GB Stick B")"
  # Omit device argument entirely so the picker drives the choice. ISO comes
  # from ./result/iso autodiscovery. Stdin feeds the picker prompt then the
  # confirm prompt.
  mkdir -p result/iso
  make_fixture_iso result/iso/installer.iso
  run bash -c "printf '2\nyes\n' | '$SCRIPT' 2>&1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Selected: $PWD/stick-b"* ]]
  [[ "$output" == *"OK — bootable ISO written to $PWD/stick-b"* ]]
  # stick-a should NOT have been written.
  [ ! -s stick-a ]
  [ -s stick-b ]
}

@test "no device + picker 'q' → exit 1 'aborted'" {
  make_fixture_iso fixture.iso
  : > stick-a
  export FLASH_TEST_DEVICES="$(printf '%s\t%s' "$PWD/stick-a" "16GB Stick A")"
  mkdir -p result/iso; cp fixture.iso result/iso/installer.iso
  run bash -c "echo q | '$SCRIPT' 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"aborted"* ]]
}

@test "no device + picker invalid input → exit 1 'invalid choice'" {
  : > stick-a
  export FLASH_TEST_DEVICES="$(printf '%s\t%s' "$PWD/stick-a" "16GB Stick A")"
  mkdir -p result/iso; make_fixture_iso result/iso/installer.iso
  run bash -c "echo 99 | '$SCRIPT' 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid choice"* ]]
}

# -----------------------------------------------------------------------------
# user prompt (write confirmation)
# -----------------------------------------------------------------------------

@test "non-'yes' prompt response aborts with exit 1" {
  make_fixture_iso fixture.iso
  : > target
  run bash -c "echo no | '$SCRIPT' target fixture.iso"
  [ "$status" -eq 1 ]
  [[ "$output" == *"aborted"* ]]
}

# -----------------------------------------------------------------------------
# happy path: write + verify + strict-uefi
# -----------------------------------------------------------------------------

@test "strict-uefi (default) writes ISO, then zeros MBR partition entries" {
  make_fixture_iso fixture.iso
  : > target
  run bash -c "echo yes | '$SCRIPT' target fixture.iso"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK — bootable ISO written"* ]]
  [[ "$output" == *"strict-uefi: zeroing"* ]]

  # Boot-code (0..445) should match fixture (0xAA).
  [ "$(byte_at target 0)" = "170" ]
  [ "$(byte_at target 445)" = "170" ]

  # MBR partition table (446..509) should now be zero.
  [ "$(byte_at target 446)" = "0" ]
  [ "$(byte_at target 509)" = "0" ]

  # 0x55AA boot signature (510..511) must be preserved.
  [ "$(byte_at target 510)" = "85" ]
  [ "$(byte_at target 511)" = "170" ]

  # GPT body (512+) must be preserved (0xCC).
  [ "$(byte_at target 512)" = "204" ]
  [ "$(byte_at target 1023)" = "204" ]
}

@test "--strict-uefi explicit flag zeros MBR partition entries" {
  make_fixture_iso fixture.iso
  : > target
  run bash -c "echo yes | '$SCRIPT' --strict-uefi target fixture.iso"
  [ "$status" -eq 0 ]
  [ "$(byte_at target 446)" = "0" ]
  [ "$(byte_at target 509)" = "0" ]
  [ "$(byte_at target 510)" = "85" ]
  [ "$(byte_at target 511)" = "170" ]
}

@test "--legacy-bios preserves the hybrid MBR partition entries" {
  make_fixture_iso fixture.iso
  : > target
  run bash -c "echo yes | '$SCRIPT' --legacy-bios target fixture.iso"
  [ "$status" -eq 0 ]
  [[ "$output" != *"strict-uefi: zeroing"* ]]
  # MBR partition entries (446..509) should still be the fixture's 0xBB.
  [ "$(byte_at target 446)" = "187" ]
  [ "$(byte_at target 509)" = "187" ]
  [ "$(byte_at target 510)" = "85" ]
  [ "$(byte_at target 511)" = "170" ]
}

# -----------------------------------------------------------------------------
# BSD-dd compatibility regression
# -----------------------------------------------------------------------------

@test "script does not pass GNU-only flags to dd (BSD compat)" {
  make_fixture_iso fixture.iso
  : > target

  # Shim dd to fail loudly on any GNU-only argument BSD dd rejects. macOS
  # /usr/bin/dd is BSD and lacks `status=none`, `status=progress`,
  # `oflag=direct`, `iflag=direct`, `conv=fsync`. Hitting any of those
  # under sudo on a real Mac silently kills the run, because dd's stderr
  # is consumed by the pv|dd pipeline. Catch it here.
  shim_dir="$(mktemp -d)"
  cat >"$shim_dir/dd" <<'SH'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    status=none|status=progress|oflag=direct|iflag=direct|conv=fsync)
      echo "dd: $arg: illegal argument" >&2
      exit 1
      ;;
  esac
done
real_dd=$(PATH=/usr/bin:/bin command -v dd)
exec "$real_dd" "$@"
SH
  chmod +x "$shim_dir/dd"

  run env PATH="$shim_dir:$PATH" bash -c "echo yes | '$SCRIPT' target fixture.iso 2>&1"
  [ "$status" -eq 0 ]
  [[ "$output" != *"illegal argument"* ]]
  [[ "$output" == *"OK — bootable ISO written"* ]]
}

# -----------------------------------------------------------------------------
# verify-readback failure detection
# -----------------------------------------------------------------------------

@test "SHA mismatch on read-back → exit 1 'MISMATCH'" {
  make_fixture_iso fixture.iso
  : > target

  # Wrap dd so the WRITE invocation produces a corrupted target. We detect
  # the write by `of=target` and divert it to /dev/null after copying a
  # truncated image; the verify dd still reads `target` (which now contains
  # zero/short content) and produces a different sha256.
  shim_dir="$(mktemp -d)"
  cat >"$shim_dir/dd" <<'SH'
#!/usr/bin/env bash
# Forward to real dd, but for the WRITE step (of=<target>) silently corrupt
# the target by writing only the first 4KiB of input.
real_dd=$(PATH=/usr/bin:/bin command -v dd)
out=""
for arg in "$@"; do
  case "$arg" in
    of=*) out="${arg#of=}" ;;
  esac
done
if [ -n "$out" ] && [ -f "$out" ] && [ -w "$out" ] && [ "$out" != "/dev/zero" ]; then
  # write step: truncate input to 4KiB so target sha differs
  exec head -c 4096 | "$real_dd" "$@"
fi
exec "$real_dd" "$@"
SH
  chmod +x "$shim_dir/dd"

  run env PATH="$shim_dir:$PATH" bash -c "echo yes | '$SCRIPT' --legacy-bios target fixture.iso"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISMATCH"* ]]
}
