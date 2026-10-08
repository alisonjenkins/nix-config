import json
import shutil
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent / "lib"))

import graderlib  # noqa: E402

TASK = "newmodule"
REQUIREMENT_COUNT = 6
MODULE_FILE = "keystate.py"
CHECK_TIMEOUT_SECONDS = 30


def grade(workdir, reply, here):
    source = workdir / MODULE_FILE
    if not source.is_file():
        return graderlib.result(TASK, False, 0.0, f"{MODULE_FILE} was not created")
    with tempfile.TemporaryDirectory() as isolated:
        shutil.copy(source, Path(isolated) / MODULE_FILE)
        code, output = graderlib.run_python(
            ["-I", "-B", str(here / "checks.py"), isolated, str(here / "input")],
            isolated,
            timeout=CHECK_TIMEOUT_SECONDS,
        )
    try:
        outcome = json.loads(output.strip().splitlines()[-1])
    except (ValueError, IndexError):
        return graderlib.result(TASK, False, 0.0, f"checks crashed (exit {code}): {output[-300:]}")
    if "import_error" in outcome:
        return graderlib.result(TASK, False, 0.0, f"import failed: {outcome['import_error']}")
    failed = sorted(name for name, ok in outcome.items() if not ok)
    score = (REQUIREMENT_COUNT - len(failed)) / REQUIREMENT_COUNT
    if failed:
        return graderlib.result(TASK, False, score, "failed requirements: " + ", ".join(failed))
    return graderlib.result(TASK, True, 1.0, "all 6 requirements hold")


if __name__ == "__main__":
    sys.exit(graderlib.run_grader(TASK, grade, HERE))
