"""Sweep a HRIR set across azimuth/elevation and score localization cues."""

from __future__ import annotations

import dataclasses

import numpy as np
from scipy.signal import fftconvolve

from . import localization
from .biquad import BiquadStage, apply_cascade
from .sofa import HRIRSet

SAMPLE_RATE_HZ = 48000.0
BURST_SECONDS = 0.2
ILD_LOW_BAND_HZ = (20.0, 1500.0)
ILD_HIGH_BAND_HZ = (3000.0, 8000.0)
FRONTBACK_BAND_HZ = (4000.0, 10000.0)

DEFAULT_AZIMUTHS_DEG = tuple(range(0, 360, 15))
DEFAULT_ELEVATIONS_DEG = (-30.0, 0.0, 30.0, 60.0)


def make_test_burst(fs: float = SAMPLE_RATE_HZ, seconds: float = BURST_SECONDS, seed: int = 0) -> np.ndarray:
    """Tukey-windowed pink noise burst — broadband energy for both the
    low-frequency ITD cue and the high-frequency ILD/spectral-notch cues,
    windowed so onset/offset transients don't distort the cross-correlation.
    """
    from scipy.signal.windows import tukey

    n = int(fs * seconds)
    rng = np.random.default_rng(seed)
    white = rng.standard_normal(n)
    # Pink-ish via 1/sqrt(f) shaping in the frequency domain.
    spectrum = np.fft.rfft(white)
    freqs = np.fft.rfftfreq(n, d=1.0 / fs)
    freqs[0] = freqs[1]  # avoid divide-by-zero at DC
    spectrum = spectrum / np.sqrt(freqs)
    pink = np.fft.irfft(spectrum, n=n)
    pink /= np.max(np.abs(pink)) + 1e-15
    return pink * tukey(n, alpha=0.1)


@dataclasses.dataclass(frozen=True)
class AnglePoint:
    azimuth_deg: float
    elevation_deg: float
    itd_error_deg: float
    ild_low_db: float
    ild_high_db: float


@dataclasses.dataclass(frozen=True)
class SweepResult:
    points: list[AnglePoint]
    # None only from live.run_live_verify, which can't guarantee a speaker
    # layout has front/back mirror channel pairs to measure.
    frontback_score_db: float | None
    mean_itd_error_deg: float
    max_itd_error_deg: float
    max_itd_error_at: tuple[float, float]


def binauralize(
    hrir: HRIRSet,
    azimuth_deg: float,
    elevation_deg: float,
    burst: np.ndarray,
    eq_stages: list[BiquadStage],
) -> tuple[np.ndarray, np.ndarray]:
    ir_left, ir_right = hrir.nearest(azimuth_deg, elevation_deg)
    left = fftconvolve(burst, ir_left, mode="full")
    right = fftconvolve(burst, ir_right, mode="full")
    if eq_stages:
        left = apply_cascade(left, eq_stages, hrir.sample_rate)
        right = apply_cascade(right, eq_stages, hrir.sample_rate)
    return left, right


def score_point(
    hrir: HRIRSet,
    azimuth_deg: float,
    elevation_deg: float,
    burst: np.ndarray,
    eq_stages: list[BiquadStage],
    head_radius_m: float = localization.KEMAR_HEAD_RADIUS_M,
) -> AnglePoint:
    left, right = binauralize(hrir, azimuth_deg, elevation_deg, burst, eq_stages)
    fs = hrir.sample_rate

    max_tau = localization.gcc_phat_search_window_seconds(head_radius_m, localization.SPEED_OF_SOUND_M_S)
    measured_itd = localization.gcc_phat(left, right, fs, max_tau=max_tau)
    itd_error = localization.itd_angular_error_deg(measured_itd, azimuth_deg, elevation_deg, head_radius_m)

    ild_low = localization.band_rms_db_ratio(left, right, fs, *ILD_LOW_BAND_HZ)
    ild_high = localization.band_rms_db_ratio(left, right, fs, *ILD_HIGH_BAND_HZ)

    return AnglePoint(
        azimuth_deg=azimuth_deg,
        elevation_deg=elevation_deg,
        itd_error_deg=itd_error,
        ild_low_db=ild_low,
        ild_high_db=ild_high,
    )


def _near_ear_signal(left: np.ndarray, right: np.ndarray, azimuth_deg: float) -> np.ndarray:
    lateral = localization.signed_lateral_deg(azimuth_deg)
    if lateral > 0:
        return left
    if lateral < 0:
        return right
    return left


def front_back_score(
    hrir: HRIRSet,
    azimuth_deg: float,
    elevation_deg: float,
    burst: np.ndarray,
    eq_stages: list[BiquadStage],
) -> float:
    """Spectral distance, in the pinna-cue band, between `azimuth_deg` and
    its front/back mirror — the two share identical ITD/ILD, so only this
    distance is available to disambiguate them.
    """
    mirror = 180.0 - azimuth_deg
    left_a, right_a = binauralize(hrir, azimuth_deg, elevation_deg, burst, eq_stages)
    left_b, right_b = binauralize(hrir, mirror, elevation_deg, burst, eq_stages)
    ear_a = _near_ear_signal(left_a, right_a, azimuth_deg)
    ear_b = _near_ear_signal(left_b, right_b, azimuth_deg)
    return localization.log_spectral_distance_db(ear_a, ear_b, hrir.sample_rate, *FRONTBACK_BAND_HZ)


def run_sweep(
    hrir: HRIRSet,
    eq_stages: list[BiquadStage],
    azimuths_deg: tuple[float, ...] = DEFAULT_AZIMUTHS_DEG,
    elevations_deg: tuple[float, ...] = DEFAULT_ELEVATIONS_DEG,
    head_radius_m: float = localization.KEMAR_HEAD_RADIUS_M,
) -> SweepResult:
    burst = make_test_burst(fs=hrir.sample_rate)

    points = [
        score_point(hrir, az, el, burst, eq_stages, head_radius_m)
        for el in elevations_deg
        for az in azimuths_deg
    ]

    errors = [p.itd_error_deg for p in points]
    max_idx = int(np.argmax(errors))

    # Front/back score at 0-degree elevation only: mirroring by azimuth
    # assumes the source stays in the horizontal plane the pinna-cue model
    # was reasoned about; off-axis elevations get their own confusion
    # geometry that this metric doesn't attempt to capture in v1.
    #
    # Excludes azimuths where the mirror (180 - az) lands back on az itself
    # (az % 180 == 90, i.e. az = 90 or 270): those are the interaural poles,
    # directly left/right, where front and back genuinely collapse to the
    # same physical point. front_back_score there always returns exactly
    # 0.0 regardless of chain quality — not a low score, a meaningless one —
    # and including it would drag the aggregate down with pure noise. 0 and
    # 180 (dead ahead/behind) stay in: they're a real, non-degenerate mirror
    # pair and carry real information.
    frontback_scores = [
        front_back_score(hrir, az, 0.0, burst, eq_stages)
        for az in azimuths_deg
        if az % 180 != 90
    ]
    frontback_score = float(np.mean(frontback_scores)) if frontback_scores else 0.0

    return SweepResult(
        points=points,
        frontback_score_db=frontback_score,
        mean_itd_error_deg=float(np.mean(errors)),
        max_itd_error_deg=float(errors[max_idx]),
        max_itd_error_at=(points[max_idx].azimuth_deg, points[max_idx].elevation_deg),
    )
