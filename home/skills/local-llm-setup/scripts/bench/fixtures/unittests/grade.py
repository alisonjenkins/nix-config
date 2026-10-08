import ast
import shutil
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent / "lib"))

import graderlib  # noqa: E402

TASK = "unittests"
TEST_FILE = "test_device_scan.py"
MODULE_FILE = "device_scan.py"
TEST_MODULE = "test_device_scan"
EXPECTED_TEST_COUNT = 4
MIN_MUTANTS_KILLED = 3
WEIGHT_PASSES = 0.4
WEIGHT_KILLS = 0.4
WEIGHT_STYLE = 0.2
METHOD_GAP_LINES = 1
IMPORT_TO_CLASS_GAP_LINES = 2


def blank_line_violations(source):
    lines = source.splitlines()
    tree = ast.parse(source)
    problems = []

    def blanks_before(lineno):
        count = 0
        index = lineno - 2
        while index >= 0 and lines[index].strip() == "":
            count += 1
            index -= 1
        return count

    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            body_lines = lines[node.body[0].lineno - 1 : node.end_lineno]
            if any(line.strip() == "" for line in body_lines):
                problems.append(f"blank line inside {node.name}")
    for node in ast.walk(tree):
        if isinstance(node, ast.ClassDef):
            first = min([node.lineno] + [d.lineno for d in node.decorator_list])
            if blanks_before(first) != IMPORT_TO_CLASS_GAP_LINES:
                problems.append("class is not preceded by exactly two blank lines")
            methods = [n for n in node.body if isinstance(n, ast.FunctionDef)]
            for method in methods[1:]:
                start = min([method.lineno] + [d.lineno for d in method.decorator_list])
                if blanks_before(start) != METHOD_GAP_LINES:
                    problems.append(f"{method.name} is not preceded by exactly one blank line")
    return problems


def count_test_methods(source):
    tree = ast.parse(source)
    return sum(
        1
        for node in ast.walk(tree)
        if isinstance(node, ast.FunctionDef) and node.name.startswith("test_")
    )


def tests_pass_against(test_source, module_source):
    with tempfile.TemporaryDirectory() as scratch:
        (Path(scratch) / TEST_FILE).write_text(test_source, encoding="utf-8")
        (Path(scratch) / MODULE_FILE).write_text(module_source, encoding="utf-8")
        ok, output = graderlib.run_unittest(scratch, TEST_MODULE)
    return ok, output


def grade(workdir, reply, here):
    test_path = workdir / TEST_FILE
    if not test_path.is_file():
        return graderlib.result(TASK, False, 0.0, f"{TEST_FILE} was not created")
    test_source = test_path.read_text(encoding="utf-8")
    try:
        count = count_test_methods(test_source)
        style = blank_line_violations(test_source)
    except SyntaxError as exc:
        return graderlib.result(TASK, False, 0.0, f"{TEST_FILE} has a syntax error: {exc}")
    correct = (here / "input" / MODULE_FILE).read_text(encoding="utf-8")
    passes, output = tests_pass_against(test_source, correct)
    mutant_files = sorted((here / "mutants").glob("*.py"))
    killed = []
    survived = []
    for mutant in mutant_files:
        mutant_passes, _ = tests_pass_against(test_source, mutant.read_text(encoding="utf-8"))
        (survived if mutant_passes else killed).append(mutant.name)
    kills_ok = passes and len(killed) >= MIN_MUTANTS_KILLED
    score = 0.0
    if passes:
        score += WEIGHT_PASSES
        score += WEIGHT_KILLS * len(killed) / len(mutant_files)
    if not style:
        score += WEIGHT_STYLE
    problems = []
    if not passes:
        problems.append("tests fail against the correct module: " + output.strip()[-200:])
    elif not kills_ok:
        problems.append(f"only {len(killed)}/{len(mutant_files)} mutants killed (survived: {', '.join(survived)})")
    if count != EXPECTED_TEST_COUNT:
        problems.append(f"{count} test methods, expected {EXPECTED_TEST_COUNT}")
    problems.extend(style)
    details = {"mutants_killed": len(killed), "mutants_total": len(mutant_files), "survived": survived}
    if problems:
        return graderlib.result(TASK, False, score, "; ".join(problems), **details)
    return graderlib.result(TASK, True, score, f"passes, kills {len(killed)}/{len(mutant_files)} mutants, style ok", **details)


if __name__ == "__main__":
    sys.exit(graderlib.run_grader(TASK, grade, HERE))
