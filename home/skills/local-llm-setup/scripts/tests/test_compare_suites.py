import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "compare-suites.py"
spec = importlib.util.spec_from_file_location("compare_suites", SCRIPT)
compare_suites = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compare_suites)


def row(task, rep, passed, exit_code=0, failed=0, seconds=10.0):
    return {"task": task, "rep": rep, "pass": passed, "exit_code": exit_code, "failed_tool_calls": failed, "seconds": seconds}


class Summarise(unittest.TestCase):
    def test_excludes_explain_and_boundaries_from_the_graded_and_abnormal_counts(self):
        rows = [
            row("newmodule", 1, True),
            row("unittests", 1, False, exit_code=3, failed=5, seconds=40.0),
            row("explain", 1, False),
            row("boundaries", 1, True, exit_code=3, failed=6),
        ]
        got = compare_suites.summarise(rows)
        self.assertEqual(got["graded"], (1, 2))
        self.assertEqual(got["abnormal"], 1)
        self.assertEqual(got["failed_calls"], 5)
        self.assertEqual(got["boundaries_exits"], [3])

    def test_median_seconds_per_task(self):
        rows = [row("newmodule", 1, True, seconds=10.0), row("newmodule", 2, True, seconds=30.0), row("newmodule", 3, True, seconds=20.0)]
        self.assertEqual(compare_suites.summarise(rows)["median_seconds"]["newmodule"], 20.0)


class Load(unittest.TestCase):
    def test_reads_every_profile_directory(self):
        with tempfile.TemporaryDirectory() as root:
            for name in ("a-new", "b-new"):
                suite = Path(root) / name / "suite"
                suite.mkdir(parents=True)
                (suite / "results.jsonl").write_text(json.dumps(row("newmodule", 1, True)) + "\n")
            got = compare_suites.load(Path(root))
        self.assertEqual(sorted(got), ["a-new", "b-new"])


if __name__ == "__main__":
    unittest.main()
