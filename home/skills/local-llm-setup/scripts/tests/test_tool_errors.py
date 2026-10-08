import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "tool-errors.py"
spec = importlib.util.spec_from_file_location("tool_errors", SCRIPT)
tool_errors = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool_errors)


def tool_event(tool, status, error="", **tool_input):
    return json.dumps(
        {"type": "tool_use", "part": {"type": "tool", "tool": tool, "state": {"status": status, "error": error, "input": tool_input}}}
    )


class Classify(unittest.TestCase):
    def test_known_messages_map_to_kinds(self):
        c = tool_errors.classify
        self.assertEqual(c("The user has specified a rule which prevents you from using this specific tool call."), "denied")
        self.assertEqual(c("No changes to apply: oldString and newString are identical."), "identical")
        self.assertEqual(c("Could not find oldString in the file. It must match exactly"), "not_found")
        self.assertEqual(c("Found multiple matches for oldString. Provide more surrounding context"), "ambiguous")
        self.assertEqual(c("File not found: /x"), "missing_file")
        self.assertEqual(c("something unexpected"), "other")


class Summarise(unittest.TestCase):
    def test_counts_per_profile_and_task_and_ignores_successes(self):
        with tempfile.TemporaryDirectory() as root:
            logs = Path(root) / "inc-small-new" / "suite" / "logs"
            logs.mkdir(parents=True)
            (logs / "boundaries-1.events.jsonl").write_text(
                "\n".join(
                    [
                        tool_event("read", "error", "The user has specified a rule which prevents you from using this specific tool call."),
                        tool_event("read", "completed"),
                    ]
                )
            )
            (logs / "unittests-1.events.jsonl").write_text(
                "\n".join(
                    [
                        tool_event("edit", "error", "No changes to apply: oldString and newString are identical.", oldString="a", newString="a"),
                        tool_event("edit", "error", "Could not find oldString in the file.", oldString="    x", newString="    y"),
                    ]
                )
            )
            got = tool_errors.summarise(Path(root))
        self.assertEqual(got["inc-small-new"]["boundaries"], {"denied": 1})
        self.assertEqual(got["inc-small-new"]["unittests"], {"identical": 1, "not_found": 1})

    def test_skips_lines_that_are_not_json(self):
        with tempfile.TemporaryDirectory() as root:
            logs = Path(root) / "p" / "suite" / "logs"
            logs.mkdir(parents=True)
            (logs / "unittests-1.events.jsonl").write_text("not json\n" + tool_event("edit", "error", "File not found: /x"))
            got = tool_errors.summarise(Path(root))
        self.assertEqual(got["p"]["unittests"], {"missing_file": 1})


if __name__ == "__main__":
    unittest.main()
