# shellcheck shell=bash
# Shared helpers for pm. Sourced, never executed.

# shellcheck disable=SC2034 # read by pm, which sources this file
PM_VERBS="status list show update sync-plan"

pm_die() {
  echo "error: $*" >&2
  exit 1
}

# pm_need tool...: die unless every tool is on PATH.
pm_need() {
  local t
  for t in "$@"; do
    command -v "$t" >/dev/null 2>&1 || pm_die "required tool not found: $t"
  done
}

# pm_arg2 "$@": die unless a flag at $1 has a value at $2.
pm_arg2() {
  [[ $# -ge 2 ]] || pm_die "${1:-flag} needs a value"
}

# pm_header backend [k=v ...]: the first line of every verb's output.
pm_header() {
  local out="# backend=$1" kv
  shift
  for kv in "$@"; do
    out="$out $kv"
  done
  echo "$out"
}

# pm_backends_table <dir>: one "alias<TAB>name" line per backend, by name.
pm_backends_table() {
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

# pm_backends_usage <dir>: "g|github l|local".
pm_backends_usage() {
  pm_backends_table "$1" | awk -F'\t' '{ printf "%s%s|%s", sep, $1, $2; sep = " " } END { print "" }'
}

# pm_resolve_backend <dir> <value>: print the backend name for an alias or a
# full name. Alias wins; no prefix or fuzzy matching.
pm_resolve_backend() {
  local dir="$1" want="$2" alias name
  while IFS="$(printf '\t')" read -r alias name; do
    [[ -n $name ]] || continue
    if [[ -n $alias && $alias == "$want" ]]; then
      echo "$name"
      return 0
    fi
  done < <(pm_backends_table "$dir")
  if [[ $want =~ ^[a-z][a-z0-9-]*$ && -d $dir/$want ]]; then
    echo "$want"
    return 0
  fi
  return 1
}

# pm_url_route <arg>: for a GitHub issue URL print
# "github<TAB>owner/name<TAB>number" and return 0; otherwise return 1.
pm_url_route() {
  local re='^https://github\.com/([^/]+)/([^/]+)/issues/([0-9]+)/?$'
  if [[ $1 =~ $re ]]; then
    printf 'github\t%s/%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
    return 0
  fi
  return 1
}
