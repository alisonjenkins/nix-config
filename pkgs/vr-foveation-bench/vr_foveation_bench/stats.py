"""Statistics rule for comparing a condition's runs (research.md D7).

A run is one measured session; its metric is a single number (median frame
time, mean power). A condition ('off' or 'on') is several runs. A gain counts
only when it clears the run-to-run noise, not merely when the means differ.
"""

import math
import statistics
from dataclasses import dataclass
from typing import Optional, Sequence, Tuple

MIN_RUNS = 3
NOISE_FACTOR = 2.0


class InvalidSample(ValueError):
    """A sample is empty, non-finite or negative; the message names where."""


class TooFewRuns(ValueError):
    """A condition has fewer than MIN_RUNS runs, so noise cannot be judged."""


class UnequalRunCounts(ValueError):
    """off and on have different run counts, so runs cannot be paired."""


def _check_value(value: float, where: str) -> None:
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        raise InvalidSample(f"{where}: not a number: {value!r}")
    if not math.isfinite(value):
        raise InvalidSample(f"{where}: not finite: {value!r}")
    if value < 0:
        raise InvalidSample(f"{where}: negative: {value!r}")


def _check_values(values: Sequence[float], run: str) -> None:
    if len(values) == 0:
        raise InvalidSample(f"{run}: no values")
    for i, v in enumerate(values):
        _check_value(v, f"{run}: index {i}")


def run_median(values: Sequence[float], run: str = "run") -> float:
    """Median of a run's per-frame values (mean of the middle two if even)."""
    _check_values(values, run)
    return float(statistics.median(values))


def percentile_nearest_rank(values: Sequence[float], pct: int, run: str = "run") -> float:
    """Nearest-rank percentile: the value at 1-based rank ceil(pct/100 * n).

    Integer arithmetic, so 99 % of 1000 frames is exactly rank 990 rather than
    whatever float rounding gives. Always returns a member of `values`.
    """
    if not isinstance(pct, int) or not 1 <= pct <= 100:
        raise ValueError(f"pct must be an integer in 1..100, got {pct!r}")
    _check_values(values, run)
    rank = (pct * len(values) + 99) // 100
    return float(sorted(values)[rank - 1])


def run_p99(values: Sequence[float], run: str = "run") -> float:
    return percentile_nearest_rank(values, 99, run)


def mean_power(samples: Sequence[Tuple[float, float]], run: str = "run") -> float:
    """Mean power in W: trapezoid-integrated energy over elapsed time.

    `samples` is (time_s, power_w), strictly increasing in time. Weighting by
    time keeps an irregular sampler from biasing the mean.
    """
    if len(samples) < 2:
        raise InvalidSample(f"{run}: need at least 2 power samples, got {len(samples)}")
    energy_j = 0.0
    for i, (t, p) in enumerate(samples):
        _check_value(t, f"{run}: sample {i} time")
        _check_value(p, f"{run}: sample {i} power")
        if i == 0:
            continue
        t_prev, p_prev = samples[i - 1]
        if t <= t_prev:
            raise InvalidSample(
                f"{run}: sample {i} time {t!r} is not after sample {i - 1} time {t_prev!r}")
        energy_j += (p + p_prev) / 2.0 * (t - t_prev)
    return energy_j / (samples[-1][0] - samples[0][0])


def noise(values: Sequence[float], run: str = "condition") -> float:
    """Spread (max - min) of a condition's per-run values."""
    _check_values(values, run)
    return float(max(values) - min(values))


@dataclass(frozen=True)
class Gain:
    diff: float
    relative_change: float
    noise_off: float
    noise_on: float
    median_off: float
    median_on: float
    exceeds_noise: bool
    same_sign_in_every_pair: bool

    @property
    def beyond_noise(self) -> bool:
        return self.exceeds_noise and self.same_sign_in_every_pair


def _sign(x: float) -> int:
    return (x > 0) - (x < 0)


def _validate_condition(label: str, values: Sequence[float]) -> None:
    if len(values) < MIN_RUNS:
        raise TooFewRuns(
            f"{label}: {len(values)} run(s), need at least {MIN_RUNS} to judge noise")
    for i, v in enumerate(values):
        _check_value(v, f"{label} run {i}")


def gain_beyond_noise(off_runs: Sequence[float], on_runs: Sequence[float],
                      label: Optional[str] = None) -> Gain:
    """Judge whether on differs from off by more than noise.

    Beyond noise needs both: |median(on) - median(off)| strictly above twice
    the larger within-condition noise, and the same sign of (on_i - off_i) as
    the overall difference in every interleaved pair (a tie fails). There is
    no minimum percentage (spec SC-001): any change that clears the noise
    counts. Both directions are reported; a reduction is
    `beyond_noise and diff < 0`.
    """
    suffix = f" ({label})" if label else ""
    _validate_condition(f"off{suffix}", off_runs)
    _validate_condition(f"on{suffix}", on_runs)
    if len(off_runs) != len(on_runs):
        raise UnequalRunCounts(
            f"off{suffix} has {len(off_runs)} runs but on has {len(on_runs)}; "
            "runs are compared in interleaved pairs")
    median_off = float(statistics.median(off_runs))
    median_on = float(statistics.median(on_runs))
    if median_off <= 0:
        raise InvalidSample(f"off{suffix}: median of runs is {median_off!r}, cannot take a relative change")
    diff = median_on - median_off
    noise_off = noise(off_runs)
    noise_on = noise(on_runs)
    diff_sign = _sign(diff)
    same_sign = diff_sign != 0 and all(
        _sign(on - off) == diff_sign for off, on in zip(off_runs, on_runs))
    return Gain(
        diff=diff,
        relative_change=diff / median_off,
        noise_off=noise_off,
        noise_on=noise_on,
        median_off=median_off,
        median_on=median_on,
        exceeds_noise=abs(diff) > NOISE_FACTOR * max(noise_off, noise_on),
        same_sign_in_every_pair=same_sign,
    )
