import difflib
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent / "lib"))

import graderlib  # noqa: E402

TASK = "multiedit"
TARGET = "test_registry.py"
TARGET_MODULE = "test_registry"
PENALTY_COLLATERAL = 0.25
PENALTY_TESTS_FAIL = 0.25


def hunks(before, after):
    matcher = difflib.SequenceMatcher(None, before, after, autojunk=False)
    return [op for op in matcher.get_opcodes() if op[0] != "equal"]


def core(lines):
    start, end = 0, len(lines)
    while start < end and lines[start].strip() == "":
        start += 1
    while end > start and lines[end - 1].strip() == "":
        end -= 1
    return "\n".join(lines[start:end])


def edit_footprint(before, after):
    removed = set()
    added = Counter()
    for _, i1, i2, j1, j2 in hunks(before, after):
        removed.update(range(i1, i2))
        added.update(after[j1:j2])
    return removed, added


def grade(workdir, reply, here):
    original = (here / "input" / TARGET).read_text(encoding="utf-8")
    expected = (here / "solution" / TARGET).read_text(encoding="utf-8")
    path = workdir / TARGET
    if not path.is_file():
        return graderlib.result(TASK, False, 0.0, f"{TARGET} is missing")
    actual = path.read_text(encoding="utf-8")
    before, wanted, got = original.splitlines(), expected.splitlines(), actual.splitlines()

    sites = hunks(before, wanted)
    landed = 0
    missing = []
    for number, (_, i1, i2, j1, j2) in enumerate(sites, start=1):
        added_core = core(wanted[j1:j2])
        removed_core = core(before[i1:i2])
        present = added_core in actual and actual.count(added_core) == expected.count(added_core)
        gone = not removed_core or actual.count(removed_core) < original.count(removed_core)
        if present and gone:
            landed += 1
        else:
            missing.append(number)

    wanted_removed, wanted_added = edit_footprint(before, wanted)
    got_removed, got_added = edit_footprint(before, got)
    extra_removed = len(got_removed - wanted_removed)
    extra_added = sum((got_added - wanted_added).values())
    collateral = extra_removed + extra_added

    tests_ok, output = graderlib.run_unittest(workdir, TARGET_MODULE)
    score = landed / len(sites)
    if collateral:
        score -= PENALTY_COLLATERAL
    if not tests_ok:
        score -= PENALTY_TESTS_FAIL
    problems = []
    if missing:
        problems.append(f"edits not landed exactly: {missing}")
    if collateral:
        problems.append(f"{collateral} collateral changed lines outside the edit sites")
    if not tests_ok:
        problems.append("module tests fail: " + output.strip()[-200:])
    details = {"edits_landed": landed, "edits_total": len(sites), "collateral_lines": collateral, "exact": actual == expected}
    if problems:
        return graderlib.result(TASK, False, score, "; ".join(problems), **details)
    return graderlib.result(TASK, True, score, f"all {len(sites)} edits landed, no collateral, tests pass", **details)


if __name__ == "__main__":
    sys.exit(graderlib.run_grader(TASK, grade, HERE))
