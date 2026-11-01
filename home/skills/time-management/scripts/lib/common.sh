# shellcheck shell=bash
# Shared helpers for tm. Sourced, never executed.

# shellcheck disable=SC2034 # read by tm, which sources this file
TM_VERBS="plan"

tm_die() {
  echo "error: $*" >&2
  exit 1
}

# tm_arg2 "$@": die unless a flag at $1 has a value at $2.
tm_arg2() {
  [[ $# -ge 2 ]] || tm_die "${1:-flag} needs a value"
}

# tm_zone_known <name>: succeed if name is a compiled zone (TZif file) in the tz
# database. GNU date reads $TZDIR alone when it is set and treats anything else
# as UTC, so only look where date will. macOS date has the directory compiled in
# and ignores $TZDIR. TM_ZONEINFO_DIRS (colon separated) replaces the system paths.
tm_zone_known() {
  local d dirs
  [[ $1 =~ ^[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+)*$ ]] || return 1
  IFS=: read -ra dirs <<<"${TM_ZONEINFO_DIRS:-/usr/share/zoneinfo:/usr/share/lib/zoneinfo:/etc/zoneinfo}"
  if [[ -n ${TZDIR:-} ]] && date --version >/dev/null 2>&1; then
    dirs=("$TZDIR")
  fi
  for d in "${dirs[@]}"; do
    if [[ -f $d/$1 && $(head -c 4 "$d/$1") == TZif ]]; then
      return 0
    fi
  done
  return 1
}

# tm_zone_offset <zone> <epoch|"YYYY-MM-DD">: the zone's UTC offset in minutes at
# that instant, or at noon local time on that date (a transition is never at
# noon, so the whole working day shares it). GNU date, else BSD date. BSD date's
# -d means something else (kernel DST flag), so GNU is detected, never tried.
tm_zone_offset() {
  local zone="$1" when="$2" z
  if date --version >/dev/null 2>&1; then
    if [[ $when =~ ^[0-9]+$ ]]; then
      z="$(TZ="$zone" date -d "@$when" +%z)"
    else
      z="$(TZ="$zone" date -d "$when 12:00" +%z)"
    fi
  elif [[ $when =~ ^[0-9]+$ ]]; then
    z="$(TZ="$zone" date -r "$when" +%z)"
  else
    z="$(TZ="$zone" date -j -f '%Y-%m-%d %H:%M' "$when 12:00" +%z)"
  fi
  [[ $z =~ ^([+-])([0-9][0-9])([0-9][0-9])$ ]] || tm_die "cannot read the UTC offset of zone '$zone' (got '$z')"
  local m=$((10#${BASH_REMATCH[2]} * 60 + 10#${BASH_REMATCH[3]}))
  [[ ${BASH_REMATCH[1]} == - ]] && m=$((-m))
  echo "$m"
}

# tm_backends_table <dir>: one "alias<TAB>name" line per backend, by name.
tm_backends_table() {
  local d name alias
  for d in "$1"/*/; do
    [[ -d $d ]] || continue
    name="$(basename "$d")"
    alias=""
    if [[ -f $d/alias ]]; then
      alias="$(tr -d '[:space:]' <"$d/alias")"
    fi
    printf '%s\t%s\n' "$alias" "$name"
  done | LC_ALL=C sort -t "$(printf '\t')" -k2,2
}

# tm_backends_usage <dir>: "g|google i|ics".
tm_backends_usage() {
  tm_backends_table "$1" | awk -F'\t' '{ printf "%s%s|%s", sep, $1, $2; sep = " " } END { print "" }'
}

# tm_resolve_backend <dir> <value>: print the backend name for an alias or a
# full name. Alias wins; no prefix or fuzzy matching.
tm_resolve_backend() {
  local dir="$1" want="$2" alias name
  while IFS="$(printf '\t')" read -r alias name; do
    [[ -n $name ]] || continue
    if [[ -n $alias && $alias == "$want" ]]; then
      echo "$name"
      return 0
    fi
  done < <(tm_backends_table "$dir")
  if [[ $want =~ ^[a-z][a-z0-9-]*$ && -d $dir/$want ]]; then
    echo "$want"
    return 0
  fi
  return 1
}
