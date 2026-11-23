"""Tests for scripts/cve_diff.py.

Run: python3 -m unittest discover -s scripts/tests -p 'test_cve_diff.py'
"""

from __future__ import annotations

import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import cve_diff  # noqa: E402


def item(pname, version, cves, scores=None):
    return {
        "name": f"{pname}-{version}",
        "pname": pname,
        "version": version,
        "derivation": f"/nix/store/x-{pname}-{version}.drv",
        "affected_by": cves,
        "whitelisted": [],
        "cvssv3_basescore": scores or {},
        "description": {},
    }


class CveDiffTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, name, items):
        p = self.dir / name
        p.write_text(json.dumps(items))
        return p

    def run_diff(self, base, head, *extra):
        out = io.StringIO()
        with redirect_stdout(out):
            rc = cve_diff.main([str(self.write("base.json", base)), str(self.write("head.json", head)), *extra])
        return rc, out.getvalue()

    def test_same_cve_after_version_bump_is_not_new(self):
        rc, out = self.run_diff(
            [item("openssl", "3.5.1", ["CVE-2026-1"], {"CVE-2026-1": 9.8})],
            [item("openssl", "3.5.2", ["CVE-2026-1"], {"CVE-2026-1": 9.8})],
        )
        self.assertEqual(rc, 0)
        self.assertIn("No new CVE scored 7.0 or higher", out)

    def test_new_high_cve_fails(self):
        rc, out = self.run_diff(
            [],
            [item("curl", "8.20.0", ["CVE-2026-2"], {"CVE-2026-2": 7.5})],
        )
        self.assertEqual(rc, 1)
        self.assertIn("1 new CVE(s) scored 7.0 or higher", out)
        self.assertIn("| curl | 8.20.0 | [CVE-2026-2]", out)

    def test_new_medium_and_unscored_warn_only(self):
        rc, out = self.run_diff(
            [],
            [
                item("zlib", "1.3", ["CVE-2026-3"], {"CVE-2026-3": 5.3}),
                item("expat", "2.7", ["CVE-2026-4"]),
            ],
        )
        self.assertEqual(rc, 0)
        self.assertIn("New, not yet scored by NVD", out)
        self.assertIn("| expat | 2.7 | [CVE-2026-4](https://nvd.nist.gov/vuln/detail/CVE-2026-4) | unscored |", out)
        self.assertIn("New, scored below 7.0", out)

    def test_cve_moving_to_another_package_is_new(self):
        rc, _ = self.run_diff(
            [item("libxml2", "2.14", ["CVE-2026-5"], {"CVE-2026-5": 8.1})],
            [item("libxslt", "1.1", ["CVE-2026-5"], {"CVE-2026-5": 8.1})],
        )
        self.assertEqual(rc, 1)

    def test_fixed_cves_are_listed(self):
        rc, out = self.run_diff(
            [item("glibc", "2.42", ["CVE-2026-6"], {"CVE-2026-6": 7.8})],
            [],
        )
        self.assertEqual(rc, 0)
        self.assertIn("Fixed by this change (1)", out)

    def test_threshold_is_configurable(self):
        base, head = [], [item("bash", "5.3", ["CVE-2026-7"], {"CVE-2026-7": 9.1})]
        self.assertEqual(self.run_diff(base, head, "--threshold", "9.5")[0], 0)
        self.assertEqual(self.run_diff(base, head, "--threshold", "9.0")[0], 1)

    def test_summary_file_is_appended(self):
        summary = self.dir / "summary.md"
        summary.write_text("before\n")
        self.run_diff([], [], "--summary", str(summary))
        self.assertTrue(summary.read_text().startswith("before\n## CVE scan (vulnix)"))

    def test_bad_input_exits_2(self):
        bad = self.dir / "bad.json"
        bad.write_text("{}")
        good = self.write("good.json", [])
        with redirect_stdout(io.StringIO()):
            self.assertEqual(cve_diff.main([str(bad), str(good)]), 2)
            self.assertEqual(cve_diff.main([str(self.dir / "missing.json"), str(good)]), 2)

    def whitelist(self, text):
        p = self.dir / "wl.toml"
        p.write_text(text)
        return p

    def check(self, text, today="2026-11-23"):
        err = io.StringIO()
        with redirect_stdout(io.StringIO()), mock.patch("sys.stderr", err):
            rc = cve_diff.main(["--check-whitelist", str(self.whitelist(text)), "--today", today])
        return rc, err.getvalue()

    def test_valid_whitelist_passes(self):
        rc, err = self.check(
            '["openssl"]\ncve = ["CVE-2026-1"]\nuntil = "2027-01-15"\ncomment = "QUIC server only"\n'
        )
        self.assertEqual((rc, err), (0, ""))

    def test_empty_whitelist_passes(self):
        self.assertEqual(self.check("# nothing accepted\n")[0], 0)

    def test_whitelist_rejects_broad_or_open_ended_entries(self):
        rc, err = self.check(
            '["*"]\ncve = ["CVE-2026-1"]\nuntil = "2027-01-01"\ncomment = "x"\n'
            '["curl"]\ncomment = "all of curl"\nuntil = "2027-01-01"\n'
            '["zlib"]\ncve = ["CVE-2026-2"]\nuntil = "2027-01-01"\n'
            '["expat"]\ncve = ["CVE-2026-3"]\ncomment = "x"\n'
            '["bash"]\ncve = ["CVE-2026-4"]\ncomment = "x"\nuntil = "2027-06-01"\n'
        )
        self.assertEqual(rc, 2)
        self.assertIn('["*"]: must name one exact package', err)
        self.assertIn('["curl"]: needs a non-empty cve list', err)
        self.assertIn('["zlib"]: needs a comment', err)
        self.assertIn('["expat"]: needs an until date', err)
        self.assertIn('["bash"]: until 2027-06-01 is more than 90 days away', err)

    def test_expired_exception_fails_even_when_base_has_it(self):
        report = [item("openssl", "3.5", ["CVE-2026-1"], {"CVE-2026-1": 9.8})]
        wl = self.whitelist('["openssl"]\ncve = ["CVE-2026-1"]\nuntil = "2026-11-01"\ncomment = "x"\n')
        rc, out = self.run_diff(report, report, "--whitelist", str(wl), "--today", "2026-11-23")
        self.assertEqual(rc, 1)
        self.assertIn("1 accepted CVE(s) whose exception", out)

    def test_exception_in_date_does_not_fail(self):
        report = [item("openssl", "3.5", ["CVE-2026-1"], {"CVE-2026-1": 9.8})]
        wl = self.whitelist('["openssl"]\ncve = ["CVE-2026-1"]\nuntil = "2026-12-01"\ncomment = "x"\n')
        rc, _ = self.run_diff(report, report, "--whitelist", str(wl), "--today", "2026-11-23")
        self.assertEqual(rc, 0)


if __name__ == "__main__":
    unittest.main()
