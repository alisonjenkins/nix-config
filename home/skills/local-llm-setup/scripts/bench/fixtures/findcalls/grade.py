import ast
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent / "lib"))

import graderlib  # noqa: E402

TASK = "findcalls"
FUNCTION = "parse_rate"
CITATION = re.compile(r"([A-Za-z0-9_.-]+\.py):(\d+)")


def true_calls(directory):
    calls = set()
    for path in sorted(Path(directory).glob("*.py")):
        for node in ast.walk(ast.parse(path.read_text(encoding="utf-8"))):
            if not isinstance(node, ast.Call):
                continue
            func = node.func
            name = func.id if isinstance(func, ast.Name) else func.attr if isinstance(func, ast.Attribute) else None
            if name == FUNCTION:
                calls.add((path.name, node.lineno))
    return calls


def cited(reply):
    return {(Path(name).name, int(line)) for name, line in CITATION.findall(reply)}


def grade(workdir, reply, here):
    changed = [p for p in graderlib.changed_paths(here / "input", workdir) if (here / "input" / p).exists()]
    if changed:
        return graderlib.result(TASK, False, 0.0, "a read-only task modified files: " + ", ".join(changed))
    truth = true_calls(workdir)
    claimed = cited(reply)
    hits = truth & claimed
    precision = len(hits) / len(claimed) if claimed else 0.0
    recall = len(hits) / len(truth) if truth else 1.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    wrong = sorted(claimed - truth)
    missed = sorted(truth - claimed)
    near_miss = [c for c in wrong if any(c[0] == t[0] and abs(c[1] - t[1]) == 1 for t in truth)]
    details = {
        "precision": round(precision, 4),
        "recall": round(recall, 4),
        "truth_count": len(truth),
        "wrong": [f"{n}:{l}" for n, l in wrong],
        "missed": [f"{n}:{l}" for n, l in missed],
        "off_by_one": [f"{n}:{l}" for n, l in near_miss],
    }
    if not wrong and not missed:
        return graderlib.result(TASK, True, 1.0, f"all {len(truth)} calls listed with correct lines", **details)
    return graderlib.result(
        TASK, False, f1, f"precision {precision:.2f}, recall {recall:.2f}; wrong={details['wrong']} missed={details['missed']}", **details
    )


if __name__ == "__main__":
    sys.exit(graderlib.run_grader(TASK, grade, HERE))
