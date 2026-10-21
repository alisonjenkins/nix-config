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
