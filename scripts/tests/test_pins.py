"""Tests for scripts/pins.py.

Run: python3 -m unittest discover -s scripts/tests -p 'test_pins.py'
"""

from __future__ import annotations

import copy
import datetime as dt
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import pins  # noqa: E402

NOW = dt.date(2026, 10, 23)
REV = "a" * 40

FLAKE = f'''
{{
  inputs = {{
    plain.url = "github:owner/plain";
    branch.url = "github:owner/branch/nixos-unstable";
    locked.url = "github:owner/locked/{REV}";
    flatpak.url = "github:owner/flatpak/?ref=latest";
    tagged = {{
      url = "github:owner/tagged/v1.2.3";
      inputs.nixpkgs.follows = "nixpkgs";
    }};
    kernel = {{
      url = "github:owner/kernel/{REV}";
      inputs.nixpkgs.url = "github:NixOS/nixpkgs/{REV}";
    }};
  }};
}}
'''


def pin(**overrides: object) -> dict[str, object]:
    base: dict[str, object] = {
        "id": "demo", "class": "workaround", "kind": "overlay-override",
        "site": {"file": "overlays.nix", "match": "version = \"1.0\""},
        "pinned": "1.0", "since": "2026-10-01", "reviewed": "2026-10-20",
        "review_by": "2026-11-10",
        "reason": "Upstream has not shipped the fix we need yet, see issue.",
        "removal": "Delete the override.", "manual_test": "Build it.",
    }
    base.update(overrides)
    return base


def registry(*pin_list: dict[str, object]) -> dict[str, object]:
    return {"max_review_days": {"workaround": 45, "exception": 90, "lockstep": 90,
                                "tracked": 180}, "pins": list(pin_list)}


class DetectTests(unittest.TestCase):
    def test_finds_rev_and_tag_pins_only(self) -> None:
        found = pins.detect_flake_pins(FLAKE)
        self.assertEqual(
            found,
            {"locked": REV, "tagged": "v1.2.3", "kernel": REV,
             "kernel.inputs.nixpkgs": REV},
        )

    def test_branch_and_query_refs_are_not_pins(self) -> None:
        found = pins.detect_flake_pins(FLAKE)
        for name in ("plain", "branch", "flatpak"):
            self.assertNotIn(name, found)

    def test_insecure_packages_found_across_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "a.nix").write_text('{ permittedInsecurePackages = [ "pnpm-1" "x-2" ]; }')
            (root / "b.nix").write_text('permittedInsecurePackages = [\n "pnpm-1"\n];')
            found = pins.detect_insecure(root)
        self.assertEqual(sorted(found["pnpm-1"]), ["a.nix", "b.nix"])
        self.assertEqual(found["x-2"], ["a.nix"])


class ValidateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / "overlays.nix").write_text('version = "1.0";')
        (self.root / "flake.nix").write_text("{ inputs = { }; }")

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def errors(self, reg: dict[str, object]) -> list[str]:
        return pins.validate(reg, self.root, NOW)[0]

    def test_valid_pin_passes(self) -> None:
        self.assertEqual(self.errors(registry(pin())), [])

    def test_review_interval_over_class_limit_fails(self) -> None:
        errs = self.errors(registry(pin(review_by="2026-12-31")))
        self.assertTrue(any("may wait at most 45" in e for e in errs), errs)

    def test_needs_probe_or_manual_test(self) -> None:
        bad = pin()
        del bad["manual_test"]
        self.assertTrue(any("probe or a manual_test" in e for e in self.errors(registry(bad))))

    def test_stale_entry_whose_pin_was_removed_fails(self) -> None:
        (self.root / "overlays.nix").write_text("nothing here")
        self.assertTrue(any("stale entry" in e for e in self.errors(registry(pin()))))

    def test_unregistered_flake_pin_fails(self) -> None:
        (self.root / "flake.nix").write_text(FLAKE)
        errs = self.errors(registry(pin()))
        self.assertTrue(any("locked is pinned" in e for e in errs), errs)

    def test_registered_flake_pin_passes_and_removed_one_fails(self) -> None:
        (self.root / "flake.nix").write_text(
            f'{{\n  inputs = {{\n    locked.url = "github:o/r/{REV}";\n  }};\n}}\n')
        have = pin(id="locked", kind="flake-input", site={"input": "locked"})
        self.assertEqual(self.errors(registry(have)), [])
        (self.root / "flake.nix").write_text("{ inputs = { }; }")
        self.assertTrue(any("no longer pins it" in e for e in self.errors(registry(have))))

    def test_unregistered_insecure_permit_fails(self) -> None:
        (self.root / "m.nix").write_text('permittedInsecurePackages = [ "pnpm-9" ];')
        self.assertTrue(any("pnpm-9" in e for e in self.errors(registry(pin()))))

    def test_duplicate_id_and_short_reason_fail(self) -> None:
        errs = self.errors(registry(pin(), pin(reason="too short")))
        self.assertTrue(any("duplicate" in e for e in errs))
        self.assertTrue(any("too short" in e for e in errs))


class StatusTests(unittest.TestCase):
    def test_states(self) -> None:
        self.assertEqual(pins.status(pin(), NOW), "ok")
        self.assertEqual(pins.status(pin(review_by="2026-10-25"), NOW), "due-soon")
        self.assertEqual(pins.status(pin(review_by="2026-10-22"), NOW), "overdue")
        self.assertEqual(pins.status(pin(since="2026-01-01"), NOW), "stale")
        self.assertEqual(pins.status(pin(needs_triage=True), NOW), "needs-triage")

    def test_tracked_pins_do_not_go_stale(self) -> None:
        self.assertEqual(pins.status(pin(**{"class": "tracked", "since": "2025-01-01"}), NOW), "ok")


class ProbeTests(unittest.TestCase):
    @staticmethod
    def fake(outputs: dict[str, tuple[int, str]]):  # type: ignore[no-untyped-def]
        def run(cmd: list[str], timeout: int) -> subprocess.CompletedProcess[str]:
            key = " ".join(cmd)
            for needle, (code, out) in outputs.items():
                if needle in key:
                    return subprocess.CompletedProcess(cmd, code, out, "")
            return subprocess.CompletedProcess(cmd, 1, "", "no fake for " + key)
        return run

    def test_version_compare_is_numeric(self) -> None:
        self.assertGreater(pins.version_key("1.0.98"), pins.version_key("1.0.93"))
        self.assertGreater(pins.version_key("1.10.0"), pins.version_key("1.9.0"))
        self.assertGreater(pins.version_key("20261019"), pins.version_key("20260514"))

    def test_version_at_least(self) -> None:
        probe = {"type": "version-at-least", "flake_ref": "f", "attr": "x", "version": "2.1.293"}
        run = self.fake({"nix eval": (0, "2.1.308\n")})
        res = pins.run_probe(pin(probe=probe), run)
        self.assertTrue(res.holds)
        run = self.fake({"nix eval": (0, "2.1.200\n")})
        self.assertFalse(pins.run_probe(pin(probe=probe), run).holds)

    def test_version_at_least_uses_the_locked_rev_not_the_channel_head(self) -> None:
        asked: list[str] = []

        def run(cmd: list[str], timeout: int) -> subprocess.CompletedProcess[str]:
            asked.append(" ".join(cmd))
            return subprocess.CompletedProcess(cmd, 0, "1.0.91\n", "")

        with tempfile.TemporaryDirectory() as tmp:
            lock = Path(tmp) / "flake.lock"
            lock.write_text('{"nodes": {"nixpkgs_unstable": {"locked": {"rev": "abcdef1234"}}}}')
            probe = {"type": "version-at-least", "input": "nixpkgs_unstable",
                     "attr": "github-copilot-cli", "version": "1.0.93"}
            res = pins.run_probe(pin(probe=probe), run, lock)
        self.assertIs(res.holds, False)  # the lock is too old even if the channel head is not
        self.assertIn("github:NixOS/nixpkgs/abcdef1234#github-copilot-cli.version", asked[0])
        self.assertIn("locked nixpkgs_unstable abcdef12", res.detail)

    def test_unknown_locked_input_is_a_failed_probe(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            lock = Path(tmp) / "flake.lock"
            lock.write_text('{"nodes": {}}')
            probe = {"type": "version-at-least", "input": "missing", "attr": "x",
                     "version": "1"}
            self.assertIsNone(pins.run_probe(pin(probe=probe), self.fake({}), lock).holds)

    def test_issue_closed(self) -> None:
        probe = {"type": "issue-closed", "repo": "o/r", "number": 7}
        closed = self.fake({"issues/7": (0, "closed\n")})
        still_open = self.fake({"issues/7": (0, "open\n")})
        self.assertTrue(pins.run_probe(pin(probe=probe), closed).holds)
        self.assertFalse(pins.run_probe(pin(probe=probe), still_open).holds)

    def test_newer_release_falls_back_to_tags(self) -> None:
        probe = {"type": "newer-release", "repo": "o/r", "current": "v1",
                 "meaning": "update-available"}
        run = self.fake({"releases/latest": (1, ""), "/tags": (0, "v2\n")})
        res = pins.run_probe(pin(probe=probe), run)
        self.assertTrue(res.holds)

    def test_failed_probe_is_unknown_not_removable(self) -> None:
        probe = {"type": "command", "cmd": ["false"]}
        self.assertFalse(pins.run_probe(pin(probe=probe), self.fake({"false": (1, "")})).holds)
        res = pins.run_probe(pin(probe={"type": "mystery"}), self.fake({}))
        self.assertIsNone(res.holds)

    def test_manual_pin_has_no_verdict(self) -> None:
        self.assertIsNone(pins.run_probe(pin()).holds)


class IssueTests(unittest.TestCase):
    def titles(self, *pin_list: dict[str, object],
               results: list[pins.ProbeResult] | None = None) -> list[str]:
        specs = pins.plan_issues(registry(*pin_list), results or [], NOW)
        return [s.title for s in specs]

    def test_nothing_to_raise_for_a_healthy_pin(self) -> None:
        self.assertEqual(self.titles(pin()), [])

    def test_removable_overdue_stale_and_triage_each_raise_one(self) -> None:
        ok = pins.ProbeResult("demo", True, "removable", "x >= y")
        self.assertEqual(self.titles(pin(), results=[ok]), ["pin demo: is probably removable"])
        overdue = self.titles(pin(review_by="2026-10-22"))
        self.assertIn("pin demo: review overdue (due 2026-10-22)", overdue)
        self.assertIn("pin demo: older than 180 days", self.titles(pin(since="2026-01-01")))
        self.assertIn("pin demo: reason unknown, needs triage",
                      self.titles(pin(needs_triage=True)))

    def test_update_available_wording(self) -> None:
        res = pins.ProbeResult("demo", True, "update-available", "latest v2")
        self.assertEqual(self.titles(pin(), results=[res]), ["pin demo: has an update available"])

    def test_probe_that_does_not_hold_raises_nothing(self) -> None:
        res = pins.ProbeResult("demo", False, "removable", "still broken")
        self.assertEqual(self.titles(pin(), results=[res]), [])

    def test_existing_open_issue_is_not_duplicated(self) -> None:
        calls: list[list[str]] = []

        def run(cmd: list[str], timeout: int) -> subprocess.CompletedProcess[str]:
            calls.append(cmd)
            if cmd[:3] == ["gh", "issue", "list"]:
                title = "pin demo: review overdue (due 2026-10-22)\n"
                return subprocess.CompletedProcess(cmd, 0, title, "")
            return subprocess.CompletedProcess(cmd, 0, "", "")

        with mock.patch.dict(os.environ, {"PINS_TODAY": NOW.isoformat()}):
            pins.cmd_issues(registry(pin(review_by="2026-10-22")), [], "o/r", False, run)
            self.assertFalse(any(c[:3] == ["gh", "issue", "create"] for c in calls))
            calls.clear()
            pins.cmd_issues(registry(pin(review_by="2026-10-23")), [], "o/r", False, run)
            self.assertEqual(calls, [])  # due today is not overdue, nothing planned

    def test_real_registry_is_valid(self) -> None:
        reg = copy.deepcopy(pins.load_registry())
        errors, _ = pins.validate(reg, pins.REPO, pins.today())
        self.assertEqual(errors, [])


if __name__ == "__main__":
    unittest.main()
