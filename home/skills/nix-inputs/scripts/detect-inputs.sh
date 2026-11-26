#!/usr/bin/env bash
# Reports which input system a Nix repo uses: a flake.lock, tack (.tack/), both,
# or neither. Prints one JSON object on stdout so the caller picks the right
# update command instead of guessing from the file listing.
#
# Usage: detect-inputs.sh [DIR]   (default: current directory)
set -euo pipefail
shopt -s inherit_errexit

if [[ $# -gt 1 ]]; then
  echo "usage: $0 [DIR]" >&2
  exit 2
fi

dir="${1:-.}"
if [[ ! -d "$dir" ]]; then
  echo "error: not a directory: $dir" >&2
  exit 1
fi

json_bool() { if "$@"; then echo true; else echo false; fi; }

# Nodes in flake.lock other than "root". tack writes a lock holding only the
# root node, so zero means nothing is locked by the flake itself.
lock_nodes() {
  local lock="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r '[.nodes // {} | keys[] | select(. != "root")] | length' "$lock"
  else
    # -o, not -c: a one-line lock holds every node on a single line.
    local matches status=0
    matches="$(grep -o '"locked"' "$lock")" || status=$?
    if [[ "$status" -gt 1 ]]; then
      echo "error: cannot read $lock (grep exit $status)" >&2
      return "$status"
    fi
    if [[ -z "$matches" ]]; then
      echo 0
    else
      grep -c . <<<"$matches"
    fi
  fi
}

# "none" when tack is absent; "v2" when the CLI has commands added after 1.0
# (tree, verify, freeze). Version strings are unreliable: nixpkgs' 1.0.0
# reports itself as 0.1.1.
tack_cli() {
  if ! command -v tack >/dev/null 2>&1; then
    echo none
    return 0
  fi
  local help
  help="$(tack --help 2>/dev/null || true)"
  if grep -Eq '^[[:space:]]+(verify|freeze|tree)[[:space:]]' <<<"$help"; then
    echo v2
  else
    echo v1
  fi
}

cli="$(tack_cli)"
has_flake_nix="$(json_bool test -f "$dir/flake.nix")"
has_tack="$(json_bool test -f "$dir/.tack/pins.toml")"
nodes=0
has_lock=false
if [[ -f "$dir/flake.lock" ]]; then
  has_lock=true
  nodes="$(lock_nodes "$dir/flake.lock")"
fi
imports_tack=false
if [[ "$has_flake_nix" == true ]] && grep -Eq 'import[[:space:]]+\./\.tack' "$dir/flake.nix"; then
  imports_tack=true
fi

if [[ "$has_tack" == true && "$nodes" -gt 0 ]]; then
  mode=both
  update="tack update NAME for tack pins; nix flake update NAME for flake.lock inputs"
elif [[ "$has_tack" == true ]]; then
  mode=tack
  update="tack update NAME"
elif [[ "$has_lock" == true || "$has_flake_nix" == true ]]; then
  mode=flake
  update="nix flake update NAME"
else
  mode=none
  update=""
fi

printf '{"mode":"%s","flake_nix":%s,"flake_lock":%s,"flake_lock_nodes":%s,"tack":%s,"flake_imports_tack":%s,"tack_cli":"%s","update":"%s"}\n' \
  "$mode" "$has_flake_nix" "$has_lock" "$nodes" "$has_tack" "$imports_tack" "$cli" "$update"
