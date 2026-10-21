#!/usr/bin/env bash
# Alias lint for pm backends. Usage: lint-aliases.sh [backends_dir]
# Prints "FAIL <backend>: <reason>" per problem; exits 1 if any.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
backends_dir="${1:-$script_dir/backends}"
failures=0
names=()
aliases=()

fail() {
  echo "FAIL $1: $2"
  failures=$((failures + 1))
}

for d in "$backends_dir"/*/; do
  [[ -d $d ]] || continue
  name="$(basename "$d")"
  if [[ ! -f $d/alias ]]; then
    fail "$name" "no alias file"
    continue
  fi
  alias="$(tr -d '[:space:]' <"$d/alias")"
  if [[ ! $alias =~ ^[A-Za-z]+$ ]]; then
    fail "$name" "alias '$alias' is not [A-Za-z]+"
    continue
  fi
  if ((${#alias} > ${#name})); then
    fail "$name" "alias '$alias' is longer than the name"
  fi
  names+=("$name")
  aliases+=("$alias")
done

n=${#names[@]}
for ((i = 0; i < n; i++)); do
  for ((j = 0; j < n; j++)); do
    ((i == j)) && continue
    if ((i < j)) && [[ ${aliases[i]} == "${aliases[j]}" ]]; then
      fail "${names[i]}" "alias '${aliases[i]}' also used by ${names[j]}"
    fi
    if [[ ${aliases[i]} == "${names[j]}" ]]; then
      fail "${names[i]}" "alias '${aliases[i]}' equals backend name ${names[j]}"
    fi
  done
done

if ((failures > 0)); then
  echo "$failures alias problem(s)" >&2
  exit 1
fi
echo "backend aliases ok"
