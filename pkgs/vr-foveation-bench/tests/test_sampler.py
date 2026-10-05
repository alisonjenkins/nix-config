"""Tests for the sysfs sampler, run against a fake sysfs tree."""

import io
import os
import tempfile
import unittest
from pathlib import Path

from tests.helpers import DGPU, IGPU, FakeClock, make_card
from vr_foveation_bench import sampler


class FakeSysfs(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = self._tmp.name


class FindGpu(FakeSysfs):
    def test_selects_by_pci_device_not_hwmon_index(self):
        # The integrated GPU holds the lower hwmon index and card number here;
        # a hwmon4 for the dGPU (as on the real machine) must not matter.
        make_card(self.root, "card0", IGPU, "hwmon5", power_uw=20_000_000)
        make_card(self.root, "card1", DGPU, "hwmon4", power_uw=250_000_000)
        paths = sampler.find_gpu(self.root, DGPU)
        self.assertEqual(sampler.read_sample(paths).power_w, 250.0)

    def test_still_correct_when_indices_are_swapped(self):
        make_card(self.root, "card0", DGPU, "hwmon9", power_uw=250_000_000)
        make_card(self.root, "card1", IGPU, "hwmon1", power_uw=20_000_000)
        paths = sampler.find_gpu(self.root, DGPU)
        self.assertEqual(sampler.read_sample(paths).power_w, 250.0)

    def test_default_device_is_the_discrete_gpu(self):
        make_card(self.root, "card0", IGPU, "hwmon5", power_uw=20_000_000)
        make_card(self.root, "card1", DGPU, "hwmon4", power_uw=250_000_000)
        self.assertEqual(sampler.DEFAULT_PCI_DEVICE, 0x7550)
        paths = sampler.find_gpu(self.root)
        self.assertEqual(sampler.read_sample(paths).power_w, 250.0)

    def test_connector_entries_are_not_cards(self):
        make_card(self.root, "card1", DGPU, "hwmon4")
        conn = Path(self.root) / "class" / "drm" / "card1-DP-1"
        conn.mkdir()
        self.assertEqual(sampler.find_gpu(self.root, DGPU).card, "card1")

    def test_no_matching_device_lists_what_was_found(self):
        make_card(self.root, "card0", IGPU, "hwmon5")
        with self.assertRaises(sampler.GpuNotFound) as ctx:
            sampler.find_gpu(self.root, DGPU)
        self.assertIn("0x7550", str(ctx.exception))
        self.assertIn("0x164e", str(ctx.exception))

    def test_two_matching_cards_is_ambiguous(self):
        make_card(self.root, "card0", DGPU, "hwmon1")
        make_card(self.root, "card1", DGPU, "hwmon2")
        with self.assertRaises(sampler.GpuNotFound) as ctx:
            sampler.find_gpu(self.root, DGPU)
        self.assertIn("card0", str(ctx.exception))
        self.assertIn("card1", str(ctx.exception))

    def test_no_drm_directory(self):
        with self.assertRaises(sampler.GpuNotFound) as ctx:
            sampler.find_gpu(self.root, DGPU)
        self.assertIn(self.root, str(ctx.exception))

    def test_unreadable_device_id_names_the_path(self):
        dev = make_card(self.root, "card0", DGPU, "hwmon1")
        (dev / "device").write_text("garbage\n")
        with self.assertRaises(sampler.SensorError) as ctx:
            sampler.find_gpu(self.root, DGPU)
        self.assertIn(str(dev / "device"), str(ctx.exception))

    def test_card_without_hwmon_dir(self):
        dev = make_card(self.root, "card0", DGPU, "hwmon1")
        os.remove(dev / "hwmon" / "hwmon1" / "power1_average")
        os.remove(dev / "hwmon" / "hwmon1" / "temp1_input")
        os.rmdir(dev / "hwmon" / "hwmon1")
        with self.assertRaises(sampler.SensorError) as ctx:
            sampler.find_gpu(self.root, DGPU)
        self.assertIn(str(dev / "hwmon"), str(ctx.exception))

    def test_picks_the_hwmon_that_has_power(self):
        dev = make_card(self.root, "card0", DGPU, "hwmon3", power_uw=90_000_000)
        (dev / "hwmon" / "hwmon2").mkdir()
        paths = sampler.find_gpu(self.root, DGPU)
        self.assertEqual(paths.hwmon, dev / "hwmon" / "hwmon3")


class ReadSample(FakeSysfs):
    def test_units(self):
        make_card(self.root, "card1", DGPU, "hwmon4", power_uw=123_456_000,
                  temp_mc=61_500, busy=87)
        r = sampler.read_sample(sampler.find_gpu(self.root, DGPU))
        self.assertAlmostEqual(r.power_w, 123.456)
        self.assertEqual(r.core_mhz, 2400.0)
        self.assertEqual(r.gpu_busy_percent, 87.0)
        self.assertEqual(r.temp_c, 61.5)

    def test_core_clock_is_the_starred_line(self):
        make_card(self.root, "card1", DGPU, "hwmon4",
                  sclk="0: 500Mhz *\n1: 2400Mhz\n")
        self.assertEqual(sampler.read_sample(sampler.find_gpu(self.root, DGPU)).core_mhz, 500.0)

    def test_no_starred_line_is_an_error_naming_the_file(self):
        dev = make_card(self.root, "card1", DGPU, "hwmon4", sclk="0: 500Mhz\n")
        with self.assertRaises(sampler.SensorError) as ctx:
            sampler.read_sample(sampler.find_gpu(self.root, DGPU))
        self.assertIn(str(dev / "pp_dpm_sclk"), str(ctx.exception))

    def test_missing_power_is_an_error_naming_the_path(self):
        dev = make_card(self.root, "card1", DGPU, "hwmon4")
        paths = sampler.find_gpu(self.root, DGPU)
        os.remove(dev / "hwmon" / "hwmon4" / "power1_average")
        with self.assertRaises(sampler.SensorError) as ctx:
            sampler.read_sample(paths)
        self.assertIn(str(dev / "hwmon" / "hwmon4" / "power1_average"), str(ctx.exception))

    def test_missing_busy_is_an_error_naming_the_path(self):
        dev = make_card(self.root, "card1", DGPU, "hwmon4")
        paths = sampler.find_gpu(self.root, DGPU)
        os.remove(dev / "gpu_busy_percent")
        with self.assertRaises(sampler.SensorError) as ctx:
            sampler.read_sample(paths)
        self.assertIn("gpu_busy_percent", str(ctx.exception))

    def test_non_numeric_power_names_path_and_value(self):
        dev = make_card(self.root, "card1", DGPU, "hwmon4")
        (dev / "hwmon" / "hwmon4" / "power1_average").write_text("n/a\n")
        with self.assertRaises(sampler.SensorError) as ctx:
            sampler.read_sample(sampler.find_gpu(self.root, DGPU))
        self.assertIn("power1_average", str(ctx.exception))
        self.assertIn("n/a", str(ctx.exception))

    def test_missing_temp_is_none_not_an_error(self):
        make_card(self.root, "card1", DGPU, "hwmon4", with_temp=False)
        r = sampler.read_sample(sampler.find_gpu(self.root, DGPU))
        self.assertIsNone(r.temp_c)


class RunSampler(FakeSysfs):
    def run_for(self, duration, interval, **card):
        make_card(self.root, "card1", DGPU, "hwmon4", **card)
        paths = sampler.find_gpu(self.root, DGPU)
        fake = FakeClock()
        out = io.StringIO()
        count = sampler.run(paths, out, interval, duration, fake.clock, fake.wall, fake.sleep)
        return count, out.getvalue().splitlines(), fake

    def test_header_and_rows_with_time_relative_to_start(self):
        count, lines, fake = self.run_for(1.0, 0.25)
        self.assertEqual(lines[0], "time_s,power_w,core_mhz,gpu_busy_percent,temp_c,unix_s")
        self.assertEqual(count, 5)
        self.assertEqual(len(lines), 6)
        self.assertEqual(lines[1], "0.000,100.000,2400,42,55.0,1700001000.000")
        self.assertEqual(lines[5].split(",")[0], "1.000")
        self.assertEqual(lines[5].split(",")[5], "1700001001.000")
        self.assertEqual(fake.sleeps, [0.25] * 4)

    def test_missing_temp_writes_an_empty_field(self):
        _, lines, _ = self.run_for(0.5, 0.25, with_temp=False)
        self.assertEqual(lines[1], "0.000,100.000,2400,42,,1700001000.000")

    def test_missing_required_sensor_stops_with_the_path(self):
        with self.assertRaises(sampler.SensorError) as ctx:
            self.run_for(1.0, 0.25, with_power=False)
        self.assertIn("power1_average", str(ctx.exception))

    def test_stop_callback_ends_the_loop(self):
        make_card(self.root, "card1", DGPU, "hwmon4")
        paths = sampler.find_gpu(self.root, DGPU)
        fake = FakeClock()
        out = io.StringIO()
        count = sampler.run(paths, out, 0.25, None, fake.clock, fake.wall, fake.sleep,
                            should_stop=lambda: len(fake.sleeps) >= 3)
        self.assertEqual(count, 4)

    def test_non_positive_interval_rejected(self):
        make_card(self.root, "card1", DGPU, "hwmon4")
        paths = sampler.find_gpu(self.root, DGPU)
        fake = FakeClock()
        with self.assertRaises(ValueError):
            sampler.run(paths, io.StringIO(), 0.0, 1.0, fake.clock, fake.wall, fake.sleep)

    def test_never_writes_to_sysfs(self):
        make_card(self.root, "card1", DGPU, "hwmon4")
        before = {p: (p.read_text(), p.stat().st_mtime_ns)
                  for p in Path(self.root).rglob("*") if p.is_file()}
        self.run_for_existing()
        after = {p: (p.read_text(), p.stat().st_mtime_ns)
                 for p in Path(self.root).rglob("*") if p.is_file()}
        self.assertEqual(before, after)

    def run_for_existing(self):
        paths = sampler.find_gpu(self.root, DGPU)
        fake = FakeClock()
        sampler.run(paths, io.StringIO(), 0.25, 0.5, fake.clock, fake.wall, fake.sleep)

    def test_default_interval_is_twenty_hertz(self):
        self.assertEqual(sampler.DEFAULT_INTERVAL_S, 0.05)


if __name__ == "__main__":
    unittest.main()
