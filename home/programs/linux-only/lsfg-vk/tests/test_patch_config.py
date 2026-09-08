"""Tests for the lsfg-vk conf.toml patcher.

Run: nix-shell -p python3Packages.tomli-w --run 'python3 -m unittest discover -s tests -v'
"""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import patch_config  # noqa: E402

LIVE = """version = 2

[global]
allow_fp16 = true

[[profile]]
active_in = [ "vkcube", "ff7rebirth.exe" ]
flow_scale = 0.85
multiplier = 4
name = "4x FG"
pacing = "none"
performance_mode = true

[[profile]]
active_in = "GenshinImpact.exe"
flow_scale = 1.0
multiplier = 2
name = "2x FG"
pacing = "none"
performance_mode = false
"""

HD2 = {
    "name": "HD2",
    "active_in": ["helldivers2.exe"],
    "multiplier": 2,
    "flow_scale": 0.75,
    "performance_mode": True,
    "pacing": "vsync",
    "override_present_mode": True,
    "preserve_swapchain_image_count": False,
}


class MergeTests(unittest.TestCase):
    def setUp(self):
        self.existing = patch_config.parse(LIVE)

    def test_new_profile_is_appended_and_others_untouched(self):
        merged = patch_config.merge(self.existing, {"global": {}, "profiles": [HD2]})
        names = [p["name"] for p in merged["profile"]]
        self.assertEqual(names, ["4x FG", "2x FG", "HD2"])
        self.assertEqual(merged["profile"][0]["multiplier"], 4)

    def test_same_name_profile_is_replaced_in_place(self):
        managed = dict(HD2, name="2x FG", active_in=["GenshinImpact.exe", "other.exe"])
        merged = patch_config.merge(self.existing, {"global": {}, "profiles": [managed]})
        names = [p["name"] for p in merged["profile"]]
        self.assertEqual(names, ["4x FG", "2x FG"])
        self.assertEqual(merged["profile"][1]["active_in"], ["GenshinImpact.exe", "other.exe"])
        self.assertEqual(merged["profile"][1]["flow_scale"], 0.75)

    def test_global_keys_merge_without_dropping_existing(self):
        merged = patch_config.merge(self.existing, {"global": {"dll": "/x/Lossless.dll"}, "profiles": []})
        self.assertEqual(merged["global"], {"allow_fp16": True, "dll": "/x/Lossless.dll"})

    def test_missing_file_starts_from_v2_skeleton(self):
        merged = patch_config.merge({}, {"global": {}, "profiles": [HD2]})
        self.assertEqual(merged["version"], 2)
        self.assertEqual([p["name"] for p in merged["profile"]], ["HD2"])

    def test_unsupported_version_is_refused(self):
        with self.assertRaises(patch_config.UnsupportedConfig):
            patch_config.merge({"version": 1}, {"global": {}, "profiles": []})

    def test_input_is_not_mutated(self):
        before = json.dumps(self.existing, sort_keys=True)
        patch_config.merge(self.existing, {"global": {"dll": "/x"}, "profiles": [HD2]})
        self.assertEqual(before, json.dumps(self.existing, sort_keys=True))


class ApplyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "sub" / "conf.toml"

    def tearDown(self):
        self.tmp.cleanup()

    def test_creates_parent_dirs_and_file(self):
        changed = patch_config.apply({"global": {}, "profiles": [HD2]}, self.path)
        self.assertTrue(changed)
        text = self.path.read_text()
        self.assertIn("version = 2", text)
        self.assertIn('name = "HD2"', text)

    def test_second_run_is_a_noop(self):
        patch_config.apply({"global": {}, "profiles": [HD2]}, self.path)
        stat_before = self.path.stat().st_mtime_ns
        changed = patch_config.apply({"global": {}, "profiles": [HD2]}, self.path)
        self.assertFalse(changed)
        self.assertEqual(stat_before, self.path.stat().st_mtime_ns)

    def test_ui_edits_to_unmanaged_profiles_survive(self):
        self.path.parent.mkdir(parents=True)
        self.path.write_text(LIVE)
        patch_config.apply({"global": {}, "profiles": [HD2]}, self.path)
        reread = patch_config.parse(self.path.read_text())
        self.assertEqual(reread["profile"][0]["flow_scale"], 0.85)
        self.assertEqual(reread["profile"][1]["active_in"], "GenshinImpact.exe")

    def test_refuses_to_clobber_v1_file(self):
        self.path.parent.mkdir(parents=True)
        self.path.write_text("version = 1\n[global]\nmultiplier = 2\n")
        with self.assertRaises(patch_config.UnsupportedConfig):
            patch_config.apply({"global": {}, "profiles": [HD2]}, self.path)
        self.assertIn("version = 1", self.path.read_text())


if __name__ == "__main__":
    unittest.main()
