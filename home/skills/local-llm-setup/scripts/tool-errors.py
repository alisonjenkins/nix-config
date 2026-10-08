#!/usr/bin/env python3
"""Classify the failed tool calls in a benchmark's agent event logs.

usage: tool-errors.py RESULTS_ROOT [--json]

Reads RESULTS_ROOT/<profile>/suite/logs/<task>-<rep>.events.jsonl, as written
by bench-matrix.sh, and counts failed calls by profile, task and kind:

  denied        a permission rule refused the call (expected in `boundaries`)
  identical     an edit whose oldString equals newString (a no-op)
  not_found     oldString is not in the file
  ambiguous     oldString matches more than once
  missing_file  the path does not exist
  other         anything else

A failure count alone mixes these; the kind tells you whether to look at the
engine, the model or the task.
"""

import argparse
import collections
import json
import sys
from pathlib import Path

KINDS = (
    ("specified a rule", "denied"),
    ("are identical", "identical"),
    ("Could not find oldString", "not_found"),
    ("multiple matches", "ambiguous"),
    ("File not found", "missing_file"),
)


def classify(error):
    for needle, kind in KINDS:
        if needle in error:
            return kind
    return "other"


def summarise(root):
    out = collections.defaultdict(lambda: collections.defaultdict(collections.Counter))
    for events in sorted(Path(root).glob("*/suite/logs/*.events.jsonl")):
        profile = events.parts[-4]
        task = events.name.split("-")[0]
        for line in events.read_text().splitlines():
            try:
                part = json.loads(line).get("part", {})
            except ValueError:
                continue
            state = part.get("state", {})
            if part.get("type") == "tool" and state.get("status") == "error":
                out[profile][task][classify(str(state.get("error", "")))] += 1
    return {p: {t: dict(c) for t, c in tasks.items()} for p, tasks in out.items()}


def main(argv):
    parser = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
    parser.add_argument("root")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    summary = summarise(args.root)
    if args.json:
        print(json.dumps(summary, indent=1, sort_keys=True))
        return 0
    for profile, tasks in sorted(summary.items()):
        total = sum(sum(c.values()) for c in tasks.values())
        print(f"{profile}: {total} failed calls")
        for task, counts in sorted(tasks.items()):
            print(f"  {task:12s} {counts}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
