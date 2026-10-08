#!/usr/bin/env bash
# usage: probe-tool-whitespace.sh <profile> [old|new]
#
# Loads a profile and checks that the server hands tool-call arguments back
# byte for byte. llama.cpp builds before b9644 dropped one leading space from
# every parameter value, so an edit tool's oldString and newString arrived
# one space short. Compare the "parsed" leading-space counts with the raw
# model text printed at the end: the model wrote 8, the server returned 7.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$here/lib.sh"

[[ $# -ge 1 ]] || die "usage: $0 <profile> [old|new]"
profile=$1
engine=${2:-old}
scripts=$(find_delegation_scripts)
BASE_PATH=$PATH

select_engine "$engine"
stop_worker "$scripts"

echo "== $profile engine=$engine $(llama-server --version 2>&1 | grep -E '^version' || true)"
"$scripts/switch-local-profile.sh" "$profile" 2>&1 | tail -2
python3 "$here/tool-probe.py" --runs "${PROBE_RUNS:-3}" \
  --scenario "${PROBE_SCENARIO:-whitespace}" --temperature "${PROBE_TEMPERATURE:-0}" \
  --extra "${PROBE_EXTRA:-{\}}"
stop_worker "$scripts"
