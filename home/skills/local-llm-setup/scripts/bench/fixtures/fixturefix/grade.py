import difflib
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent / "lib"))

import graderlib  # noqa: E402

TASK = "fixturefix"
TEST_FILE = "test_store.py"
TEST_MODULE = "test_store"
MAX_CHANGED_LINES = 6
WEIGHT_PASSES = 0.6


def changed_line_count(before, after):
    diff = difflib.unified_diff(before.splitlines(), after.splitlines(), lineterm="", n=0)
    return sum(1 for line in diff if line[:1] in "+-" and line[:3] not in ("+++", "---"))


def grade(workdir, reply, here):
    original_root = here / "input"
    touched = graderlib.changed_paths(original_root, workdir)
    stray = [p for p in touched if p != TEST_FILE]
    if not (workdir / TEST_FILE).is_file():
        return graderlib.result(TASK, False, 0.0, f"{TEST_FILE} is missing")
    passes, output = graderlib.run_unittest(workdir, TEST_MODULE)
    changed = changed_line_count(
        (original_root / TEST_FILE).read_text(encoding="utf-8"),
        (workdir / TEST_FILE).read_text(encoding="utf-8"),
    )
    minimal = changed <= MAX_CHANGED_LINES and not stray
    score = (WEIGHT_PASSES if passes else 0.0) + ((1 - WEIGHT_PASSES) if minimal else 0.0)
    problems = []
    if not passes:
        problems.append("tests fail: " + output.strip()[-200:])
    if changed > MAX_CHANGED_LINES:
        problems.append(f"{changed} changed lines, limit {MAX_CHANGED_LINES}")
    if stray:
        problems.append("other files changed: " + ", ".join(stray))
    if problems:
        return graderlib.result(TASK, False, score, "; ".join(problems), changed_lines=changed)
    return graderlib.result(TASK, True, score, f"tests pass, {changed} changed lines", changed_lines=changed)


if __name__ == "__main__":
    sys.exit(graderlib.run_grader(TASK, grade, HERE))
