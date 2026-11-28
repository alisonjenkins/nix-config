"""Tests for scripts/cve_fix.py, with a fake command runner.

Run: python3 -m unittest discover -s scripts/tests -p 'test_cve_fix.py'
"""

from __future__ import annotations

import datetime as dt
import io
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import cve_fix  # noqa: E402
import pins  # noqa: E402

CUR = "/nix/store/c-curl-8.drv"


def done(rc=0, out=""):
    return subprocess.CompletedProcess([], rc, out, "")


class FakeRunner:
    """Answers the commands cve_fix runs from the tables it was given."""

    def __init__(self, infos, flagged, referrers=(), prs="[]", scan_fixed=("CVE-1",), scan_rc=0):
        self.infos = infos  # {(ref, attr): info}
        self.flagged = flagged  # {drv: [cves still reported for curl]}
        self.referrers = list(referrers)
        self.prs = prs
        self.scan_fixed = scan_fixed
        self.scan_rc = scan_rc
        self.calls = []

    def __call__(self, cmd, timeout=0, cwd=None, env=None):
        self.calls.append(cmd)
        if cmd[:2] == ["nix", "eval"]:
            ref, attr = cmd[4].split("#")
            info = self.infos.get((ref, attr))
            return done(0, json.dumps(info)) if info else done(1)
        if cmd[:2] == ["nix", "path-info"]:
            ref, attr = cmd[-1].split("#")
            info = self.infos.get((ref, attr))
            return done(0, info["drvPath"] + "\n") if info else done(1)
        if cmd[:2] == ["nix", "shell"]:
            drv = cmd[-1]
            cves = self.flagged.get(drv, [])
            return done(2 if cves else 0, json.dumps([{"pname": "curl", "affected_by": cves}] if cves else []))
        if cmd[:3] == ["nix-store", "--query", "--referrers-closure"]:
            return done(0, "\n".join(self.referrers))
        if cmd[:3] == ["gh", "pr", "list"]:
            return done(0, self.prs)
        if cmd[:3] == ["gh", "pr", "create"]:
            return done(0, "https://github.com/o/r/pull/7\n")
        if cmd[0] == "git" and "worktree" in cmd and "add" in cmd:
            wt = Path(cmd[-2])
            for rel in (cve_fix.FIXES_FILE, cve_fix.REGISTRY_FILE):
                (wt / rel).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy(cve_fix.REPO / rel, wt / rel)
            return done()
        if cmd[0] == "scripts/cve-scan.sh":
            Path(env["CVE_JSON"]).write_text(json.dumps(
                {"failing": [], "fixed": [{"pname": "curl", "cve": c} for c in self.scan_fixed]}))
            Path(env["CVE_REPORT"]).write_text("## CVE scan (vulnix)\n")
            self.wt = Path(cwd)
            self.written = {rel: (Path(cwd) / rel).read_text()
                            for rel in (cve_fix.FIXES_FILE, cve_fix.REGISTRY_FILE)}
            return done(self.scan_rc)
        if cmd[0] == "git":
            return done()
        raise AssertionError(f"unexpected command {cmd}")


def info(version, drv):
    return {"pname": "curl", "version": version, "drvPath": drv}


LOCKED = "github:NixOS/nixpkgs/abc"


class FixTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        (self.dir / "closures").mkdir()
        (self.dir / "closures" / "srv").write_text(f"{CUR}\n/nix/store/r1.drv\n/nix/store/r2.drv\n")
        (self.dir / "flake.lock").write_text(json.dumps(
            {"root": "root", "nodes": {"root": {"inputs": {"nixpkgs": "nixpkgs"}}, "nixpkgs": {"locked": {"rev": "abc"}}}}))
        (self.dir / "status.json").write_text(json.dumps({"open": [
            {"pname": "curl", "cve": "CVE-1", "alert": True, "drvs": [CUR], "hosts": ["srv"], "versions": ["8"]},
            {"pname": "zlib", "cve": "CVE-9", "alert": False, "drvs": [], "hosts": ["srv"], "versions": ["1"]},
        ]}))

    def tearDown(self):
        self.tmp.cleanup()

    def run_fix(self, runner, *extra):
        out = self.dir / "fixes.json"
        args = ["--status", str(self.dir / "status.json"), "--closures", str(self.dir / "closures"),
                "--out", str(out), "--lock", str(self.dir / "flake.lock"), "--today", "2026-11-24", *extra]
        with redirect_stdout(io.StringIO()):
            self.assertEqual(cve_fix.main(args, run=runner), 0)
        return json.loads(out.read_text())

    def infos(self, channel=None, unstable=None, master=None):
        out = {(LOCKED, "curl"): info("8", CUR)}
        for ref, v in ((cve_fix.CHANNEL, channel), (cve_fix.UNSTABLE, unstable), (cve_fix.MASTER, master)):
            out[(ref, "curl")] = info(v or "8", f"/nix/store/{ref[-6:]}-curl.drv")
        return out

    def test_only_alerted_packages_are_looked_at(self):
        res = self.run_fix(FakeRunner(self.infos(), {}))
        self.assertEqual(list(res), ["curl"])

    def test_not_a_top_level_package(self):
        res = self.run_fix(FakeRunner({}, {}))
        self.assertIn("needs a person", res["curl"]["note"])

    def test_fixed_in_the_channel_waits_for_the_nightly(self):
        res = self.run_fix(FakeRunner(self.infos(channel="8.1"), {}))
        self.assertEqual(res["curl"]["note"], "fixed in nixos-26.05 (8.1); the nightly update brings it")

    def test_a_newer_version_still_flagged_is_not_a_fix(self):
        infos = self.infos(channel="8.1", unstable="8.2")
        flagged = {"/nix/store/-26.05-curl.drv": ["CVE-1"]}  # the channel's 8.1 is not a fix
        res = self.run_fix(FakeRunner(infos, flagged, referrers=["/nix/store/r1.drv"]))
        self.assertEqual(res["curl"]["note"], "fixed in nixos-unstable (8.2)")

    def test_fixed_in_unstable_with_big_rebuild_waits(self):
        res = self.run_fix(FakeRunner(self.infos(unstable="9"), {}, referrers=["/nix/store/r1.drv"]), "--max-rebuilds", "0")
        self.assertIn("would rebuild 1 derivations; wait for nixos-26.05", res["curl"]["note"])

    def test_fixed_only_in_master_is_noted(self):
        res = self.run_fix(FakeRunner(self.infos(master="9"), {}))
        self.assertEqual(res["curl"]["note"], "fixed in nixpkgs master (9), not yet in a channel")

    def test_no_fix_anywhere(self):
        res = self.run_fix(FakeRunner(self.infos(), {}))
        self.assertEqual(res["curl"]["note"], "no fixed version in nixpkgs yet")

    def test_dry_run_opens_nothing(self):
        runner = FakeRunner(self.infos(unstable="9"), {}, referrers=["/nix/store/r1.drv"])
        res = self.run_fix(runner)
        self.assertNotIn("pr", res["curl"])
        self.assertFalse(any(c[0] in ("gh", "git") for c in runner.calls))

    def apply(self, runner):
        return self.run_fix(runner, "--apply", "--repo", "o/r", "--base-sha", "deadbeef",
                            "--ready", str(self.dir / "ready.json"))

    def publish(self, runner):
        with redirect_stdout(io.StringIO()):
            rc = cve_fix.main(["--publish", str(self.dir / "ready.json"), "--repo", "o/r",
                               "--out", str(self.dir / "fixes.json")], run=runner)
        self.assertEqual(rc, 0)
        return json.loads((self.dir / "fixes.json").read_text())

    def test_apply_proves_then_opens_a_pr(self):
        runner = FakeRunner(self.infos(unstable="9"), {}, referrers=["/nix/store/r1.drv", "/nix/store/elsewhere.drv"])
        res = self.apply(runner)
        self.assertNotIn("pr", res["curl"])
        self.assertFalse(any("push" in c or c[:3] == ["gh", "pr", "create"] for c in runner.calls))
        [ready] = json.loads((self.dir / "ready.json").read_text())
        self.assertEqual(ready["branch"], "cve-fix/curl")
        self.assertIn("rebuilds: 1 derivation(s)", ready["body"])
        res = self.publish(runner)
        self.assertEqual(res["curl"], {"note": "fixed in nixos-unstable (9)", "pr": "https://github.com/o/r/pull/7"})
        fixes = json.loads(runner.written[cve_fix.FIXES_FILE])["fixes"]
        self.assertEqual(fixes["curl"], {"from": "unstable", "version": "9", "cves": ["CVE-1"], "since": "2026-11-24"})
        reg = json.loads(runner.written[cve_fix.REGISTRY_FILE])
        entry = reg["pins"][-1]
        self.assertEqual(entry["id"], "cve-fix-curl")
        self.assertIn("rebuilds 1 derivation(s)", entry["reason"])
        # The entry passes the registry's own checks against the fixed tree.
        tree = self.dir / "tree"
        for rel, text in runner.written.items():
            (tree / rel).parent.mkdir(parents=True, exist_ok=True)
            (tree / rel).write_text(text)
        errors, _ = pins.validate(reg, tree, dt.date(2026, 11, 24))
        self.assertEqual([e for e in errors if "cve-fix-curl" in e], [])
        push = next(c for c in runner.calls if "push" in c)
        self.assertEqual(push[-1], "refs/heads/cve-fix/curl:refs/heads/cve-fix/curl")
        self.assertNotIn("auto", " ".join(next(c for c in runner.calls if c[:3] == ["gh", "pr", "create"])))

    def test_apply_does_not_open_a_fix_the_scan_does_not_confirm(self):
        runner = FakeRunner(self.infos(unstable="9"), {}, referrers=[], scan_fixed=())
        res = self.apply(runner)
        self.assertIn("did not pass the CVE gate", res["curl"]["note"])
        self.assertEqual(json.loads((self.dir / "ready.json").read_text()), [])

    def test_apply_reuses_an_open_pr(self):
        prs = json.dumps([{"url": "https://github.com/o/r/pull/3", "state": "OPEN", "title": "x"}])
        res = self.apply(FakeRunner(self.infos(unstable="9"), {}, prs=prs))
        self.assertEqual(res["curl"]["pr"], "https://github.com/o/r/pull/3")

    def test_apply_does_not_reopen_a_closed_pr(self):
        title = "fix(cve): take curl 9 from nixos-unstable"
        prs = json.dumps([{"url": "https://github.com/o/r/pull/3", "state": "CLOSED", "title": title}])
        runner = FakeRunner(self.infos(unstable="9"), {}, prs=prs)
        res = self.apply(runner)
        self.assertIn("pull/3 was closed, not reopened", res["curl"]["note"])
        self.assertFalse(any("worktree" in c for c in runner.calls))

    def test_registry_append_keeps_the_hand_formatting(self):
        text = (cve_fix.REPO / cve_fix.REGISTRY_FILE).read_text()
        out = cve_fix.add_registry_entry(text, {"id": "x"})
        self.assertTrue(out.startswith(text[: text.rstrip().rfind("]")].rstrip()))
        self.assertEqual(json.loads(out)["pins"][-1], {"id": "x"})
        empty = '{\n  "pins": [\n  ]\n}\n'
        self.assertEqual(json.loads(cve_fix.add_registry_entry(empty, {"id": "x"}))["pins"], [{"id": "x"}])


if __name__ == "__main__":
    unittest.main()
