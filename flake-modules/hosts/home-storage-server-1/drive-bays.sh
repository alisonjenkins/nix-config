#!/usr/bin/env bash
# drive-bays: show which disk sits in which front slot of home-storage-server-1.
#
# Slots are named row+column as seen from the front: row 1 = top, A = leftmost,
# 6 rows x 4 columns (1A..6D). The SES enclosure counts bays down from 24 at 1A
# to 1 at 6D, so: n = 25 - bay, row = ceil(n/4), column = A..D for (n-1) mod 4.
#
# Usage:
#   drive-bays                       front-view grid (default)
#   drive-bays --table               one line per slot
#   drive-bays --locate <slot|serial|bay> on|off
#                                    toggle a locate LED (the only write; needs root)
set -euo pipefail

readonly SYS_ENCL=/sys/class/enclosure
readonly BAYS=24
readonly COLS=4
readonly CELL_WIDTH=21
readonly COLUMN_LETTERS=ABCD

die() {
  printf 'drive-bays: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  drive-bays                       front-view grid (default)
  drive-bays --table               one line per slot
  drive-bays --locate <slot|serial|bay> on|off
                                   toggle a locate LED (the only write; needs root)
USAGE
}

# The 24-slot enclosure whose slots have the most disks attached. The host0
# view of the same enclosure has 24 slots but no block devices behind them.
find_enclosure() {
  local best="" best_count=-1 encl slots count
  for encl in "$SYS_ENCL"/*; do
    [[ -d "$encl" ]] || continue
    slots=$(compgen -G "$encl/ArrayDevice*" | wc -l)
    [[ "$slots" -eq "$BAYS" ]] || continue
    count=$(compgen -G "$encl/ArrayDevice*/device/block/*" | wc -l)
    if ((count > best_count)); then
      best=$encl
      best_count=$count
    fi
  done
  [[ -n "$best" ]] || die "no ${BAYS}-slot enclosure under $SYS_ENCL"
  printf '%s\n' "$best"
}

bay_to_slot() {
  local bay=$1 n row col
  n=$((BAYS + 1 - bay))
  row=$(((n + COLS - 1) / COLS))
  col=$(((n - 1) % COLS))
  printf '%s%s\n' "$row" "${COLUMN_LETTERS:col:1}"
}

slot_to_bay() {
  local slot=${1^^} row col idx
  [[ "$slot" =~ ^([1-6])([A-D])$ ]] || return 1
  row=${BASH_REMATCH[1]}
  col=${BASH_REMATCH[2]}
  idx=${COLUMN_LETTERS%%"$col"*}
  printf '%s\n' $((BAYS + 1 - ((row - 1) * COLS + ${#idx} + 1)))
}

# ata-<model>_<serial> for a block device name, or empty.
by_id_for() {
  local blk=$1 link
  for link in /dev/disk/by-id/ata-* /dev/disk/by-id/scsi-*; do
    [[ -e "$link" && "$link" != *-part* ]] || continue
    if [[ "$(readlink -f "$link")" == "/dev/$blk" ]]; then
      basename "$link"
      return
    fi
  done
}

# mergerfs branch modes (RW/NC/RO) keyed by mountpoint. Reading them needs
# getfattr and usually root; without that, NC is just not shown.
declare -A BRANCH_MODE=()
load_branch_modes() {
  local pool branches entry
  command -v getfattr >/dev/null 2>&1 || return 0
  while read -r pool; do
    branches=$(getfattr --absolute-names -n user.mergerfs.branches --only-values \
      "$pool/.mergerfs" 2>/dev/null) || continue
    IFS=: read -ra entries <<<"$branches"
    for entry in "${entries[@]}"; do
      BRANCH_MODE[${entry%=*}]=${entry##*=}
    done
  done < <(findmnt -rn -t fuse.mergerfs -o TARGET 2>/dev/null)
}

# Fills the global associative array D for one bay directory.
declare -A D
read_bay() {
  local dir=$1 blk id mnt part
  D=([bay]="" [slot]="" [blk]="" [model]="" [serial]="" [size]="" [role]="empty" [mount]="" [leds]="")
  D[bay]=$(($(cat "$dir/slot") + 1))
  D[slot]=$(bay_to_slot "${D[bay]}")
  [[ "$(cat "$dir/locate" 2>/dev/null || echo 0)" == 1 ]] && D[leds]+="LOCATE "
  [[ "$(cat "$dir/fault" 2>/dev/null || echo 0)" == 1 ]] && D[leds]+="FAULT "

  for blk in "$dir"/device/block/*; do
    [[ -e "$blk" ]] && break
  done
  blk=$([[ -e "$blk" ]] && basename "$blk" || true)
  [[ -n "$blk" && -e "/sys/block/$blk" ]] || return 0
  D[blk]=$blk
  D[size]=$(numfmt --to=si --suffix=B "$(($(cat "/sys/block/$blk/size") * 512))" 2>/dev/null || echo "?")

  id=$(by_id_for "$blk")
  if [[ -n "$id" ]]; then
    id=${id#ata-}
    id=${id#scsi-}
    D[serial]=${id##*_}
    D[model]=${id%_*}
    D[model]=${D[model]//_/ }
  else
    D[model]=$(xargs <"/sys/block/$blk/device/model" 2>/dev/null || true)
    D[serial]="?"
  fi

  D[role]="unmounted"
  local parts=("$blk") p
  for p in /sys/block/"$blk"/"$blk"*; do
    [[ -e "$p" ]] && parts+=("${p##*/}")
  done
  for part in "${parts[@]}"; do
    mnt=$(findmnt -rn -S "/dev/$part" -o TARGET 2>/dev/null | head -n1) || true
    [[ -n "$mnt" ]] || continue
    D[mount]=$mnt
    case "$mnt" in
      /media/parity/*) D[role]="parity" ;;
      /media/disks/*)
        D[role]="data"
        [[ "${BRANCH_MODE[$mnt]:-}" == NC ]] && D[role]="data NC"
        ;;
      *) D[role]="other" ;;
    esac
    break
  done
}

bay_dir() {
  local encl=$1 bay=$2 dir
  for dir in "$encl"/ArrayDevice*; do
    [[ "$(cat "$dir/slot")" -eq $((bay - 1)) ]] && {
      printf '%s\n' "$dir"
      return
    }
  done
  return 1
}

print_table() {
  local encl=$1 n bay
  printf '%-4s %-3s %-5s %-24s %-16s %-6s %-9s %-7s %s\n' \
    SLOT BAY DEV MODEL SERIAL SIZE ROLE LEDS MOUNT
  for ((n = 1; n <= BAYS; n++)); do
    bay=$((BAYS + 1 - n))
    read_bay "$(bay_dir "$encl" "$bay")"
    printf '%-4s %-3s %-5s %-24s %-16s %-6s %-9s %-7s %s\n' \
      "${D[slot]}" "${D[bay]}" "${D[blk]:--}" "${D[model]:--}" "${D[serial]:--}" \
      "${D[size]:--}" "${D[role]}" "${D[leds]:--}" "${D[mount]:--}"
  done
}

cell() {
  printf "%-${CELL_WIDTH}.${CELL_WIDTH}s" "$1"
}

print_grid() {
  local encl=$1 row col bay border line1 line2 line3 line4 model
  border="+$(printf -- "-%.0s" $(seq 1 $(((CELL_WIDTH + 1) * COLS - 1))))+"
  printf 'Front view (row 1 = top, A = left). Enclosure: %s\n' "$(basename "$encl")"
  printf '%s\n' "$border"
  for ((row = 1; row <= BAYS / COLS; row++)); do
    line1="|" line2="|" line3="|" line4="|"
    for ((col = 0; col < COLS; col++)); do
      bay=$((BAYS - (row - 1) * COLS - col))
      read_bay "$(bay_dir "$encl" "$bay")"
      model=${D[model]##* }
      line1+="$(cell "${D[slot]} bay ${D[bay]} ${D[leds]}")|"
      if [[ -z "${D[blk]}" ]]; then
        line2+="$(cell "  (empty)")|"
        line3+="$(cell "")|"
        line4+="$(cell "")|"
      else
        line2+="$(cell " ${model}")|"
        line3+="$(cell " ${D[serial]}")|"
        line4+="$(cell " ${D[size]} ${D[role]}")|"
      fi
    done
    printf '%s\n%s\n%s\n%s\n%s\n' "$line1" "$line2" "$line3" "$line4" "$border"
  done
}

set_locate() {
  local encl=$1 target=$2 state=$3 bay="" b dir
  case "$state" in on) state=1 ;; off) state=0 ;; *) die "--locate state must be on or off, got '$state'" ;; esac
  ((EUID == 0)) || die "--locate writes to sysfs and needs root (run with sudo)"

  if bay=$(slot_to_bay "$target"); then
    :
  elif [[ "$target" =~ ^[0-9]+$ ]] && ((target >= 1 && target <= BAYS)); then
    bay=$target
  else
    for ((b = 1; b <= BAYS; b++)); do
      read_bay "$(bay_dir "$encl" "$b")"
      if [[ -n "${D[serial]}" && "${D[serial]^^}" == "${target^^}" ]]; then
        bay=$b
        break
      fi
    done
  fi
  [[ -n "$bay" ]] || die "no slot, bay or serial matches '$target'"

  dir=$(bay_dir "$encl" "$bay") || die "bay $bay not found in $encl"
  printf '%s\n' "$state" >"$dir/locate"
  printf 'locate %s: slot %s, bay %s (%s)\n' \
    "$([[ $state == 1 ]] && echo on || echo off)" "$(bay_to_slot "$bay")" "$bay" "$dir/locate"
}

main() {
  local mode=grid encl
  case "${1:-}" in
    "" | --grid) mode=grid ;;
    --table) mode=table ;;
    --locate)
      [[ $# -eq 3 ]] || die "usage: drive-bays --locate <slot|serial|bay> on|off"
      mode=locate
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "unknown option '$1' (try --help)" ;;
  esac

  encl=$(find_enclosure)
  case "$mode" in
    grid)
      load_branch_modes
      print_grid "$encl"
      ;;
    table)
      load_branch_modes
      print_table "$encl"
      ;;
    locate) set_locate "$encl" "$2" "$3" ;;
  esac
}

main "$@"
