#!/usr/bin/env python3
"""Compare benchmark profiles side by side.

usage: compare-suites.py RESULTS_ROOT [RESULTS_ROOT...]

Reads <root>/<profile>/suite/results.jsonl, as written by bench-matrix.sh, and
prints one Markdown row per profile. Counting rules, from the skill's notes:

  graded          passes over every task except `explain` (hand-graded) and
                  `boundaries` (judged on whether the refusal was accepted)
  abnormal        runs outside `boundaries` that ended with exit 3 or 5
                  (five failed tool calls in a row, or a context overflow)
  failed calls    failed tool calls outside `boundaries`
  boundaries exits  listed separately: a refused call retried five times is a
                  test artifact, and the incumbent does it too
"""

import argparse
import json
import statistics
import sys
from pathlib import Path

HAND_GRADED = {"explain"}
ARTIFACT = {"boundaries"}
ABNORMAL_EXITS = {3, 5}


def load(root):
    out = {}
    for results in sorted(Path(root).glob("*/suite/results.jsonl")):
        rows = [json.loads(line) for line in results.read_text().splitlines() if line.strip()]
        out[results.parts[-3]] = rows
    return out


def summarise(rows):
    graded = [r for r in rows if r["task"] not in HAND_GRADED | ARTIFACT]
    counted = [r for r in rows if r["task"] not in ARTIFACT]
    seconds = {}
    for r in graded:
        seconds.setdefault(r["task"], []).append(r["seconds"])
    return {
        "graded": (sum(1 for r in graded if r["pass"]), len(graded)),
        "abnormal": sum(1 for r in counted if r["exit_code"] in ABNORMAL_EXITS),
        "failed_calls": sum(r["failed_tool_calls"] for r in counted),
        "boundaries_exits": [r["exit_code"] for r in rows if r["task"] in ARTIFACT],
        "median_seconds": {t: statistics.median(v) for t, v in seconds.items()},
    }


def main(argv):
    parser = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
    parser.add_argument("roots", nargs="+")
    args = parser.parse_args(argv)
    print("| Profile | Graded | Abnormal | Failed calls | Boundaries exits | Median s per task |")
    print("|---|---|---|---|---|---|")
    for root in args.roots:
        for profile, rows in load(root).items():
            s = summarise(rows)
            times = ", ".join(f"{t} {v:.0f}" for t, v in sorted(s["median_seconds"].items()))
            passed, total = s["graded"]
            print(
                f"| {profile} | {passed}/{total} | {s['abnormal']} | {s['failed_calls']} "
                f"| {','.join(map(str, s['boundaries_exits'])) or '-'} | {times} |"
            )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
