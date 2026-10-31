#!/usr/bin/env bash
# Print the `nix-store --register-validity` input for every top-level entry of a
# store whose Nix database is empty. A reference is a store-path hash part found
# in file contents or symlink targets, matching a top-level entry, as Nix finds it.
set -euo pipefail
shopt -s inherit_errexit
export LC_ALL=C

usage='usage: register-store.sh [STORE_DIR]'
hash_re='[0-9a-df-np-sv-z]{32}'

[[ $# -le 1 ]] || { echo "$usage" >&2; exit 2; }
store=${1:-/nix/store}
store=${store%/}
if [[ ! -d $store || ! -r $store || ! -x $store ]]; then
  echo "$usage" >&2
  printf 'register-store: cannot read STORE_DIR=%q\n' "$store" >&2
  exit 1
fi

work=$(mktemp -d)
trap '[[ -n ${work:-} ]] && rm -rf "$work"' EXIT

# Top-level entries, sorted; .links and *.lock are not store paths.
shopt -s nullglob dotglob
for path in "$store"/*; do
  name=${path##*/}
  case $name in
    .links | *.lock) continue ;;
  esac
  printf '%s\n' "$name"
done | sort > "$work/names"

# Hash part -> entry name, for entries named <hash>-<name>.
awk -F '\t' 'length($0) > 32 && substr($0, 33, 1) == "-" { print substr($0, 1, 32) "\t" $0 }' \
  "$work/names" > "$work/map"

# Hash parts occurring in a path: file contents (binary too) and symlink targets.
# A top-level symlink is not followed, as Nix does not follow it either.
scan_hashes() {
  local path=$1 links
  if [[ ! -L $path ]]; then
    grep -raohE "$hash_re" -- "$path" || [[ $? -eq 1 ]]
  fi
  links=$(find "$path" -type l -exec readlink {} +)
  printf '%s\n' "$links" | grep -oE "$hash_re" || [[ $? -eq 1 ]]
}

while IFS= read -r name; do
  refs=$(scan_hashes "$store/$name" \
    | awk -F '\t' -v map="$work/map" \
        'FILENAME == map { entry[$1] = $2; next } ($1 in entry) && !seen[$1]++ { print entry[$1] }' \
        "$work/map" - \
    | sort)
  refs_list=()
  if [[ -n $refs ]]; then
    mapfile -t refs_list <<< "$refs"
  fi
  printf '%s/%s\n\n%s\n' "$store" "$name" "${#refs_list[@]}"
  for ref in "${refs_list[@]}"; do
    printf '%s/%s\n' "$store" "$ref"
  done
done < "$work/names"
