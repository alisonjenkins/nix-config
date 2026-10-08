#!/usr/bin/env bash
# usage: bench-matrix.sh <profile[:old|:new]>...
#
# For each profile, in order: stop any worker, load the profile, record load
# time and VRAM, run the safety/speed probe, run the 7-task suite, unload.
# Results land in $BENCH_OUT/<profile>-<engine>/ (load.json, probe/, suite/).
#
# env:
#   BENCH_PROFILES  profiles.toml to use (default: the delegation default)
#   BENCH_OUT       output root (default: ./bench-results)
#   BENCH_REPS      repetitions per task (default 2; use 3 to see variance)
#   LLAMA_BIN_DIR   directory with the second llama-server, for ":new"
#   LOCAL_LLM_FORCE_SWITCH=1  load even when the fit check refuses
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$here/lib.sh"

[[ $# -ge 1 ]] || die "usage: $0 <profile[:old|:new]>..."
scripts=$(find_delegation_scripts)
out_root=${BENCH_OUT:-$PWD/bench-results}
reps=${BENCH_REPS:-2}
BASE_PATH=$PATH
[[ -n "${BENCH_PROFILES:-}" ]] && export LOCAL_LLM_PROFILES_FILE=$BENCH_PROFILES
mkdir -p "$out_root"

run_one() {
  local profile=$1 engine=$2 out="$out_root/$1-$2" idle load_start load_end
  mkdir -p "$out"
  stop_worker "$scripts"
  select_engine "$engine"
  echo "[$(date -u +%FT%TZ)] === $profile engine=$engine $(llama-server --version 2>&1 | grep -E '^version')" | tee -a "$out_root/driver.log"
  idle=$(vram_used_bytes)
  load_start=$(date +%s)
  if ! "$scripts/switch-local-profile.sh" "$profile" >"$out/switch.log" 2>&1; then
    echo "[$(date -u +%FT%TZ)] LOAD FAILED $profile: $(tail -2 "$out/switch.log")" | tee -a "$out_root/driver.log"
    stop_worker "$scripts"
    return
  fi
  load_end=$(date +%s)
  printf '{"profile":"%s","engine":"%s","load_seconds":%d,"vram_idle":%s,"vram_loaded":%s}\n' \
    "$profile" "$engine" "$((load_end - load_start))" "$idle" "$(vram_used_bytes)" >"$out/load.json"
  python3 "$here/bench/probe.py" --out "$out/probe" >"$out/probe.log" 2>&1 || true
  "$here/bench/run-bench.sh" "$profile-$engine" "$out/suite" "$reps" >"$out/suite.log" 2>&1 || true
  echo "[$(date -u +%FT%TZ)] done $profile engine=$engine" | tee -a "$out_root/driver.log"
  stop_worker "$scripts"
}

for spec in "$@"; do
  profile=${spec%%:*}
  engine=old
  [[ "$spec" == *:* ]] && engine=${spec##*:}
  run_one "$profile" "$engine"
done
echo "[$(date -u +%FT%TZ)] ALL DONE" | tee -a "$out_root/driver.log"
