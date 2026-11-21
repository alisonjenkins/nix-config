"""slice.sh gate tests. Run: python3 -m unittest discover -s scripts/tests (from the skill directory)"""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from test_check_model import tetra, write_3mf


class SliceScriptGate(unittest.TestCase):
    """slice.sh must stop on the model check before it ever calls the slicer."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self._tmp.name)
        stub = self.dir / "bin"
        stub.mkdir()
        slicer = stub / "qidi-studio"
        slicer.write_text("#!/bin/sh\necho SLICER_CALLED >&2\nexit 1\n")
        slicer.chmod(0o755)
        self.env = {**os.environ, "PATH": f"{stub}:{os.environ['PATH']}"}
        self.script = Path(__file__).resolve().parent.parent / "slice.sh"
        self.overrides = self.dir / "o.json"
        self.overrides.write_text("{}")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def run_slice(self, model: Path, **extra: str) -> subprocess.CompletedProcess[str]:
        env = {**self.env, **extra}
        return subprocess.run(
            [
                "bash",
                str(self.script),
                str(model),
                str(self.overrides),
                str(self.dir / "out"),
            ],
            env=env,
            capture_output=True,
            text=True,
        )

    def test_loose_pieces_stop_before_the_slicer(self) -> None:
        m = self.dir / "two.3mf"
        write_3mf(m, [tetra(0), tetra(10)])
        r = self.run_slice(m)
        self.assertEqual(r.returncode, 1)
        self.assertIn("found 2", r.stderr)
        self.assertNotIn("SLICER_CALLED", r.stderr)

    def test_unreadable_model_says_so_and_stops(self) -> None:
        m = self.dir / "bad.3mf"
        m.write_text("nope")
        r = self.run_slice(m)
        self.assertEqual(r.returncode, 1)
        self.assertIn("could not check", r.stderr)
        self.assertNotIn("SLICER_CALLED", r.stderr)

    def test_parts_zero_skips_the_check(self) -> None:
        m = self.dir / "bad.3mf"
        m.write_text("nope")
        r = self.run_slice(m, QIDI_PARTS="0")
        self.assertIn("SLICER_CALLED", r.stderr + r.stdout)  # got past the gate


if __name__ == "__main__":
    unittest.main()
