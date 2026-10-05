"""Tests for the measurement statistics rule."""

import math
import unittest

from vr_foveation_bench import stats


class RunMedianAndP99(unittest.TestCase):
    def test_median_odd_and_even(self):
        self.assertEqual(stats.run_median([3.0, 1.0, 2.0]), 2.0)
        self.assertEqual(stats.run_median([4.0, 1.0, 2.0, 3.0]), 2.5)

    def test_p99_is_nearest_rank(self):
        values = [float(i) for i in range(1, 101)]
        self.assertEqual(stats.run_p99(values), 99.0)

    def test_p99_nearest_rank_rounds_up_for_small_runs(self):
        self.assertEqual(stats.run_p99([5.0, 1.0, 9.0]), 9.0)

    def test_p99_exact_rank_boundary_not_float_fuzzed(self):
        values = [float(i) for i in range(1, 1001)]
        self.assertEqual(stats.run_p99(values), 990.0)

    def test_single_value(self):
        self.assertEqual(stats.run_median([7.0]), 7.0)
        self.assertEqual(stats.run_p99([7.0]), 7.0)

    def test_empty_run_names_the_run(self):
        with self.assertRaises(stats.InvalidSample) as ctx:
            stats.run_median([], run="off run 2")
        self.assertIn("off run 2", str(ctx.exception))

    def test_nan_names_run_and_index(self):
        with self.assertRaises(stats.InvalidSample) as ctx:
            stats.run_median([1.0, math.nan], run="on run 1")
        self.assertIn("on run 1", str(ctx.exception))
        self.assertIn("index 1", str(ctx.exception))

    def test_negative_value_rejected(self):
        with self.assertRaises(stats.InvalidSample) as ctx:
            stats.run_p99([1.0, -0.5], run="r")
        self.assertIn("-0.5", str(ctx.exception))

    def test_inf_rejected(self):
        with self.assertRaises(stats.InvalidSample):
            stats.run_median([1.0, math.inf])


class MeanPower(unittest.TestCase):
    def test_constant_power(self):
        self.assertEqual(stats.mean_power([(0.0, 100.0), (1.0, 100.0), (2.0, 100.0)]), 100.0)

    def test_trapezoid_integrates_energy_over_time(self):
        # energy = (0+100)/2*1 + (100+100)/2*3 = 350 J over 4 s
        samples = [(0.0, 0.0), (1.0, 100.0), (4.0, 100.0)]
        self.assertEqual(stats.mean_power(samples), 87.5)

    def test_unequal_spacing_is_time_weighted_not_sample_averaged(self):
        samples = [(0.0, 10.0), (0.1, 10.0), (10.0, 20.0)]
        # (1.0 + 148.5) J over 10 s; a plain sample average would be 13.33
        self.assertAlmostEqual(stats.mean_power(samples), 14.95)

    def test_needs_two_samples(self):
        with self.assertRaises(stats.InvalidSample):
            stats.mean_power([(0.0, 5.0)], run="r1")

    def test_non_increasing_time_rejected(self):
        with self.assertRaises(stats.InvalidSample) as ctx:
            stats.mean_power([(0.0, 5.0), (0.0, 6.0)], run="r1")
        self.assertIn("sample 1", str(ctx.exception))

    def test_negative_power_rejected(self):
        with self.assertRaises(stats.InvalidSample):
            stats.mean_power([(0.0, 5.0), (1.0, -1.0)])

    def test_nan_power_rejected(self):
        with self.assertRaises(stats.InvalidSample):
            stats.mean_power([(0.0, 5.0), (1.0, math.nan)])


class Noise(unittest.TestCase):
    def test_spread(self):
        self.assertEqual(stats.noise([10.0, 10.5, 9.75]), 0.75)

    def test_identical(self):
        self.assertEqual(stats.noise([4.0, 4.0, 4.0]), 0.0)

    def test_empty_rejected(self):
        with self.assertRaises(stats.InvalidSample):
            stats.noise([])


class GainBeyondNoise(unittest.TestCase):
    def test_clear_reduction(self):
        r = stats.gain_beyond_noise([10.0, 10.5, 10.0], [8.0, 8.5, 8.0])
        self.assertTrue(r.beyond_noise)
        self.assertEqual(r.diff, -2.0)
        self.assertEqual(r.noise_off, 0.5)
        self.assertEqual(r.noise_on, 0.5)
        self.assertEqual(r.relative_change, -0.2)

    def test_clear_increase_is_beyond_noise_with_positive_diff(self):
        r = stats.gain_beyond_noise([10.0, 10.5, 10.0], [12.0, 12.5, 12.0])
        self.assertTrue(r.beyond_noise)
        self.assertGreater(r.diff, 0)

    def test_identical_runs_are_not_a_gain(self):
        r = stats.gain_beyond_noise([5.0, 5.0, 5.0], [5.0, 5.0, 5.0])
        self.assertFalse(r.beyond_noise)
        self.assertEqual(r.diff, 0.0)

    def test_exactly_at_noise_threshold_is_not_beyond(self):
        # diff -1.0, threshold 2 * 0.5 = 1.0, strict inequality
        r = stats.gain_beyond_noise([10.0, 10.5, 10.0], [9.0, 9.5, 9.0])
        self.assertEqual(r.diff, -1.0)
        self.assertFalse(r.beyond_noise)

    def test_just_past_noise_threshold_is_beyond(self):
        r = stats.gain_beyond_noise([10.0, 10.5, 10.0], [8.9, 9.4, 8.9])
        self.assertTrue(r.beyond_noise)

    def test_a_small_reduction_beyond_noise_counts(self):
        # spec SC-001: no minimum percentage, only noise decides
        r = stats.gain_beyond_noise([100.0, 100.0, 100.0], [99.5, 99.5, 99.5])
        self.assertTrue(r.beyond_noise)
        self.assertAlmostEqual(r.relative_change, -0.005)

    def test_a_tiny_change_inside_noise_does_not_count(self):
        r = stats.gain_beyond_noise([100.0, 100.4, 100.0], [99.5, 99.9, 99.5])
        self.assertFalse(r.beyond_noise)

    def test_larger_of_the_two_noises_sets_the_threshold(self):
        # on is noisy (1.0), off is quiet: threshold 2.0, diff -1.5 fails
        r = stats.gain_beyond_noise([10.0, 10.0, 10.0], [8.5, 8.0, 9.0])
        self.assertEqual(r.noise_on, 1.0)
        self.assertFalse(r.beyond_noise)

    def test_one_outlier_run_widens_noise_and_blocks_the_claim(self):
        r = stats.gain_beyond_noise([10.0, 10.0, 10.0, 10.0, 10.0], [8.0, 8.0, 8.0, 8.0, 12.0])
        self.assertEqual(r.noise_on, 4.0)
        self.assertFalse(r.beyond_noise)

    def test_sign_flip_in_one_pair_blocks_the_claim(self):
        # medians differ by -2.0 with tiny noise, but pair 3 goes the other way
        off = [10.0, 10.1, 10.0, 10.1, 10.0]
        on = [8.0, 8.1, 10.2, 8.1, 8.0]
        r = stats.gain_beyond_noise(off, on)
        self.assertFalse(r.beyond_noise)
        self.assertFalse(r.same_sign_in_every_pair)

    def test_tie_in_a_pair_counts_as_not_same_sign(self):
        r = stats.gain_beyond_noise([10.0, 10.0, 10.0], [8.0, 10.0, 8.0])
        self.assertFalse(r.same_sign_in_every_pair)

    def test_fewer_than_three_off_runs(self):
        with self.assertRaises(stats.TooFewRuns) as ctx:
            stats.gain_beyond_noise([1.0, 2.0], [1.0, 2.0, 3.0])
        self.assertIn("off", str(ctx.exception))
        self.assertIn("2", str(ctx.exception))

    def test_fewer_than_three_on_runs(self):
        with self.assertRaises(stats.TooFewRuns) as ctx:
            stats.gain_beyond_noise([1.0, 2.0, 3.0], [1.0])
        self.assertIn("on", str(ctx.exception))

    def test_unequal_run_counts_cannot_be_paired(self):
        with self.assertRaises(stats.UnequalRunCounts):
            stats.gain_beyond_noise([10.0] * 4, [8.0] * 5)

    def test_bad_value_names_condition_and_run(self):
        with self.assertRaises(stats.InvalidSample) as ctx:
            stats.gain_beyond_noise([10.0, math.nan, 10.0], [8.0, 8.0, 8.0])
        self.assertIn("off", str(ctx.exception))
        self.assertIn("run 1", str(ctx.exception))

    def test_zero_off_median_rejected(self):
        with self.assertRaises(stats.InvalidSample):
            stats.gain_beyond_noise([0.0, 0.0, 0.0], [1.0, 1.0, 1.0])


if __name__ == "__main__":
    unittest.main()
