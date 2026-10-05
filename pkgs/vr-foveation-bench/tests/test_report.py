"""Tests for the measurement report schema, CSV parsing and verdict logic."""

import datetime
import unittest

from vr_foveation_bench import report, stats

META = {
    "game": "Fallout 4 VR",
    "appId": 611660,
    "gameBuild": "build-1234",
    "driver": "mesa 26.2",
    "gpu": "RX 9070 XT",
    "undervoltMv": -40,
    "headsetOrDisplay": {"kind": "null-driver", "renderWidth": 2064, "refreshHz": 90},
}
NOW = datetime.datetime(2026, 10, 5, 12, 30, 0, tzinfo=datetime.timezone.utc)

RUN_KEYS = {
    "frames", "medianGpuMs", "p99GpuMs", "medianEyePassMs", "meanPowerW",
    "meanCoreMhz", "startTempC", "endTempC", "window",
}
WINDOW_KEYS = {"skipSeconds", "windowSeconds", "windowStartUnixS", "windowEndUnixS"}
T0 = 1000.0
REPORT_KEYS = {
    "game", "appId", "gameBuild", "driver", "gpu", "undervoltMv",
    "headsetOrDisplay", "build", "condition", "runs", "noise",
    "eyePassShare", "date",
}


def frames(gpu_ms, eye_ms=None):
    eye_ms = gpu_ms * 0.5 if eye_ms is None else eye_ms
    return [report.Frame(i, gpu_ms, eye_ms, T0 + i * 0.01) for i in range(100)]


def power(watts, core_mhz=2400.0, temp_start=60.0, temp_end=70.0):
    return [
        report.PowerSample(0.0, watts, core_mhz, 90.0, temp_start, T0),
        report.PowerSample(0.5, watts, core_mhz, 90.0, temp_end, T0 + 0.5),
    ]


def run(gpu_ms, watts=None, run_label="r"):
    samples = power(watts) if watts is not None else None
    return report.build_run(frames(gpu_ms), samples, run_label)


def runs(gpu_list, watt_list=None):
    watt_list = watt_list or [None] * len(gpu_list)
    return [run(g, w, f"run {i}") for i, (g, w) in enumerate(zip(gpu_list, watt_list))]


class BuildRun(unittest.TestCase):
    def test_fields_exactly_as_the_data_model(self):
        r = run(10.0, 200.0)
        self.assertEqual(set(r), RUN_KEYS)
        self.assertEqual(r["frames"], 100)
        self.assertEqual(r["medianGpuMs"], 10.0)
        self.assertEqual(r["p99GpuMs"], 10.0)
        self.assertEqual(r["medianEyePassMs"], 5.0)
        self.assertEqual(r["meanPowerW"], 200.0)
        self.assertEqual(r["meanCoreMhz"], 2400.0)
        self.assertEqual(r["startTempC"], 60.0)
        self.assertEqual(r["endTempC"], 70.0)

    def test_without_power_samples_power_fields_are_null(self):
        r = run(10.0)
        self.assertEqual(set(r), RUN_KEYS)
        for key in ("meanPowerW", "meanCoreMhz", "startTempC", "endTempC"):
            self.assertIsNone(r[key])

    def test_missing_temperature_is_null_not_zero(self):
        samples = [report.PowerSample(0.0, 100.0, 2400.0, 50.0, None, T0),
                   report.PowerSample(0.5, 100.0, 2400.0, 50.0, None, T0 + 0.5)]
        r = report.build_run(frames(10.0), samples, "r")
        self.assertIsNone(r["startTempC"])
        self.assertIsNone(r["endTempC"])
        self.assertEqual(r["meanPowerW"], 100.0)

    def test_no_frames_names_the_run(self):
        with self.assertRaises(stats.InvalidSample) as ctx:
            report.build_run([], None, "off run 3")
        self.assertIn("off run 3", str(ctx.exception))

    def test_window_is_recorded_in_the_run(self):
        r = run(10.0, 200.0)
        w = r["window"]
        self.assertEqual(set(w), WINDOW_KEYS)
        self.assertEqual(w["skipSeconds"], 0.0)
        self.assertEqual(w["windowStartUnixS"], T0)
        self.assertEqual(w["windowEndUnixS"], T0 + 99 * 0.01)
        self.assertAlmostEqual(w["windowSeconds"], 0.99)

    def test_trimming_changes_the_medians_and_counts_the_trimmed_frames(self):
        # 60 s of slow warm-up then 40 s steady; power drops once warm-up ends.
        fs = [report.Frame(i, 50.0 if i < 60 else 10.0, 5.0, T0 + i) for i in range(100)]
        ps = [report.PowerSample(t - T0, w, 2400.0, 90.0, None, t)
              for t, w in ((T0, 300.0), (T0 + 30, 300.0), (T0 + 60, 100.0), (T0 + 99, 100.0))]
        whole = report.build_run(fs, ps, "r")
        trimmed = report.build_run(fs, ps, "r", skip_s=60.0)
        self.assertEqual(whole["medianGpuMs"], 50.0)
        self.assertEqual(whole["frames"], 100)
        self.assertEqual(trimmed["medianGpuMs"], 10.0)
        self.assertEqual(trimmed["p99GpuMs"], 10.0)
        self.assertEqual(trimmed["frames"], 40)
        self.assertEqual(trimmed["meanPowerW"], 100.0)
        self.assertGreater(whole["meanPowerW"], 100.0)
        self.assertEqual(trimmed["window"]["skipSeconds"], 60.0)
        self.assertEqual(trimmed["window"]["windowStartUnixS"], T0 + 60)


def timed_frames(count=20):
    return [report.Frame(i, float(i + 1), 1.0, T0 + i) for i in range(count)]


def timed_samples(times):
    return [report.PowerSample(t - T0, 100.0 + (t - T0), 2400.0, 90.0, None, t) for t in times]


HALF_SECONDS = [T0 + 0.5 * k for k in range(41)]


class TrimToWindow(unittest.TestCase):
    def test_skip_only_runs_to_the_last_frame(self):
        fs, ps, win = report.trim_to_window(
            timed_frames(), timed_samples(HALF_SECONDS), 5.0, None, "r")
        self.assertEqual([f.frame for f in fs], list(range(5, 20)))
        self.assertEqual(ps[0].unix_s, T0 + 5)
        self.assertEqual(ps[-1].unix_s, T0 + 19.0)
        self.assertEqual(win, report.Window(5.0, 14.0, T0 + 5, T0 + 19))

    def test_skip_and_window_with_boundary_samples_included(self):
        fs, ps, win = report.trim_to_window(
            timed_frames(), timed_samples(HALF_SECONDS), 2.0, 4.0, "r")
        self.assertEqual([f.frame for f in fs], [2, 3, 4, 5, 6])
        self.assertEqual([p.unix_s for p in ps], [T0 + 2 + 0.5 * k for k in range(9)])
        self.assertEqual(win, report.Window(2.0, 4.0, T0 + 2, T0 + 6))

    def test_window_beyond_log_end_is_an_error(self):
        # a run that stopped early must not pass as a full-length one
        with self.assertRaises(report.InputError) as ctx:
            report.trim_to_window(
                timed_frames(), timed_samples(HALF_SECONDS), 10.0, 100.0, "on run 3 (c.csv)")
        self.assertIn("on run 3 (c.csv)", str(ctx.exception))
        self.assertIn("frame log ends", str(ctx.exception))

    def test_window_end_within_the_tolerance_of_the_log_end_is_accepted(self):
        # frames run to T0 + 19; the window asks for T0 + 19.5
        fs, _, win = report.trim_to_window(
            timed_frames(), timed_samples(HALF_SECONDS), 10.0, 9.5, "r")
        self.assertEqual([f.frame for f in fs], list(range(10, 20)))
        self.assertEqual(win.window_end_unix_s, T0 + 19.5)

    def test_sampler_that_starts_after_the_window_start_is_an_error(self):
        ps = timed_samples([T0 + 8 + 0.5 * k for k in range(25)])
        with self.assertRaises(report.InputError) as ctx:
            report.trim_to_window(timed_frames(), ps, 5.0, None, "r")
        self.assertIn("sampler starts", str(ctx.exception))

    def test_sampler_that_ends_before_the_window_end_is_an_error(self):
        ps = timed_samples([T0 + 0.5 * k for k in range(25)])
        with self.assertRaises(report.InputError) as ctx:
            report.trim_to_window(timed_frames(), ps, 2.0, None, "r")
        self.assertIn("sampler ends", str(ctx.exception))

    def test_without_samples_returns_none(self):
        fs, ps, _ = report.trim_to_window(timed_frames(), None, 1.0, None, "r")
        self.assertIsNone(ps)
        self.assertEqual(len(fs), 19)

    def test_skip_past_the_log_leaves_no_frames(self):
        with self.assertRaises(report.InputError) as ctx:
            report.trim_to_window(timed_frames(), None, 100.0, None, "off run 1 (a.csv)")
        self.assertIn("off run 1 (a.csv)", str(ctx.exception))
        self.assertIn("no frames", str(ctx.exception))

    def test_samples_entirely_outside_the_window_are_an_error(self):
        ps = timed_samples([T0 + 500, T0 + 501])
        with self.assertRaises(report.InputError) as ctx:
            report.trim_to_window(timed_frames(), ps, 0.0, None, "on run 2 (b.csv)")
        self.assertIn("on run 2 (b.csv)", str(ctx.exception))
        self.assertIn("overlap", str(ctx.exception))

    def test_samples_before_the_window_are_an_error(self):
        ps = timed_samples([T0 - 10, T0 - 9])
        with self.assertRaises(report.InputError) as ctx:
            report.trim_to_window(timed_frames(), ps, 0.0, None, "r")
        self.assertIn("overlap", str(ctx.exception))

    def test_one_sample_in_the_window_is_too_few(self):
        ps = timed_samples([T0 + 5, T0 + 50])
        with self.assertRaises(report.InputError) as ctx:
            report.trim_to_window(timed_frames(), ps, 0.0, None, "r")
        self.assertIn("fewer than 2", str(ctx.exception))

    def test_invalid_skip_and_window_rejected(self):
        for skip, win in ((-1.0, None), (float("nan"), None), (0.0, 0.0), (0.0, -2.0),
                          (0.0, float("inf"))):
            with self.assertRaises(ValueError):
                report.trim_to_window(timed_frames(), None, skip, win, "r")


class MeasurementReport(unittest.TestCase):
    def test_schema(self):
        rep = report.build_measurement_report(
            META, "off", "patched-off", runs([10.0, 10.5, 10.0]), NOW)
        self.assertEqual(set(rep), REPORT_KEYS)
        self.assertEqual(rep["game"], "Fallout 4 VR")
        self.assertEqual(rep["appId"], 611660)
        self.assertEqual(rep["undervoltMv"], -40)
        self.assertEqual(rep["headsetOrDisplay"], META["headsetOrDisplay"])
        self.assertEqual(rep["build"], "patched-off")
        self.assertEqual(rep["condition"], "off")
        self.assertEqual(len(rep["runs"]), 3)
        self.assertEqual(rep["date"], "2026-10-05T12:30:00Z")

    def test_noise_is_spread_of_per_run_medians(self):
        rep = report.build_measurement_report(
            META, "off", "patched-off", runs([10.0, 10.5, 9.75], [200, 210, 190]), NOW)
        self.assertEqual(rep["noise"]["medianGpuMs"], 0.75)
        self.assertEqual(rep["noise"]["meanPowerW"], 20.0)

    def test_noise_power_null_when_a_run_has_no_power(self):
        rep = report.build_measurement_report(
            META, "off", "patched-off", runs([10.0, 10.5, 9.75], [200, None, 190]), NOW)
        self.assertIsNone(rep["noise"]["meanPowerW"])

    def test_eye_pass_share(self):
        rs = [report.build_run(frames(10.0, 4.0), None, f"r{i}") for i in range(3)]
        rep = report.build_measurement_report(META, "on", "patched-on", rs, NOW)
        self.assertEqual(rep["eyePassShare"], 0.4)

    def test_rejects_invalid_build_and_condition(self):
        with self.assertRaises(ValueError) as ctx:
            report.build_measurement_report(META, "off", "nightly", runs([1.0] * 3), NOW)
        self.assertIn("nightly", str(ctx.exception))
        with self.assertRaises(ValueError) as ctx:
            report.build_measurement_report(META, "both", "stock", runs([1.0] * 3), NOW)
        self.assertIn("both", str(ctx.exception))

    def test_accepts_all_three_builds(self):
        for build in ("stock", "patched-off", "patched-on"):
            rep = report.build_measurement_report(META, "off", build, runs([1.0] * 3), NOW)
            self.assertEqual(rep["build"], build)

    def test_missing_meta_key_is_named(self):
        meta = dict(META)
        del meta["driver"]
        with self.assertRaises(ValueError) as ctx:
            report.build_measurement_report(meta, "off", "stock", runs([1.0] * 3), NOW)
        self.assertIn("driver", str(ctx.exception))

    def test_naive_date_rejected(self):
        with self.assertRaises(ValueError):
            report.build_measurement_report(
                META, "off", "stock", runs([1.0] * 3), datetime.datetime(2026, 1, 1))

    def test_zero_gpu_median_cannot_give_a_share(self):
        rs = runs([0.0, 0.0, 0.0])
        with self.assertRaises(stats.InvalidSample):
            report.build_measurement_report(META, "off", "stock", rs, NOW)


OFF = [10.0, 10.5, 10.0]
QUIET = [10.0, 10.25, 10.0]
ON_FASTER = [8.0, 8.5, 8.0]
OFF_W = [200.0, 205.0, 200.0]
ON_LOWER_W = [150.0, 155.0, 150.0]


class Verdict(unittest.TestCase):
    def test_go_when_gpu_time_drops_beyond_noise_and_artefacts_tolerable(self):
        v = report.decide_verdict(runs(OFF), runs(ON_FASTER), "tolerable")
        self.assertEqual(v["verdict"], "go")
        self.assertAlmostEqual(v["gpuTimeChange"], -0.2)
        self.assertIsNone(v["powerChange"])
        self.assertEqual(v["artefacts"], "tolerable")
        self.assertTrue(v["reason"])

    def test_go_when_only_power_drops(self):
        v = report.decide_verdict(
            runs(OFF, OFF_W), runs(OFF, ON_LOWER_W), "tolerable")
        self.assertEqual(v["verdict"], "go")
        self.assertAlmostEqual(v["powerChange"], -0.25)
        self.assertEqual(v["gpuTimeChange"], 0.0)

    def test_noise_values_are_reported(self):
        v = report.decide_verdict(runs(OFF, OFF_W), runs(ON_FASTER, ON_LOWER_W), "tolerable")
        self.assertEqual(v["noise"]["medianGpuMs"], {"off": 0.5, "on": 0.5})
        self.assertEqual(v["noise"]["meanPowerW"], {"off": 5.0, "on": 5.0})

    def test_no_go_when_artefacts_not_tolerable_even_with_gain(self):
        v = report.decide_verdict(runs(OFF), runs(ON_FASTER), "not-tolerable")
        self.assertEqual(v["verdict"], "no-go")
        self.assertIn("artefacts", v["reason"])

    def test_no_go_when_no_gain_and_quiet(self):
        v = report.decide_verdict(runs(QUIET), runs(QUIET), "tolerable")
        self.assertEqual(v["verdict"], "no-go")

    def test_no_go_when_gpu_time_rises_beyond_noise(self):
        v = report.decide_verdict(runs(OFF), runs([12.0, 12.5, 12.0]), "tolerable")
        self.assertEqual(v["verdict"], "no-go")
        self.assertGreater(v["gpuTimeChange"], 0)

    def test_inconclusive_when_noise_is_five_percent_or_more_of_off_median(self):
        # off median 10.0, spread 0.5 -> exactly 5 %
        v = report.decide_verdict(runs(OFF), runs([9.9, 10.4, 9.9]), "tolerable")
        self.assertEqual(v["verdict"], "inconclusive")
        self.assertIn("noise", v["reason"])

    def test_just_under_five_percent_noise_with_no_gain_is_no_go(self):
        off = [10.0, 10.49, 10.0]
        v = report.decide_verdict(runs(off), runs([9.9, 10.39, 9.9]), "tolerable")
        self.assertEqual(v["verdict"], "no-go")

    def test_noisy_power_keeps_a_clean_gpu_null_result_inconclusive(self):
        v = report.decide_verdict(
            runs(QUIET, [200.0, 230.0, 200.0]), runs(QUIET, [200.0, 230.0, 200.0]), "tolerable")
        self.assertEqual(v["verdict"], "inconclusive")

    def test_unknown_artefacts_with_a_reduction_is_inconclusive(self):
        v = report.decide_verdict(runs(OFF), runs(ON_FASTER), "unknown")
        self.assertEqual(v["verdict"], "inconclusive")
        self.assertEqual(v["reason"], "artefacts not judged")

    def test_unknown_artefacts_without_reduction_follows_the_noise_rule(self):
        v = report.decide_verdict(runs(QUIET), runs(QUIET), "unknown")
        self.assertEqual(v["verdict"], "no-go")

    def test_not_tolerable_wins_over_unknown_reduction_logic(self):
        v = report.decide_verdict(runs(QUIET), runs(QUIET), "not-tolerable")
        self.assertEqual(v["verdict"], "no-go")

    def test_rejects_invalid_artefacts(self):
        with self.assertRaises(ValueError) as ctx:
            report.decide_verdict(runs(OFF), runs(ON_FASTER), "fine")
        self.assertIn("fine", str(ctx.exception))

    def test_too_few_runs_propagates(self):
        with self.assertRaises(stats.TooFewRuns):
            report.decide_verdict(runs([10.0, 10.0]), runs([8.0, 8.0]), "tolerable")

    def test_unequal_run_counts_propagate(self):
        with self.assertRaises(stats.UnequalRunCounts):
            report.decide_verdict(runs([10.0] * 3), runs([8.0] * 4), "tolerable")

    def test_power_skipped_when_any_run_lacks_it(self):
        v = report.decide_verdict(
            runs(OFF, [200.0, None, 200.0]), runs(ON_FASTER, ON_LOWER_W), "tolerable")
        self.assertIsNone(v["powerChange"])
        self.assertEqual(v["verdict"], "go")


class BuildReport(unittest.TestCase):
    def test_pairs_both_conditions_with_a_verdict(self):
        out = report.build_report(
            META, runs(OFF), runs(ON_FASTER), "tolerable", NOW)
        self.assertEqual([r["condition"] for r in out["reports"]], ["off", "on"])
        self.assertEqual([r["build"] for r in out["reports"]], ["patched-off", "patched-on"])
        v = out["verdict"]
        self.assertEqual(v["verdict"], "go")
        self.assertEqual(v["game"], "Fallout 4 VR")
        self.assertEqual(v["driver"], "mesa 26.2")
        self.assertEqual(v["date"], "2026-10-05T12:30:00Z")

    def test_meta_may_override_builds(self):
        meta = dict(META, offBuild="stock", onBuild="patched-on")
        out = report.build_report(meta, runs(OFF), runs(ON_FASTER), "tolerable", NOW)
        self.assertEqual(out["reports"][0]["build"], "stock")


FRAMES_CSV = "frame,gpu_ms,eye_pass_ms,unix_s\n0,10.5,5.25,1000.5\n1,11.0,5.5,1000.75\n"
SAMPLER_CSV = (
    "time_s,power_w,core_mhz,gpu_busy_percent,temp_c,unix_s\n"
    "0.000,100.0,2400,90,55.0,1000.5\n"
    "0.050,110.0,2500,95,,1000.55\n"
)


class ParseFrames(unittest.TestCase):
    def test_parses_rows(self):
        got = report.parse_frames_csv(FRAMES_CSV, "f.csv")
        self.assertEqual(got, [report.Frame(0, 10.5, 5.25, 1000.5),
                               report.Frame(1, 11.0, 5.5, 1000.75)])

    def test_old_header_without_unix_s_is_rejected(self):
        with self.assertRaises(report.InputError) as ctx:
            report.parse_frames_csv("frame,gpu_ms,eye_pass_ms\n0,1,2\n", "f.csv")
        self.assertIn("f.csv:1", str(ctx.exception))
        self.assertIn("unix_s", str(ctx.exception))

    def test_bad_header_names_file_and_line(self):
        with self.assertRaises(report.InputError) as ctx:
            report.parse_frames_csv("frame,gpu\n0,1\n", "f.csv")
        self.assertIn("f.csv:1", str(ctx.exception))

    def test_bad_number_names_file_and_line(self):
        with self.assertRaises(report.InputError) as ctx:
            report.parse_frames_csv("frame,gpu_ms,eye_pass_ms,unix_s\n0,1,2,9\n1,abc,2,9\n", "f.csv")
        self.assertIn("f.csv:3", str(ctx.exception))
        self.assertIn("abc", str(ctx.exception))

    def test_wrong_field_count(self):
        with self.assertRaises(report.InputError) as ctx:
            report.parse_frames_csv("frame,gpu_ms,eye_pass_ms,unix_s\n0,1\n", "f.csv")
        self.assertIn("f.csv:2", str(ctx.exception))

    def test_negative_and_nan_rejected(self):
        for bad in ("-1.0", "nan"):
            with self.assertRaises(report.InputError):
                report.parse_frames_csv(f"frame,gpu_ms,eye_pass_ms,unix_s\n0,{bad},2,9\n", "f.csv")

    def test_no_rows_rejected(self):
        with self.assertRaises(report.InputError) as ctx:
            report.parse_frames_csv("frame,gpu_ms,eye_pass_ms,unix_s\n", "f.csv")
        self.assertIn("f.csv", str(ctx.exception))

    def test_empty_file_rejected(self):
        with self.assertRaises(report.InputError):
            report.parse_frames_csv("", "f.csv")


class ParseSampler(unittest.TestCase):
    def test_parses_rows_with_empty_temp(self):
        got = report.parse_sampler_csv(SAMPLER_CSV, "s.csv")
        self.assertEqual(got[0], report.PowerSample(0.0, 100.0, 2400.0, 90.0, 55.0, 1000.5))
        self.assertIsNone(got[1].temp_c)
        self.assertEqual(got[1].unix_s, 1000.55)

    def test_old_header_without_unix_s_is_rejected(self):
        with self.assertRaises(report.InputError) as ctx:
            report.parse_sampler_csv(
                "time_s,power_w,core_mhz,gpu_busy_percent,temp_c\n0,1,1,1,1\n", "s.csv")
        self.assertIn("s.csv:1", str(ctx.exception))
        self.assertIn("unix_s", str(ctx.exception))

    def test_bad_value_names_file_and_line(self):
        with self.assertRaises(report.InputError) as ctx:
            report.parse_sampler_csv(
                "time_s,power_w,core_mhz,gpu_busy_percent,temp_c,unix_s\n0,x,1,1,1,9\n", "s.csv")
        self.assertIn("s.csv:2", str(ctx.exception))

    def test_bad_header(self):
        with self.assertRaises(report.InputError) as ctx:
            report.parse_sampler_csv("a,b\n", "s.csv")
        self.assertIn("s.csv:1", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
