"""Tests for scripts/cve_track.py.

Run: python3 -m unittest discover -s scripts/tests -p 'test_cve_track.py'
"""

from __future__ import annotations

import datetime as dt
import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import cve_track  # noqa: E402


def finding(pname, cve, alert=False, runtime="runtime", kev=False, hosts=("a",), score=9.8, epss=0.01):
    return {"pname": pname, "cve": cve, "score": score, "epss": epss, "kev": kev, "versions": ["1"],
            "drvs": [f"/nix/store/x-{pname}.drv"], "hosts": list(hosts), "runtime": runtime,
            "alert": alert, "reasons": []}


def status(*findings, error=None):
    return {"threshold": 7.0, "epss_threshold": 0.1, "intel_error": error, "hosts": ["a", "b"],
            "open": list(findings)}


class TrackTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def run_track(self, st, previous=None, today="2026-11-24", fixes=None, *extra):
        (self.dir / "status.json").write_text(json.dumps(st))
        args = ["--status", str(self.dir / "status.json"), "--today", today,
                "--body", str(self.dir / "body.md"), "--alert", str(self.dir / "alert.md"),
                "--digest-out", str(self.dir / "digest.md"), *extra]
        for name in ("alert.md", "digest.md"):
            (self.dir / name).unlink(missing_ok=True)
        if previous is not None:
            (self.dir / "prev.md").write_text(previous)
            args += ["--previous", str(self.dir / "prev.md")]
        if fixes is not None:
            (self.dir / "fixes.json").write_text(json.dumps(fixes))
            args += ["--fixes", str(self.dir / "fixes.json")]
        with redirect_stdout(io.StringIO()):
            rc = cve_track.main(args)
        self.assertEqual(rc, 0)
        read = lambda n: (self.dir / n).read_text() if (self.dir / n).exists() else None  # noqa: E731
        return read("body.md"), read("alert.md"), read("digest.md")

    def test_first_run_makes_a_body_and_no_alert(self):
        body, alert, digest = self.run_track(status(finding("curl", "CVE-1", alert=True)), today="2026-11-23")
        self.assertTrue(body.startswith(cve_track.MARKER))
        self.assertIn("### Alerts (1)", body)
        self.assertIn("| a | 1 | 1 | 0 | 0 |", body)
        self.assertIsNone(alert)
        self.assertIsNone(digest)  # a Monday, but nothing to compare against yet
        self.assertEqual(cve_track.read_state(body)["alerts"], {"curl|CVE-1": "2026-11-23"})

    def test_new_alert_is_announced_once(self):
        body, _, _ = self.run_track(status(finding("curl", "CVE-1", alert=True)), today="2026-11-23")
        st = status(finding("curl", "CVE-1", alert=True), finding("zlib", "CVE-2", alert=True))
        body2, alert, _ = self.run_track(st, previous=body)
        self.assertIn("**1 new alert(s) on main.**", alert)
        self.assertIn("| zlib |", alert)
        self.assertNotIn("| curl |", alert)
        self.assertEqual(cve_track.read_state(body2)["alerts"]["curl|CVE-1"], "2026-11-23")
        _, alert3, _ = self.run_track(st, previous=body2, today="2026-11-25")
        self.assertIsNone(alert3)

    def test_old_finding_that_becomes_exploited_alerts(self):
        body, _, _ = self.run_track(status(finding("curl", "CVE-1", score=5.0)), today="2026-11-23")
        _, alert, _ = self.run_track(status(finding("curl", "CVE-1", score=5.0, alert=True, kev=True)), previous=body)
        self.assertIn("| curl |", alert)

    def test_build_only_findings_are_counted_not_listed(self):
        st = status(finding("gcc", "CVE-3", runtime="build"), finding("curl", "CVE-1"))
        body, _, _ = self.run_track(st)
        self.assertIn("1 more finding(s) are in packages that only build", body)
        self.assertNotIn("| gcc |", body)
        self.assertIn("### Other open findings that run on a host (1)", body)
        self.assertNotIn("gcc|CVE-3", json.dumps(cve_track.read_state(body)))

    def test_fixed_findings_are_remembered_for_the_digest(self):
        body, _, _ = self.run_track(status(finding("curl", "CVE-1"), finding("zlib", "CVE-2")), today="2026-11-10")
        body, _, _ = self.run_track(status(finding("curl", "CVE-1")), previous=body, today="2026-11-21")
        self.assertEqual(cve_track.read_state(body)["fixed"], {"zlib|CVE-2": "2026-11-21"})
        _, _, digest = self.run_track(status(finding("curl", "CVE-1"), finding("expat", "CVE-4")),
                                      previous=body, today="2026-11-23")
        self.assertIn("**2** finding(s) in packages that run on a host; **1** new in the last 7 days, **1** fixed.", digest)
        self.assertIn("Fixed this week: zlib CVE-2", digest)
        body, _, _ = self.run_track(status(), previous=body, today="2026-12-10")
        self.assertNotIn("zlib|CVE-2", json.dumps(cve_track.read_state(body)["fixed"]))

    def test_digest_only_on_mondays_unless_asked(self):
        body, _, _ = self.run_track(status(), today="2026-11-20")
        self.assertIsNone(self.run_track(status(), previous=body, today="2026-11-24")[2])
        self.assertIsNotNone(self.run_track(status(), body, "2026-11-24", None, "--digest")[2])

    def test_fix_column(self):
        st = status(finding("curl", "CVE-1", alert=True), finding("zlib", "CVE-2", alert=True))
        fixes = {"curl": {"note": "fixed in nixos-unstable (9)", "pr": "https://github.com/o/r/pull/5"},
                 "zlib": {"note": "no fixed version in nixpkgs yet"}}
        body, _, _ = self.run_track(st, fixes=fixes)
        self.assertIn("[fix PR](https://github.com/o/r/pull/5) |", body)
        self.assertIn("no fixed version in nixpkgs yet |", body)

    def test_body_stays_under_the_limit(self):
        many = [finding(f"pkg{i}", f"CVE-2026-{i}", score=5.0) for i in range(2000)]
        body, _, _ = self.run_track(status(*many))
        self.assertLessEqual(len(body), cve_track.BODY_LIMIT)
        self.assertIn("more not shown", body)
        self.assertEqual(len(cve_track.read_state(body)["open"]), 2000)

    def test_intel_outage_is_shown(self):
        body, _, _ = self.run_track(status(error="could not fetch KEV/EPSS data (x)"))
        self.assertIn("> [!WARNING]", body)
        self.assertIn("(CVSSv3 7.0+)", body)

    def test_unreadable_state_counts_as_first_run(self):
        self.assertIsNone(cve_track.read_state("<!-- cve-state:v2 bm90IHpsaWI= -->"))
        self.assertEqual(cve_track.next_state(None, [], dt.date(2026, 1, 1)), {"open": {}, "alerts": {}, "fixed": {}})


if __name__ == "__main__":
    unittest.main()
