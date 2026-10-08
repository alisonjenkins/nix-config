"""Turn results.jsonl into a Markdown summary table."""
import argparse
import json
import statistics
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

TASK_ORDER = ["newmodule", "unittests", "fixturefix", "multiedit", "explain", "findcalls", "boundaries"]
TASK_IDS = {name: f"T{index}" for index, name in enumerate(TASK_ORDER, start=1)}


def load(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def row(task, runs):
    passed = sum(1 for r in runs if r["pass"])
    codes = ",".join(str(r["exit_code"]) for r in runs)
    review = sum(1 for r in runs if r["needs_review"])
    return (
        f"| {TASK_IDS.get(task, '?')} {task} | {passed}/{len(runs)} | "
        f"{statistics.mean(r['score'] for r in runs):.2f} | "
        f"{statistics.median(r['seconds'] for r in runs):.0f} | {codes} | "
        f"{statistics.mean(r['tool_lines'] for r in runs):.1f} | "
        f"{sum(r['failed_tool_calls'] for r in runs)} | {review} |"
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--results", type=Path, required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    by_task = defaultdict(list)
    for record in load(args.results):
        by_task[record["task"]].append(record)
    lines = [
        f"# Benchmark: {args.label}",
        "",
        f"Generated {datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}.",
        "",
        "| Task | Reps passed | Mean score | Median s | Exit codes | Mean tool lines | Failed tool calls | Needs review |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for task in TASK_ORDER:
        if by_task[task]:
            lines.append(row(task, by_task[task]))
    everything = [r for runs in by_task.values() for r in runs]
    if everything:
        lines.append(row("total", everything).replace("? total", "all"))
    lines += ["", "## Per-run reasons", ""]
    for task in TASK_ORDER:
        for r in by_task[task]:
            verdict = "PASS" if r["pass"] else "FAIL"
            lines.append(f"- {task} rep {r['rep']}: {verdict} {r['score']:.2f} (exit {r['exit_code']}, {r['seconds']}s): {r['reason']}")
    lines += [
        "",
        "Exit 0 means the run finished, not that the task was done; the grade column is what counts.",
        "Rows with Needs review > 0 (explain, boundaries) need a human to read the reply.",
        "",
    ]
    args.out.write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
