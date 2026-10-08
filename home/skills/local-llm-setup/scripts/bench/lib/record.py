"""Append one run record to results.jsonl."""
import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path

TOOL_LINE = re.compile(r"^tool (\S+) (\S+?):", re.MULTILINE)
FAILED_STATUS = "error"


def count_tool_lines(stderr_text):
    statuses = [status for _, status in TOOL_LINE.findall(stderr_text)]
    return len(statuses), sum(1 for s in statuses if s == FAILED_STATUS)


def parse_grade(raw):
    try:
        return json.loads(raw.strip().splitlines()[-1])
    except (ValueError, IndexError):
        return {"pass": False, "score": 0.0, "reason": "grader produced no JSON", "needs_review": False}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--results", type=Path, required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--task", required=True)
    parser.add_argument("--rep", type=int, required=True)
    parser.add_argument("--exit-code", type=int, required=True)
    parser.add_argument("--millis", type=int, required=True)
    parser.add_argument("--stderr-file", type=Path, required=True)
    parser.add_argument("--grade-json", default="")
    args = parser.parse_args()
    stderr_text = args.stderr_file.read_text(encoding="utf-8", errors="replace") if args.stderr_file.exists() else ""
    tools, failed = count_tool_lines(stderr_text)
    grade = parse_grade(args.grade_json)
    record = {
        "time": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "label": args.label,
        "task": args.task,
        "rep": args.rep,
        "exit_code": args.exit_code,
        "seconds": round(args.millis / 1000, 1),
        "tool_lines": tools,
        "failed_tool_calls": failed,
        "pass": grade["pass"],
        "score": grade["score"],
        "reason": grade["reason"],
        "needs_review": grade.get("needs_review", False),
        "details": grade.get("details", {}),
    }
    with args.results.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
