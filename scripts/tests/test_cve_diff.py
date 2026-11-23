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


def drv(pname, version):
    return f"/nix/store/x-{pname}-{version}.drv"


def item(pname, version, cves, scores=None):
    return {
        "name": f"{pname}-{version}",
        "pname": pname,
        "version": version,
        "derivation": drv(pname, version),
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
        self.assertIn("No new CVE fails the gate (CVSSv3 7.0+)", out)

    def test_new_high_cve_fails(self):
        rc, out = self.run_diff(
            [],
            [item("curl", "8.20.0", ["CVE-2026-2"], {"CVE-2026-2": 7.5})],
        )
        self.assertEqual(rc, 1)
        self.assertIn("1 new CVE(s) that fail the gate", out)
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
        self.assertIn("New, below the gate", out)

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

    def test_expired_version_selector_covers_only_that_version(self):
        report = [item("openssl", "3.5", ["CVE-2026-1"], {"CVE-2026-1": 9.8})]
        wl = self.whitelist('["openssl-3.0"]\ncve = ["CVE-2026-1"]\nuntil = "2026-11-01"\ncomment = "x"\n')
        rc, _ = self.run_diff(report, report, "--whitelist", str(wl), "--today", "2026-11-23")
        self.assertEqual(rc, 0)
        wl = self.whitelist('["openssl-3.5"]\ncve = ["CVE-2026-1"]\nuntil = "2026-11-01"\ncomment = "x"\n')
        rc, _ = self.run_diff(report, report, "--whitelist", str(wl), "--today", "2026-11-23")
        self.assertEqual(rc, 1)

    def test_has_expired(self):
        def has(text):
            with redirect_stdout(io.StringIO()):
                return cve_diff.main(["--has-expired", str(self.whitelist(text)), "--today", "2026-11-23"])
        self.assertEqual(has('["a"]\ncve = ["CVE-1"]\nuntil = "2026-11-01"\ncomment = "x"\n'), 0)
        self.assertEqual(has('["a"]\ncve = ["CVE-1"]\nuntil = "2026-12-01"\ncomment = "x"\n'), 1)
        self.assertEqual(has(""), 1)

    def test_exception_in_date_does_not_fail(self):
        report = [item("openssl", "3.5", ["CVE-2026-1"], {"CVE-2026-1": 9.8})]
        wl = self.whitelist('["openssl"]\ncve = ["CVE-2026-1"]\nuntil = "2026-12-01"\ncomment = "x"\n')
        rc, _ = self.run_diff(report, report, "--whitelist", str(wl), "--today", "2026-11-23")
        self.assertEqual(rc, 0)

    def intel(self, kev=(), epss=None, error=None):
        p = self.dir / "intel.json"
        data = {"kev": list(kev), "epss": epss or {}}
        if error:
            data["error"] = error
        p.write_text(json.dumps(data))
        return ["--intel", str(p)]

    def test_new_kev_cve_fails_whatever_its_score(self):
        head = [item("expat", "2.7", ["CVE-2026-8"], {"CVE-2026-8": 5.3}), item("zlib", "1.3", ["CVE-2026-9"])]
        rc, out = self.run_diff([], head, *self.intel(kev=["CVE-2026-8", "CVE-2026-9"]))
        self.assertEqual(rc, 1)
        self.assertIn("2 new CVE(s) that fail the gate (CVSSv3 7.0+, in CISA KEV, or EPSS 10%+)", out)
        self.assertIn("- expat CVE-2026-8: known exploited (CISA KEV)", out)
        self.assertIn("| zlib | 1.3 | [CVE-2026-9](https://nvd.nist.gov/vuln/detail/CVE-2026-9) | unscored | - | yes |", out)

    def test_new_high_epss_cve_fails(self):
        head = [item("expat", "2.7", ["CVE-2026-8"], {"CVE-2026-8": 4.0})]
        rc, out = self.run_diff([], head, *self.intel(epss={"CVE-2026-8": 0.42}))
        self.assertEqual(rc, 1)
        self.assertIn("- expat CVE-2026-8: EPSS 42%", out)
        self.assertEqual(self.run_diff([], head, *self.intel(epss={"CVE-2026-8": 0.42}), "--epss-threshold", "0.5")[0], 0)

    def test_low_epss_medium_cve_passes(self):
        head = [item("expat", "2.7", ["CVE-2026-8"], {"CVE-2026-8": 5.0})]
        rc, out = self.run_diff([], head, *self.intel(epss={"CVE-2026-8": 0.01}))
        self.assertEqual(rc, 0)
        self.assertIn("| 1.0% |  |", out)

    def test_failing_are_ordered_by_exploitation_likelihood(self):
        head = [
            item("a", "1", ["CVE-2026-10"], {"CVE-2026-10": 9.9}),
            item("b", "1", ["CVE-2026-11"], {"CVE-2026-11": 7.0}),
            item("c", "1", ["CVE-2026-12"], {"CVE-2026-12": 8.0}),
        ]
        _, out = self.run_diff([], head, *self.intel(kev=["CVE-2026-11"], epss={"CVE-2026-12": 0.3}))
        self.assertLess(out.index("| b |"), out.index("| c |"))
        self.assertLess(out.index("| c |"), out.index("| a |"))

    def test_pre_existing_kev_cve_is_listed_not_failed(self):
        report = [item("openssl", "3.5", ["CVE-2026-1"], {"CVE-2026-1": 5.0})]
        rc, out = self.run_diff(report, report, *self.intel(kev=["CVE-2026-1"]))
        self.assertEqual(rc, 0)
        self.assertIn("Known exploited, already on the base and still open (1)", out)

    def test_intel_outage_falls_back_to_cvss_loudly(self):
        head = [item("expat", "2.7", ["CVE-2026-8"], {"CVE-2026-8": 5.0})]
        err = io.StringIO()
        with mock.patch("sys.stderr", err):
            rc, out = self.run_diff([], head, *self.intel(error="could not fetch KEV/EPSS data (timeout)"))
        self.assertEqual(rc, 0)
        self.assertIn("> [!WARNING]", out)
        self.assertIn("No new CVE fails the gate (CVSSv3 7.0+)", out)
        self.assertIn("judging by CVSS alone", err.getvalue())

    def test_fetch_intel_failure_is_an_outage_not_a_crash(self):
        with mock.patch.object(cve_diff, "_get_json", side_effect=OSError("no route")):
            intel = cve_diff.fetch_intel({"CVE-2026-1"})
        self.assertIn("no route", intel.error)
        self.assertEqual(intel.kev, set())

    def test_fetch_intel_batches_epss(self):
        cves = {f"CVE-2026-{i}" for i in range(120)} | {"not-a-cve"}
        calls = []

        def fake(url):
            calls.append(url)
            if url == cve_diff.KEV_URL:
                return {"vulnerabilities": [{"cveID": "CVE-2026-3"}]}
            asked = cve_diff.urllib.parse.parse_qs(cve_diff.urllib.parse.urlparse(url).query)["cve"][0].split(",")
            return {"data": [{"cve": c, "epss": "0.5"} for c in asked]}

        with mock.patch.object(cve_diff, "_get_json", side_effect=fake):
            intel = cve_diff.fetch_intel(cves)
        self.assertIsNone(intel.error)
        self.assertEqual(intel.kev, {"CVE-2026-3"})
        self.assertEqual(len(intel.epss), 120)
        self.assertEqual(len(calls), 1 + 3)

    def closures(self, side, hosts):
        d = self.dir / f"closures-{side}"
        d.mkdir()
        for host, paths in hosts.items():
            (d / host).write_text("\n".join(paths) + "\n")
        return str(d)

    def test_findings_are_attributed_to_hosts(self):
        base = [item("glibc", "2.42", ["CVE-2026-6"], {"CVE-2026-6": 7.8}), item("zlib", "1.3", ["CVE-2026-3"], {"CVE-2026-3": 5.0})]
        head = [item("curl", "8.20", ["CVE-2026-2"], {"CVE-2026-2": 7.5}), item("zlib", "1.3", ["CVE-2026-3"], {"CVE-2026-3": 5.0})]
        rc, out = self.run_diff(
            base,
            head,
            "--base-closures",
            self.closures("base", {"desk": [drv("glibc", "2.42"), drv("zlib", "1.3")], "srv": [drv("zlib", "1.3")]}),
            "--head-closures",
            self.closures("head", {"desk": [drv("zlib", "1.3")], "srv": [drv("curl", "8.20"), drv("zlib", "1.3")]}),
        )
        self.assertEqual(rc, 1)
        self.assertIn("Scanned 2 host(s)", out)
        self.assertIn("| desk | 0 | 0 | 1 | 1 | 0 |", out)
        self.assertIn("| srv | 1 | 1 | 0 | 1 | 0 |", out)
        self.assertIn("| curl | 8.20 | [CVE-2026-2](https://nvd.nist.gov/vuln/detail/CVE-2026-2) | 7.5 | srv |", out)
        self.assertIn("| glibc | 2.42 | [CVE-2026-6](https://nvd.nist.gov/vuln/detail/CVE-2026-6) | 7.8 | desk |", out)

    def test_closures_must_come_in_pairs(self):
        with redirect_stdout(io.StringIO()), mock.patch("sys.stderr", io.StringIO()), self.assertRaises(SystemExit):
            cve_diff.main([str(self.write("b.json", [])), str(self.write("h.json", [])), "--head-closures", str(self.dir)])

    def test_summary_can_go_to_several_files(self):
        a, b = self.dir / "a.md", self.dir / "b.md"
        self.run_diff([], [], "--summary", str(a), "--summary", str(b))
        self.assertEqual(a.read_text(), b.read_text())

    def runtime_dirs(self, runtime):
        """Closures where every finding's drv is on host srv, plus runtime listings."""
        h = "0" * 32
        rt = self.dir / "runtime"
        rt.mkdir()
        for host, names in runtime.items():
            (rt / host).write_text("".join(f"/nix/store/{h}-{n}\n" for n in names))
        return str(rt)

    def gate_with_runtime(self, head, runtime, *extra):
        closures = {"srv": [d for i in head for d in [i["derivation"]]]}
        return self.run_diff(
            [],
            head,
            "--base-closures", self.closures("base", {"srv": []}),
            "--head-closures", self.closures("head", closures),
            "--runtime", self.runtime_dirs(runtime),
            *extra,
        )

    def test_in_runtime_matches_name_and_version(self):
        names = {"curl-8.20.0-bin", "python3.13-requests-2.32.3", "curl-impersonate-1.0"}
        self.assertTrue(cve_diff.in_runtime("curl", names))
        self.assertTrue(cve_diff.in_runtime("python3.13-requests", names))
        self.assertFalse(cve_diff.in_runtime("python3.13-req", names))
        self.assertFalse(cve_diff.in_runtime("gcc", names))
        self.assertFalse(cve_diff.in_runtime("curl-impersonate-1", {"curl-impersonate-10"}))

    def test_build_only_high_cve_does_not_fail(self):
        head = [item("gcc", "14", ["CVE-2026-20"], {"CVE-2026-20": 9.8})]
        rc, out = self.gate_with_runtime(head, {"srv": ["glibc-2.42", "openssl-3.5.1"]})
        self.assertEqual(rc, 0)
        self.assertIn("New, build-time only (1, not failing)", out)
        self.assertIn("| build only | srv |", out)

    def test_runtime_high_cve_fails(self):
        head = [item("openssl", "3.5.2", ["CVE-2026-21"], {"CVE-2026-21": 9.8})]
        rc, out = self.gate_with_runtime(head, {"srv": ["openssl-3.5.1-bin"]})
        self.assertEqual(rc, 1)
        self.assertIn("| yes | srv |", out)

    def test_build_only_kev_cve_still_fails(self):
        head = [item("gcc", "14", ["CVE-2026-20"], {"CVE-2026-20": 5.0})]
        rc, out = self.gate_with_runtime(head, {"srv": []}, *self.intel(kev=["CVE-2026-20"]))
        self.assertEqual(rc, 1)
        self.assertIn("known exploited (CISA KEV), though build-time only", out)

    def test_host_without_runtime_data_is_unknown_and_fails(self):
        head = [item("gcc", "14", ["CVE-2026-20"], {"CVE-2026-20": 9.8})]
        rc, out = self.gate_with_runtime(head, {"other": []})
        self.assertEqual(rc, 1)
        self.assertIn("| unknown | srv |", out)

    def test_json_output(self):
        out_json = self.dir / "out.json"
        head = [item("gcc", "14", ["CVE-2026-20"], {"CVE-2026-20": 9.8})]
        self.gate_with_runtime(head, {"srv": []}, "--json", str(out_json))
        data = json.loads(out_json.read_text())
        self.assertEqual(data["hosts"], ["srv"])
        [f] = data["build_only"]
        self.assertEqual((f["cve"], f["runtime"], f["alert"], f["hosts"]), ("CVE-2026-20", "build", False, ["srv"]))

    def test_status_mode_lists_open_findings_and_never_fails(self):
        out_json = self.dir / "status.json"
        report = self.write("status-in.json", [item("curl", "8", ["CVE-2026-2"], {"CVE-2026-2": 9.8})])
        out = io.StringIO()
        with redirect_stdout(out):
            rc = cve_diff.main(["--status", str(report), "--json", str(out_json)])
        self.assertEqual(rc, 0)
        self.assertIn("1 open finding(s), 1 that would fail the gate", out.getvalue())
        data = json.loads(out_json.read_text())
        self.assertTrue(data["open"][0]["alert"])
        self.assertNotIn("failing", data)


if __name__ == "__main__":
    unittest.main()
