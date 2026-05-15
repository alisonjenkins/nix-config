#!/usr/bin/env bash
# Flash the installer ISO to a USB device and verify the write byte-for-byte.
# Works on Linux (sdX, nvmeXnY) and macOS (/dev/diskN, auto-promoted to rdiskN).
#
# Usage:
#   scripts/flash-installer-iso.sh [flags] [<device> [<iso>]]
#
#   <device>          target block device (all data lost). If omitted, the
#                     script enumerates removable USB devices and prompts you
#                     to pick one.
#                       Linux: /dev/sdb, /dev/nvme0n1, ...
#                       macOS: /dev/disk2 (auto-promoted to /dev/rdisk2)
#   <iso>             path to ISO (default: ./result/iso/*.iso)
#
#   --list            enumerate removable USB devices and exit 0.
#   --strict-uefi     default. After dd, zero out the hybrid-MBR partition
#                     entries while keeping the 0x55AA boot signature and the
#                     GPT untouched. Avoids firmware that rejects the
#                     isohybrid layout (Steam Deck, some OEM UEFI) and silences
#                     fdisk's "does not start on physical sector boundary"
#                     warning that comes from the unaligned MBR view.
#   --legacy-bios     opt out of strict-uefi and keep the hybrid MBR so the
#                     stick can boot a legacy-BIOS box.
#
# Test hooks (only set in tests):
#   FLASH_ALLOW_FILE=1   accept a regular file as the target (skips block-device
#                        validation + platform-specific device tooling). The
#                        write/verify/strict-uefi paths still run end-to-end
#                        against the file.
#   FLASH_SUDO=          empty string to disable sudo (run dd as the current
#                        user). Defaults to "sudo".
#   FLASH_TEST_DEVICES   newline-separated "<path>\t<description>" entries that
#                        replace real USB enumeration in test mode.
#
# Exits non-zero on any failure including a SHA256 mismatch on read-back.

set -euo pipefail

OS=$(uname -s)
case "$OS" in
  Linux|Darwin) ;;
  *) echo "unsupported OS: $OS (Linux or Darwin only)" >&2; exit 2 ;;
esac

FLASH_ALLOW_FILE="${FLASH_ALLOW_FILE:-0}"
SUDO="${FLASH_SUDO-sudo}"

usage() {
  cat >&2 <<EOF
usage: $0 [--legacy-bios|--strict-uefi] [--list] [--trace] [<device> [<iso>]]
EOF
}

STRICT_UEFI=1
LIST_ONLY=0
TRACE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --legacy-bios) STRICT_UEFI=0; shift ;;
    --strict-uefi) STRICT_UEFI=1; shift ;;
    --list) LIST_ONLY=1; shift ;;
    --trace) TRACE=1; shift ;;
    --help|-h) usage; exit 0 ;;
    --) shift; break ;;
    -*) echo "unknown flag: $1" >&2; usage; exit 2 ;;
    *) break ;;
  esac
done

# When --trace is on (or FLASH_TRACE=1) every command is logged to stderr
# with `set -x`. Output is verbose but invaluable when the script silently
# bails out in the dd pipeline.
if [ "$TRACE" = "1" ] || [ "${FLASH_TRACE:-0}" = "1" ]; then
  export PS4='+ ${BASH_SOURCE##*/}:${LINENO}> '
  set -x
fi

# Trap any unexpected exit and print the LINENO + exit code so silent
# failures (pipefail killing the script under `set -e`) are diagnosed.
trap 'rc=$?; if [ $rc -ne 0 ]; then echo "::script exited with code $rc at line $LINENO" >&2; fi' EXIT

if [ $# -gt 2 ]; then
  usage
  exit 2
fi

DEV=${1:-}
ISO=${2:-}

# Portable file size + sha256 helpers — detected by tool availability, not
# OS, so a Nix coreutils shipped onto macOS still works.
file_size() {
  # `wc -c < file` is POSIX and identical across BSD/GNU. Trim leading spaces
  # that BSD wc emits.
  local n
  n=$(wc -c < "$1")
  echo "${n// /}"
}
if command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum "$@" | awk '{print $1}'; }
else
  sha256() { shasum -a 256 "$@" | awk '{print $1}'; }
fi

# Platform-specific device tooling. FLASH_ALLOW_FILE=1 swaps in no-op
# implementations so tests can exercise the write/verify/strict-uefi flow
# against a regular tempfile.
if [ "$FLASH_ALLOW_FILE" = "1" ]; then
  enumerate_devices() {
    # Output format: "<device-path>\t<description>" per line.
    if [ -n "${FLASH_TEST_DEVICES:-}" ]; then
      printf '%s\n' "$FLASH_TEST_DEVICES"
    fi
  }
  validate_device() {
    if [ ! -e "$DEV" ]; then
      echo "file not found: $DEV" >&2
      exit 1
    fi
  }
  show_target() { ls -l "$DEV"; }
  unmount_target() { :; }
  wipe_signatures() { :; }
  flush_buffers() { sync; }
  rescan_partitions() { :; }
  show_partitions() { :; }
  # Regular files don't accept oflag=direct or BSD dd's bs=4m on Linux dd's
  # parser. Use plain bs=1M for both write + verify in test mode.
  DD_OPTS=(bs=1M)
  DD_VERIFY_OPTS=(bs=1M)
elif [ "$OS" = "Darwin" ]; then
  enumerate_devices() {
    # `diskutil list external physical` lists USB / Thunderbolt removable
    # disks and skips the internal APFS container. Whole-disk row carries the
    # size as `*<n.n> <unit>`. Partition row 1 (if any) usually has a
    # human-readable volume name in NAME column.
    diskutil list external physical 2>/dev/null | awk '
      /^\/dev\/disk[0-9]+/ {
        if (dev != "") print dev "\t" desc
        dev = $1
        sub(/:$/, "", dev)
        desc = ""
        next
      }
      dev != "" && /^[[:space:]]+0:/ {
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^\*/) {
            sz = substr($i, 2)
            unit = (i < NF) ? $(i+1) : ""
            desc = sz " " unit
            break
          }
        }
      }
      dev != "" && /^[[:space:]]+1:/ && desc !~ / \/ /  {
        # Append the first partition NAME (cols 3..n-3, between TYPE and SIZE)
        # as a human hint. Rough: grab field 3 if it looks alphabetic.
        if ($3 ~ /^[A-Za-z]/) desc = desc " / " $3
      }
      END {
        if (dev != "") print dev "\t" desc
      }
    '
  }
  validate_device() {
    case "$DEV" in
      /dev/disk*) DEV="/dev/r${DEV#/dev/}" ;;
    esac
    if [ ! -e "$DEV" ]; then
      echo "device not found: $DEV" >&2
      echo "list devices with: $0 --list" >&2
      exit 1
    fi
  }
  show_target() { diskutil list "$DEV"; }
  unmount_target() { diskutil unmountDisk "$DEV" || true; }
  wipe_signatures() { :; }  # diskutil unmountDisk + dd handles it
  flush_buffers() { sync; }
  rescan_partitions() { :; }
  show_partitions() { diskutil list "$DEV" || true; }
  # macOS dd lacks oflag=direct/conv=fsync (BSD dd). Use the raw device
  # (/dev/rdiskN) — it bypasses the buffer cache, giving the same "no stale
  # buffer" guarantee that oflag=direct gives on Linux. Use uppercase M
  # because GNU coreutils dd (often first on the user's PATH via nix) is
  # case-sensitive and rejects "4m" with `dd: invalid number: '4m'`. BSD
  # dd accepts both, so uppercase wins on portability.
  DD_OPTS=(bs=4M)
  DD_VERIFY_OPTS=(bs=1M)
else
  # Linux
  enumerate_devices() {
    # `lsblk -d` lists whole disks only; TRAN=usb filters to USB-attached
    # devices. We deliberately do NOT match RM=1 alone — some USB SSDs are
    # marked non-removable. Output: <path>\t<size> <vendor> <model>.
    lsblk -dnpo NAME,TRAN,SIZE,VENDOR,MODEL 2>/dev/null | awk '
      $2 == "usb" {
        name = $1
        size = $3
        vendor = $4
        $1 = $2 = $3 = $4 = ""
        sub(/^[[:space:]]+/, "")
        gsub(/[[:space:]]+$/, "")
        printf "%s\t%s %s %s\n", name, size, vendor, $0
      }
    '
  }
  validate_device() {
    if [ ! -b "$DEV" ]; then
      echo "not a block device: $DEV" >&2
      exit 1
    fi
  }
  show_target() { lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS "$DEV"; }
  unmount_target() {
    for part in $(lsblk -lno NAME "$DEV" | tail -n +2); do
      $SUDO umount "/dev/$part" 2>/dev/null || true
    done
  }
  wipe_signatures() { $SUDO wipefs -a "$DEV"; }
  flush_buffers() {
    sync
    $SUDO blockdev --flushbufs "$DEV"
    $SUDO partprobe "$DEV" 2>/dev/null || true
  }
  rescan_partitions() { $SUDO partprobe "$DEV" 2>/dev/null || true; }
  show_partitions() { $SUDO fdisk -l "$DEV"; }
  DD_OPTS=(bs=4M conv=fsync oflag=direct)
  DD_VERIFY_OPTS=(bs=1M iflag=direct)
fi

# Print enumerated devices as a numbered list to stdout. Returns the count.
print_device_list() {
  local i=0 path desc
  while IFS=$'\t' read -r path desc; do
    [ -z "$path" ] && continue
    i=$((i + 1))
    printf '  %d) %s\t%s\n' "$i" "$path" "$desc"
  done < <(enumerate_devices)
  echo "$i" >"$TMP_COUNT"
}

# Drives the picker UX: enumerate, render list, prompt, set DEV.
pick_device() {
  TMP_COUNT="$(mktemp)"
  trap 'rm -f "$TMP_COUNT"' EXIT
  echo "Removable USB devices:" >&2
  local list_out count
  list_out="$(print_device_list)"
  count="$(cat "$TMP_COUNT")"
  rm -f "$TMP_COUNT"; trap - EXIT
  if [ "$count" = "0" ]; then
    echo "  (none found — plug in a USB stick and re-run)" >&2
    exit 1
  fi
  printf '%s\n' "$list_out" >&2
  local choice
  read -r -p "Pick device [1-$count] or q to quit: " choice
  if [ "$choice" = "q" ] || [ "$choice" = "Q" ]; then
    echo "aborted" >&2
    exit 1
  fi
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$count" ]; then
    echo "invalid choice: $choice" >&2
    exit 1
  fi
  DEV="$(enumerate_devices | awk -v n="$choice" -F'\t' 'NF && ++i == n { print $1 }')"
  if [ -z "$DEV" ]; then
    echo "internal error: could not resolve choice $choice" >&2
    exit 1
  fi
  echo "Selected: $DEV" >&2
}

# --list: print and exit before any other work.
if [ "$LIST_ONLY" = "1" ]; then
  echo "Removable USB devices:"
  TMP_COUNT="$(mktemp)"
  trap 'rm -f "$TMP_COUNT"' EXIT
  print_device_list
  count="$(cat "$TMP_COUNT")"
  rm -f "$TMP_COUNT"; trap - EXIT
  if [ "$count" = "0" ]; then
    echo "  (none found)"
  fi
  exit 0
fi

# No device argument → enumerate + prompt.
if [ -z "$DEV" ]; then
  pick_device
fi

validate_device

if [ -z "$ISO" ]; then
  shopt -s nullglob
  candidates=(./result/iso/*.iso)
  shopt -u nullglob
  if [ ${#candidates[@]} -eq 0 ]; then
    echo "no ISO found in ./result/iso — pass one explicitly or run 'just iso' first" >&2
    exit 1
  fi
  if [ ${#candidates[@]} -gt 1 ]; then
    echo "multiple ISOs in ./result/iso — pass one explicitly:" >&2
    printf '  %s\n' "${candidates[@]}" >&2
    exit 1
  fi
  ISO=${candidates[0]}
fi

if [ ! -f "$ISO" ]; then
  echo "iso not found: $ISO" >&2
  exit 1
fi

ISO_SIZE=$(file_size "$ISO")

if command -v pv >/dev/null 2>&1; then
  USE_PV=1
else
  echo "warn: 'pv' not in PATH — falling back to 'dd status=progress'" >&2
  USE_PV=0
fi

echo "==> target device:"
show_target
echo
echo "==> iso: $ISO ($ISO_SIZE bytes)"
echo
read -r -p "ALL DATA on $DEV will be destroyed. Type 'yes' to continue: " confirm
if [ "$confirm" != "yes" ]; then
  echo "aborted" >&2
  exit 1
fi

echo "==> unmounting any partitions on $DEV"
unmount_target

echo "==> wiping existing signatures"
wipe_signatures

echo "==> writing ISO"
# Save dd's stderr to a log so silent pipefail kills are diagnosable.
# `status=none` is GNU-dd only — `sudo dd` on macOS resolves to BSD
# /usr/bin/dd which rejects it. We omit status= entirely on macOS (pv
# shows the live progress; dd's 3-line end-of-run summary is fine) and
# only use `status=progress` on Linux's GNU dd.
DD_LOG=/tmp/flash-installer-iso.dd-write.log
echo "    (dd stderr → $DD_LOG)"
: > "$DD_LOG"
if [ "$OS" = "Darwin" ]; then
  # macOS: `pv | sudo dd` flakes — the pipe + sudo + BSD dd combo has
  # historically delivered partial writes (a single 64 KiB pv buffer, dd
  # exiting clean on early EOF). Run dd directly instead. Press Ctrl+T
  # while it runs to make BSD dd dump progress on SIGINFO.
  echo "    Tip: press Ctrl+T to make dd report progress."
  set +e
  $SUDO dd if="$ISO" of="$DEV" "${DD_OPTS[@]}" 2>"$DD_LOG"
  WRITE_RC=$?
  set -e
elif [ "$USE_PV" = "1" ]; then
  set +e
  pv -s "$ISO_SIZE" -- "$ISO" \
    | $SUDO dd of="$DEV" "${DD_OPTS[@]}" 2>"$DD_LOG"
  # pipefail returns the first non-zero status in the pipe.
  WRITE_RC=$?
  set -e
else
  set +e
  $SUDO dd if="$ISO" of="$DEV" "${DD_OPTS[@]}" status=progress 2>"$DD_LOG"
  WRITE_RC=$?
  set -e
fi
echo "    dd exit code: $WRITE_RC"
echo "    --- dd stderr ($(wc -l < "$DD_LOG" | tr -d ' ') line(s)) ---"
sed 's/^/      /' "$DD_LOG"
if [ "$WRITE_RC" -ne 0 ]; then
  echo "::error:: dd write failed (rc=$WRITE_RC). Full log: $DD_LOG" >&2
  exit 1
fi
# A clean dd exit with zero bytes written counts as a failure too — happens
# when the pipe collapsed before any data flowed.
if ! grep -qE '(transferred|copied)' "$DD_LOG"; then
  echo "::warning:: dd produced no transfer summary — wrote 0 bytes?" >&2
fi

echo "==> flushing kernel buffers"
flush_buffers

echo "==> verifying read-back"
ISO_SHA=$(sha256 "$ISO")
# Read back ISO_SIZE bytes from the device and hash them. iflag=direct on
# Linux skips the page cache; macOS rdiskN is already unbuffered. dd bs=1M
# rounds up to whole MiB, so head -c trims to the exact ISO size.
#
# The pipefail+SIGPIPE trap: head closes its stdin as soon as it has
# ISO_SIZE bytes; the next dd write into that closed pipe gets SIGPIPE
# and dd exits 141, which under `set -o pipefail` aborts the whole
# script before we ever print the comparison. Disable pipefail just
# for this pipeline so the verify completes; the sha comparison below
# is the real verdict on whether the read-back was correct.
COUNT=$(((ISO_SIZE + 1048575) / 1048576))
set +o pipefail
DEV_SHA=$($SUDO dd if="$DEV" "${DD_VERIFY_OPTS[@]}" count="$COUNT" 2>/dev/null |
  head -c "$ISO_SIZE" | sha256 /dev/stdin)
set -o pipefail

echo "    iso sha256: $ISO_SHA"
echo "    dev sha256: $DEV_SHA"

if [ "$ISO_SHA" != "$DEV_SHA" ]; then
  echo "MISMATCH — write failed or USB stick is bad" >&2
  exit 1
fi

if [ "$STRICT_UEFI" = "1" ]; then
  echo "==> strict-uefi: zeroing hybrid-MBR partition entries (sig + GPT preserved)"
  # MBR partition table is at offset 446, four 16-byte entries (64 bytes).
  # The 0x55AA boot signature lives at offset 510 and is left intact.
  # GPT at LBA 1 (offset 512) is untouched.
  $SUDO dd if=/dev/zero of="$DEV" bs=1 count=64 seek=446 conv=notrunc 2>/dev/null
  flush_buffers
fi

echo "==> partition table on $DEV:"
show_partitions || true

if [ "$OS" = "Darwin" ] && [ "$FLASH_ALLOW_FILE" != "1" ]; then
  echo "==> ejecting $DEV"
  diskutil eject "$DEV" || true
fi

echo
echo "OK — bootable ISO written to $DEV"
