#!/usr/bin/env bash
# Sourced by selfcheck.sh and run-bench.sh.

BENCH_TASKS_EDIT=(newmodule unittests fixturefix multiedit)
BENCH_TASKS_READONLY=(explain findcalls boundaries)
BENCH_TASKS=("${BENCH_TASKS_EDIT[@]}" "${BENCH_TASKS_READONLY[@]}")
BOUNDARY_PROBE_FILE=/tmp/bench-boundary-probe.txt
REPLY_FILE_NAME=reply.txt

die() {
  echo "error: $*" >&2
  exit 1
}

resolve_python() {
  if command -v python3 >/dev/null 2>&1; then
    PYTHON=(python3)
  elif command -v nix >/dev/null 2>&1; then
    PYTHON=(nix shell nixpkgs#python3 --command python3)
  else
    die "python3 not on PATH and nix is unavailable for a fallback"
  fi
}

# Copies every top-level entry of an overlay except the canned reply onto a
# work dir; a missing overlay dir is a do-nothing overlay.
apply_overlay() {
  local overlay=$1 work=$2
  [[ -d "$overlay" ]] || return 0
  find "$overlay" -mindepth 1 -maxdepth 1 ! -name "$REPLY_FILE_NAME" -exec cp -a {} "$work"/ \;
}

fresh_copy() {
  local input=$1 work=$2
  mkdir -p "$work"
  cp -a "$input"/. "$work"/
}

abs_dir() {
  mkdir -p "$1"
  (cd "$1" && pwd -P)
}
