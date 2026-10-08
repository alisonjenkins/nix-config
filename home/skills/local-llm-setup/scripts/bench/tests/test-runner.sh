#!/usr/bin/env bash
# Runner plumbing test: put a fake delegate first on PATH and check results.md.
# The fake applies solution/ (expect all PASS) or nothing (expect all FAIL).
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
bench=$(cd "$here/.." && pwd -P)
# shellcheck source=../lib/common.sh
source "$bench/lib/common.sh"
resolve_python

scratch=$(abs_dir "$(mktemp -d)")
trap 'rm -rf "$scratch"' EXIT
export PATH="$here/fake-delegate:$PATH"
failures=0

run_mode() {
  local mode=$1 expect_pass=$2
  local out=$scratch/$mode
  FAKE_MODE=$mode "$bench/run-bench.sh" "fake-$mode" "$out" 2 2>"$scratch/$mode.log" \
    || { echo "BAD runner exited non-zero for $mode"; cat "$scratch/$mode.log"; failures=$((failures + 1)); return; }
  echo "--- results.md ($mode) ---"
  cat "$out/results.md"
  "${PYTHON[@]}" - "$out" "$expect_pass" <<'EOF' || failures=$((failures + 1))
import json
import sys
from pathlib import Path

out, expect_pass = Path(sys.argv[1]), sys.argv[2] == "true"
records = [json.loads(line) for line in (out / "results.jsonl").read_text().splitlines()]
problems = []
if len(records) != 14:
    problems.append(f"{len(records)} records, wanted 7 tasks x 2 reps")
for r in records:
    if r["tool_lines"] != 3 or r["failed_tool_calls"] != 1:
        problems.append(f"{r['task']}: tool counting {r['tool_lines']}/{r['failed_tool_calls']}")
    if r["exit_code"] != 0:
        problems.append(f"{r['task']}: exit {r['exit_code']}")
    if expect_pass and not (r["pass"] and r["score"] == 1.0):
        problems.append(f"{r['task']} rep {r['rep']} should PASS: {r['reason']}")
    if not expect_pass and r["pass"] and r["score"] >= 1.0:
        problems.append(f"{r['task']} rep {r['rep']} should FAIL: {r['reason']}")
for work in sorted((out / "work").iterdir()):
    if work.resolve() != work or work.is_symlink():
        problems.append(f"{work} is not an absolute, symlink-free path")
if not (out / "results.md").read_text().startswith("# Benchmark: fake-"):
    problems.append("results.md header")
print("BAD " + "; ".join(problems) if problems else f"ok  runner plumbing, expect_pass={str(expect_pass).lower()}")
sys.exit(1 if problems else 0)
EOF
}

run_mode solution true
run_mode null false

if ((failures > 0)); then
  echo "test-runner: $failures failure(s)" >&2
  exit 1
fi
echo "test-runner: ok"
