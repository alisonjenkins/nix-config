#!/usr/bin/env bash
# tm plan (ics): rank pm list rows, place them around busy .ics files and
# optionally write the plan as an .ics. Reads rows from --from or stdin.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$script_dir/../../lib/common.sh"
lib="$script_dir/../../lib"

from=""
busy=()
out_ics=""
now_arg=""
days=14
hours=09:00-17:00
tz=+00:00
weekdays=1-5
chunk=90
gap=10
defest=30
while (($#)); do
  case "$1" in
    --from) tm_arg2 "$@"; from="$2"; shift 2 ;;
    --busy) tm_arg2 "$@"; busy+=("$2"); shift 2 ;;
    --ics) tm_arg2 "$@"; out_ics="$2"; shift 2 ;;
    --now) tm_arg2 "$@"; now_arg="$2"; shift 2 ;;
    --days) tm_arg2 "$@"; days="$2"; shift 2 ;;
    --hours) tm_arg2 "$@"; hours="$2"; shift 2 ;;
    --tz) tm_arg2 "$@"; tz="$2"; shift 2 ;;
    --weekdays) tm_arg2 "$@"; weekdays="$2"; shift 2 ;;
    --chunk) tm_arg2 "$@"; chunk="$2"; shift 2 ;;
    --gap) tm_arg2 "$@"; gap="$2"; shift 2 ;;
    --default-est) tm_arg2 "$@"; defest="$2"; shift 2 ;;
    *) tm_die "plan: unsupported argument '$1'" ;;
  esac
done

# tm_uint <flag> <value> <min>: die unless value is a whole number >= min.
# 10# keeps a leading zero ("08") from being read as octal.
tm_uint() {
  if [[ ! $2 =~ ^[0-9]+$ ]] || ((10#$2 < $3)); then
    tm_die "plan: $1 must be a whole number >= $3, got '$2'"
  fi
}

tm_uint --days "$days" 1
# Each placement rescans the horizon from day one, so cap it.
((10#$days <= 366)) || tm_die "plan: --days must be at most 366, got '$days'"
tm_uint --chunk "$chunk" 1
tm_uint --gap "$gap" 0
tm_uint --default-est "$defest" 1

hours_re='^([0-9][0-9]):([0-9][0-9])-([0-9][0-9]):([0-9][0-9])$'
[[ $hours =~ $hours_re ]] || tm_die "plan: --hours must look like 09:00-17:00, got '$hours'"
hs=$((10#${BASH_REMATCH[1]} * 60 + 10#${BASH_REMATCH[2]}))
he=$((10#${BASH_REMATCH[3]} * 60 + 10#${BASH_REMATCH[4]}))
((10#${BASH_REMATCH[2]} < 60 && 10#${BASH_REMATCH[4]} < 60 && hs < he && he <= 1440)) ||
  tm_die "plan: --hours must be a valid window within one day, got '$hours'"

tz_re='^([+-])([0-9][0-9]):([0-9][0-9])$'
[[ $tz =~ $tz_re ]] || tm_die "plan: --tz must be a fixed offset like +01:00, got '$tz'"
tz_min=$((10#${BASH_REMATCH[2]} * 60 + 10#${BASH_REMATCH[3]}))
((10#${BASH_REMATCH[3]} < 60 && tz_min <= 840)) || tm_die "plan: --tz offset out of range, got '$tz'"
[[ ${BASH_REMATCH[1]} == - ]] && tz_min=$((-tz_min))

wd_re='^([1-7])-([1-7])$'
[[ $weekdays =~ $wd_re ]] || tm_die "plan: --weekdays must look like 1-5 (1 = Monday), got '$weekdays'"
wdmin="${BASH_REMATCH[1]}"
wdmax="${BASH_REMATCH[2]}"
((wdmin <= wdmax)) || tm_die "plan: --weekdays range is backwards, got '$weekdays'"

tmp="$(mktemp -d)"
ics_tmp=""
trap 'rm -rf "$tmp"; [[ -z $ics_tmp ]] || rm -f "$ics_tmp"' EXIT
echo 'BEGIN { print iso2epoch(s) }' >"$tmp/to-epoch.awk"
echo 'BEGIN { print epoch2iso(e) }' >"$tmp/to-iso.awk"

if [[ -n $now_arg ]]; then
  now_epoch="$(awk -v s="$now_arg" -f "$lib/time.awk" -f "$tmp/to-epoch.awk")"
  ((now_epoch >= 0)) || tm_die "plan: --now must be an ISO8601 UTC time, got '$now_arg'"
else
  now_epoch="$(date -u +%s)"
fi
now_iso="$(awk -v e="$now_epoch" -f "$lib/time.awk" -f "$tmp/to-iso.awk")"

if [[ -z $from || $from == - ]]; then
  from_label=stdin
  cat >"$tmp/rows.tsv"
else
  [[ -r $from ]] || tm_die "plan: cannot read --from file '$from'"
  from_label="$from"
  cp "$from" "$tmp/rows.tsv"
fi

: >"$tmp/busy.tsv"
for f in ${busy[@]+"${busy[@]}"}; do
  [[ -r $f ]] || tm_die "plan: cannot read --busy file '$f'"
  awk -v hfrom="$now_epoch" -v hto="$((now_epoch + (10#$days + 1) * 86400))" \
    -f "$lib/time.awk" -f "$lib/busy.awk" "$f" >>"$tmp/busy.tsv"
done

if [[ -n $out_ics ]]; then
  out_dir="$(dirname "$out_ics")"
  [[ -d $out_dir && -w $out_dir ]] || tm_die "plan: cannot write --ics file in '$out_dir'"
fi

awk -v now="$now_epoch" -v days="$days" -v hs="$hs" -v he="$he" -v tz="$tz_min" \
  -v wdmin="$wdmin" -v wdmax="$wdmax" -v chunk="$chunk" -v gap="$gap" -v defest="$defest" \
  -v busyfile="$tmp/busy.tsv" -f "$lib/time.awk" -f "$lib/schedule.awk" "$tmp/rows.tsv" >"$tmp/plan.txt"

echo "# backend=ics from=$from_label now=$now_iso"
cat "$tmp/plan.txt"

if [[ -n $out_ics ]]; then
  # Written next to the target so the final mv is a rename, never a partial copy.
  # Created by a redirect, not mktemp, so the mode follows the umask (mktemp is 0600).
  ics_new="$out_dir/.tm-plan.$$"
  (set -o noclobber; : >"$ics_new") || tm_die "plan: cannot create '$ics_new'"
  ics_tmp="$ics_new"
  LC_ALL=C awk -v now="$now_epoch" -f "$lib/time.awk" -f "$lib/ics-out.awk" "$tmp/plan.txt" >"$ics_tmp"
  mv "$ics_tmp" "$out_ics"
fi
