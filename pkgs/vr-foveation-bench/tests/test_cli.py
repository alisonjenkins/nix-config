"""Tests for the command line: exit codes, files in and out."""

import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tests.helpers import make_card
from vr_foveation_bench import cli

META = {
    "game": "Fallout 4 VR", "appId": 611660, "gameBuild": "b1", "driver": "mesa",
    "gpu": "RX 9070 XT", "undervoltMv": -40, "headsetOrDisplay": {"kind": "null-driver"},
}


T0 = 1000.0


def frames_csv(gpu_ms, warmup_ms=None):
    """20 frames, one per second from T0; the first 10 are warm-up if given."""
    rows = "".join(
        f"{i},{warmup_ms if warmup_ms is not None and i < 10 else gpu_ms},{gpu_ms / 2},{T0 + i}\n"
        for i in range(20))
    return "frame,gpu_ms,eye_pass_ms,unix_s\n" + rows


def sampler_csv(watts, warmup_watts=None):
    first = watts if warmup_watts is None else warmup_watts
    return ("time_s,power_w,core_mhz,gpu_busy_percent,temp_c,unix_s\n"
            f"0.0,{first},2400,90,60,{T0}\n9.0,{first},2400,90,62,{T0 + 9}\n"
            f"10.0,{watts},2400,90,63,{T0 + 10}\n19.0,{watts},2400,90,65,{T0 + 19}\n")


class Cli(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.dir = Path(self._tmp.name)
        (self.dir / "meta.json").write_text(json.dumps(META))

    def write(self, name, text):
        path = self.dir / name
        path.write_text(text)
        return str(path)

    def runs(self, prefix, gpu_list, watt_list=None):
        frames = [self.write(f"{prefix}{i}.csv", frames_csv(g)) for i, g in enumerate(gpu_list)]
        power = []
        if watt_list:
            power = [self.write(f"{prefix}{i}-power.csv", sampler_csv(w))
                     for i, w in enumerate(watt_list)]
        return frames, power

    def invoke(self, argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = cli.main(argv)
        return code, out.getvalue(), err.getvalue()

    def report_argv(self, off, on, off_power=(), on_power=(), artefacts="tolerable", out=None):
        argv = ["report", "--meta", str(self.dir / "meta.json"),
                "--off", *off, "--on", *on, "--artefacts", artefacts,
                "--out", out or str(self.dir / "report.json")]
        if off_power:
            argv += ["--off-power", *off_power]
        if on_power:
            argv += ["--on-power", *on_power]
        return argv

    def test_exit_0_writes_report_and_prints_summary(self):
        off, off_p = self.runs("off", [10.0, 10.5, 10.0], [200.0, 205.0, 200.0])
        on, on_p = self.runs("on", [8.0, 8.5, 8.0], [150.0, 155.0, 150.0])
        code, out, err = self.invoke(self.report_argv(off, on, off_p, on_p))
        self.assertEqual(code, 0, err)
        data = json.loads((self.dir / "report.json").read_text(encoding="utf-8"))
        self.assertEqual(data["verdict"]["verdict"], "go")
        self.assertEqual(len(data["reports"]), 2)
        self.assertEqual(data["reports"][0]["runs"][0]["frames"], 20)
        self.assertIn("go", out)
        self.assertIn("noise", out)
        self.assertIn("median", out)

    def inputs(self):
        off, _ = self.runs("off", [10.0, 10.5, 10.0])
        on, _ = self.runs("on", [8.0, 8.5, 8.0])
        return off, on

    def test_exit_1_refuses_to_overwrite_existing_out(self):
        off, on = self.inputs()
        target = self.dir / "report.json"
        target.write_text("precious")
        code, _, err = self.invoke(self.report_argv(off, on))
        self.assertEqual(code, 1)
        self.assertIn(str(target), err)
        self.assertIn("--force", err)
        self.assertEqual(target.read_text(), "precious")

    def test_force_overwrites_existing_out(self):
        off, on = self.inputs()
        target = self.dir / "report.json"
        target.write_text("precious")
        code, _, err = self.invoke(self.report_argv(off, on) + ["--force"])
        self.assertEqual(code, 0, err)
        self.assertIn("reports", json.loads(target.read_text(encoding="utf-8")))

    def test_absent_out_is_written_without_force(self):
        off, on = self.inputs()
        code, _, err = self.invoke(self.report_argv(off, on))
        self.assertEqual(code, 0, err)
        self.assertTrue((self.dir / "report.json").exists())

    def warm_runs(self):
        off = [self.write(f"woff{i}.csv", frames_csv(10.0, warmup_ms=50.0)) for i in range(3)]
        on = [self.write(f"won{i}.csv", frames_csv(8.0, warmup_ms=50.0)) for i in range(3)]
        off_p = [self.write(f"woff{i}-p.csv", sampler_csv(200.0, 400.0)) for i in range(3)]
        on_p = [self.write(f"won{i}-p.csv", sampler_csv(150.0, 400.0)) for i in range(3)]
        return off, on, off_p, on_p

    def test_skip_and_window_trim_both_logs_and_are_reported(self):
        off, on, off_p, on_p = self.warm_runs()
        argv = self.report_argv(off, on, off_p, on_p) + [
            "--skip-seconds", "10", "--window-seconds", "9"]
        code, out, err = self.invoke(argv)
        self.assertEqual(code, 0, err)
        data = json.loads((self.dir / "report.json").read_text(encoding="utf-8"))
        run0 = data["reports"][0]["runs"][0]
        self.assertEqual(run0["medianGpuMs"], 10.0)
        self.assertEqual(run0["frames"], 10)
        self.assertEqual(run0["meanPowerW"], 200.0)
        self.assertEqual(run0["window"], {
            "skipSeconds": 10.0, "windowSeconds": 9.0,
            "windowStartUnixS": T0 + 10, "windowEndUnixS": T0 + 19})
        self.assertIn("window", out)
        self.assertIn("skip 10", out)

    def test_without_trim_the_warmup_is_included(self):
        off, on, off_p, on_p = self.warm_runs()
        code, _, err = self.invoke(self.report_argv(off, on, off_p, on_p))
        self.assertEqual(code, 0, err)
        data = json.loads((self.dir / "report.json").read_text(encoding="utf-8"))
        self.assertEqual(data["reports"][0]["runs"][0]["frames"], 20)

    def test_exit_1_when_skip_leaves_no_frames_and_names_the_file(self):
        off, on, _, _ = self.warm_runs()
        code, _, err = self.invoke(self.report_argv(off, on) + ["--skip-seconds", "500"])
        self.assertEqual(code, 1)
        self.assertIn(off[0], err)
        self.assertFalse((self.dir / "report.json").exists())

    def test_exit_1_when_sampler_does_not_overlap_the_window(self):
        off, on, off_p, on_p = self.warm_runs()
        Path(off_p[1]).write_text(
            "time_s,power_w,core_mhz,gpu_busy_percent,temp_c,unix_s\n"
            "0,1,1,1,1,5000\n1,1,1,1,1,5001\n")
        code, _, err = self.invoke(self.report_argv(off, on, off_p, on_p))
        self.assertEqual(code, 1)
        self.assertIn(off[1], err)
        self.assertIn("overlap", err)

    def test_exit_1_on_invalid_skip_and_window_values(self):
        off, on, _, _ = self.warm_runs()
        for extra in (["--skip-seconds", "-1"], ["--window-seconds", "0"],
                      ["--window-seconds", "abc"], ["--skip-seconds", "nan"]):
            code, _, err = self.invoke(self.report_argv(off, on) + extra)
            self.assertEqual(code, 1, extra)
            self.assertTrue(err)

    def test_exit_0_without_power_files(self):
        off, _ = self.runs("off", [10.0, 10.5, 10.0])
        on, _ = self.runs("on", [8.0, 8.5, 8.0])
        code, _, err = self.invoke(self.report_argv(off, on))
        self.assertEqual(code, 0, err)

    def test_exit_1_bad_frame_file_names_file_and_line(self):
        off, _ = self.runs("off", [10.0, 10.5, 10.0])
        on, _ = self.runs("on", [8.0, 8.5, 8.0])
        Path(on[1]).write_text("frame,gpu_ms,eye_pass_ms,unix_s\n0,1,2,9\n1,oops,2,9\n")
        code, out, err = self.invoke(self.report_argv(off, on))
        self.assertEqual(code, 1)
        self.assertIn(f"{on[1]}:3", err)
        self.assertFalse((self.dir / "report.json").exists())

    def test_exit_1_missing_file(self):
        off, _ = self.runs("off", [10.0, 10.5, 10.0])
        on, _ = self.runs("on", [8.0, 8.5, 8.0])
        on[0] = str(self.dir / "nope.csv")
        code, _, err = self.invoke(self.report_argv(off, on))
        self.assertEqual(code, 1)
        self.assertIn("nope.csv", err)

    def test_exit_1_bad_meta(self):
        off, _ = self.runs("off", [10.0, 10.5, 10.0])
        on, _ = self.runs("on", [8.0, 8.5, 8.0])
        (self.dir / "meta.json").write_text('{"game": "x"}')
        code, _, err = self.invoke(self.report_argv(off, on))
        self.assertEqual(code, 1)
        self.assertIn("meta.json", err)
        self.assertIn("driver", err)

    def test_exit_1_unequal_run_counts(self):
        off, _ = self.runs("off", [10.0, 10.5, 10.0, 10.0])
        on, _ = self.runs("on", [8.0, 8.5, 8.0])
        code, _, err = self.invoke(self.report_argv(off, on))
        self.assertEqual(code, 1)
        self.assertIn("pair", err)

    def test_exit_1_power_files_do_not_match_run_count(self):
        off, off_p = self.runs("off", [10.0, 10.5, 10.0], [200.0, 205.0])
        on, _ = self.runs("on", [8.0, 8.5, 8.0])
        code, _, err = self.invoke(self.report_argv(off, on, off_p))
        self.assertEqual(code, 1)
        self.assertIn("--off-power", err)

    def test_exit_1_usage_error(self):
        code, _, err = self.invoke(["report", "--artefacts", "maybe"])
        self.assertEqual(code, 1)
        self.assertTrue(err)

    def test_exit_2_too_few_runs(self):
        off, _ = self.runs("off", [10.0, 10.5])
        on, _ = self.runs("on", [8.0, 8.5])
        code, _, err = self.invoke(self.report_argv(off, on))
        self.assertEqual(code, 2)
        self.assertIn("at least 3", err)
        self.assertFalse((self.dir / "report.json").exists())

    def test_sample_writes_csv_from_a_fake_sysfs(self):
        root = self.dir / "sys"
        make_card(root, "card0", 0x164E, "hwmon5", power_uw=20_000_000)
        make_card(root, "card1", 0x7550, "hwmon4", power_uw=250_000_000)
        out = self.dir / "sampler.csv"
        code, _, err = self.invoke(["sample", "--out", str(out), "--duration", "0",
                                    "--sysfs-root", str(root), "--pci-device", "0x7550"])
        self.assertEqual(code, 0, err)
        lines = out.read_text(encoding="utf-8").splitlines()
        self.assertEqual(lines[0], "time_s,power_w,core_mhz,gpu_busy_percent,temp_c,unix_s")
        self.assertEqual(lines[1].split(",")[1], "250.000")
        self.assertGreater(float(lines[1].split(",")[5]), 1_600_000_000.0)

    def test_sample_exit_1_when_gpu_absent(self):
        root = self.dir / "sys"
        make_card(root, "card0", 0x164E, "hwmon5")
        code, _, err = self.invoke(["sample", "--out", str(self.dir / "s.csv"),
                                    "--sysfs-root", str(root), "--duration", "0"])
        self.assertEqual(code, 1)
        self.assertIn("0x7550", err)

    def make_report(self, **verdict_over):
        verdict = {"game": "Fallout 4 VR", "date": "2026-10-06T12:00:00Z", "driver": "mesa",
                   "verdict": "go", "gpuTimeChange": -0.073, "powerChange": None,
                   "noise": {"medianGpuMs": {"off": 0.42, "on": 0.2}, "meanPowerW": None},
                   "artefacts": "tolerable", "reason": "r"}
        verdict.update(verdict_over)
        return self.write("rep.json", json.dumps({"reports": [{}, {}], "verdict": verdict}))

    def verdict_argv(self, rep, table, notes="none seen"):
        return ["verdict", "--report", rep, "--verdicts", str(table), "--artefact-notes", notes]

    def test_verdict_creates_file_and_prints_row(self):
        table = self.dir / "verdicts.md"
        code, out, err = self.invoke(self.verdict_argv(self.make_report(), table))
        self.assertEqual(code, 0, err)
        text = table.read_text(encoding="utf-8")
        self.assertIn("| game | date | driver | verdict |", text)
        self.assertIn("| Fallout 4 VR | 2026-10-06T12:00:00Z | mesa | go | -7.3% | n/a "
                      "| GPU ±0.42 ms; power n/a | none seen |", text)
        self.assertIn("Fallout 4 VR", out)

    def test_verdict_twice_is_idempotent_and_replaces(self):
        table = self.dir / "verdicts.md"
        rep = self.make_report()
        self.invoke(self.verdict_argv(rep, table))
        first = table.read_text(encoding="utf-8")
        self.assertEqual(self.invoke(self.verdict_argv(rep, table))[0], 0)
        self.assertEqual(table.read_text(encoding="utf-8"), first)
        self.invoke(self.verdict_argv(self.make_report(verdict="no-go"), table))
        text = table.read_text(encoding="utf-8")
        self.assertEqual(text.count("Fallout 4 VR"), 1)
        self.assertIn("| no-go |", text)

    def test_verdict_missing_parent_dir_exit_1(self):
        table = self.dir / "nope" / "verdicts.md"
        code, _, err = self.invoke(self.verdict_argv(self.make_report(), table))
        self.assertEqual(code, 1)
        self.assertIn(str(table.parent), err)

    def test_verdict_invalid_verdict_exit_1(self):
        table = self.dir / "verdicts.md"
        code, _, err = self.invoke(self.verdict_argv(self.make_report(verdict="maybe"), table))
        self.assertEqual(code, 1)
        self.assertIn("maybe", err)
        self.assertFalse(table.exists())

    def test_verdict_failed_write_keeps_the_original_and_leaves_no_temp_file(self):
        table = self.dir / "verdicts.md"
        rep = self.make_report()
        self.invoke(self.verdict_argv(rep, table))
        original = table.read_text(encoding="utf-8")
        before = sorted(p.name for p in self.dir.iterdir())
        with mock.patch.object(cli.os, "replace", side_effect=OSError("disk full")):
            code, _, err = self.invoke(self.verdict_argv(self.make_report(verdict="no-go"), table))
        self.assertEqual(code, 1)
        self.assertIn("disk full", err)
        self.assertEqual(table.read_text(encoding="utf-8"), original)
        self.assertEqual(sorted(p.name for p in self.dir.iterdir()), before)

    def test_verdict_file_gets_the_permissions_a_normal_write_would(self):
        reference = self.dir / "reference.txt"
        reference.write_text("x", encoding="utf-8")
        table = self.dir / "verdicts.md"
        self.invoke(self.verdict_argv(self.make_report(), table))
        self.assertEqual(table.stat().st_mode & 0o777, reference.stat().st_mode & 0o777)
        table.chmod(0o640)
        self.invoke(self.verdict_argv(self.make_report(verdict="no-go"), table))
        self.assertEqual(table.stat().st_mode & 0o777, 0o640)

    def test_verdict_bad_report_exit_1(self):
        table = self.dir / "verdicts.md"
        code, _, err = self.invoke(self.verdict_argv(self.write("bad.json", "{"), table))
        self.assertEqual(code, 1)
        self.assertIn("bad.json", err)


if __name__ == "__main__":
    unittest.main()
