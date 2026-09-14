"""Localization-cue extraction and the psychoacoustic ground truth to score
against.

ITD alone cannot disambiguate front from back — a source at azimuth 30 deg
and its mirror at 150 deg produce the same interaural delay (the "cone of
confusion"). That's not a bug in the ITD scoring below, it's the reason a
separate front/back spectral-asymmetry score exists (see `front_back_score`):
ITD/ILD get scored against how well they match the expected magnitude for a
listener's actual lateral angle, and front/back discrimination gets scored
separately, on the cue that's actually responsible for it.
"""

from __future__ import annotations

import math

import numpy as np
from scipy.optimize import brentq

SPEED_OF_SOUND_M_S = 343.0
KEMAR_HEAD_RADIUS_M = 0.0875


def fold_to_front_hemisphere(azimuth_deg: float) -> float:
    """Lateral angle in [0, 90] that (azimuth, its front/back mirror) share.

    0 = straight ahead or straight behind, 90 = directly left or right.
    """
    az = azimuth_deg % 360.0
    signed = az if az <= 180.0 else az - 360.0  # (-180, 180]
    lateral = abs(signed)
    return lateral if lateral <= 90.0 else 180.0 - lateral


def signed_lateral_deg(azimuth_deg: float) -> float:
    az = azimuth_deg % 360.0
    signed = az if az <= 180.0 else az - 360.0
    return signed  # positive = left half, negative = right half


def woodworth_itd_seconds(
    azimuth_deg: float,
    elevation_deg: float = 0.0,
    head_radius_m: float = KEMAR_HEAD_RADIUS_M,
    speed_of_sound: float = SPEED_OF_SOUND_M_S,
) -> float:
    """Signed ITD (t_right_ear - t_left_ear) for a source at
    (`azimuth_deg`, `elevation_deg`).

    Positive = right ear lags = source on the left, matching this repo's
    azimuth convention (0 front, 90 hard left, ccw).

    The plain Woodworth formula only models the horizontal plane. A source
    overhead (elevation -> 90) reaches both ears at once regardless of
    azimuth, so the interaural path difference shrinks as the source lifts
    out of that plane — scaling by cos(elevation) is the standard
    first-order correction for that (e.g. Duda & Martens' spherical-head
    model). Skipping it would make every elevation sweep above 0 degrees
    score against a target ITD the real chain has no way to reach, and the
    "error" would just be measuring the model's own blind spot.
    """
    theta_deg = fold_to_front_hemisphere(azimuth_deg)
    theta = math.radians(theta_deg)
    magnitude = (head_radius_m / speed_of_sound) * (theta + math.sin(theta)) * math.cos(math.radians(elevation_deg))
    lateral = signed_lateral_deg(azimuth_deg)
    sign = 1.0 if lateral > 0 else (-1.0 if lateral < 0 else 0.0)
    return sign * magnitude


def max_woodworth_itd_seconds(
    head_radius_m: float = KEMAR_HEAD_RADIUS_M,
    speed_of_sound: float = SPEED_OF_SOUND_M_S,
) -> float:
    """ITD magnitude at theta=90 degrees — the model's maximum, reached at
    the sides. Used both to bound the inversion below and as the GCC-PHAT
    search window: clipping that window any tighter than this would cut off
    the true peak for a source near the side and silently return a shorter,
    wrong lag instead.
    """
    return (head_radius_m / speed_of_sound) * (math.pi / 2 + 1.0)


# 20% headroom over the Woodworth max: a real HRIR's actual peak lag can run
# slightly past the idealized-sphere bound (pinna/torso effects), and
# clipping the GCC-PHAT search window any tighter risks cutting off the true
# peak and returning a shorter, wrong lag instead. Shared by the offline
# (scoring.py) and live (live.py) paths so a future retune only happens once.
GCC_PHAT_SEARCH_WINDOW_HEADROOM = 1.2


def gcc_phat_search_window_seconds(
    head_radius_m: float = KEMAR_HEAD_RADIUS_M,
    speed_of_sound: float = SPEED_OF_SOUND_M_S,
) -> float:
    return GCC_PHAT_SEARCH_WINDOW_HEADROOM * max_woodworth_itd_seconds(head_radius_m, speed_of_sound)


def itd_to_lateral_angle_deg(
    itd_seconds: float,
    head_radius_m: float = KEMAR_HEAD_RADIUS_M,
    speed_of_sound: float = SPEED_OF_SOUND_M_S,
) -> float:
    """Invert the Woodworth model: recover the [0, 90] lateral angle implied
    by a measured (unsigned) ITD magnitude. Monotonic on [0, pi/2], so a
    plain root-find is exact up to solver tolerance.
    """
    magnitude = abs(itd_seconds)
    max_magnitude = max_woodworth_itd_seconds(head_radius_m, speed_of_sound)
    if magnitude >= max_magnitude:
        return 90.0
    if magnitude <= 0:
        return 0.0

    def f(theta_rad: float) -> float:
        return (head_radius_m / speed_of_sound) * (theta_rad + math.sin(theta_rad)) - magnitude

    theta_rad = brentq(f, 0.0, math.pi / 2)
    return math.degrees(theta_rad)


def itd_angular_error_deg(
    measured_itd_seconds: float,
    true_azimuth_deg: float,
    true_elevation_deg: float = 0.0,
    head_radius_m: float = KEMAR_HEAD_RADIUS_M,
    speed_of_sound: float = SPEED_OF_SOUND_M_S,
) -> float:
    """Angular error, expressed as the gap between two "equivalent 0-degree-
    elevation lateral angles": the one implied by the measured ITD, and the
    one implied by the elevation-corrected expected ITD for the true
    (azimuth, elevation). Both go through the same (elevation-agnostic)
    inversion, so the model's own elevation approximation cancels out of the
    comparison instead of showing up as a fake error at non-zero elevation.
    """
    expected_itd = woodworth_itd_seconds(true_azimuth_deg, true_elevation_deg, head_radius_m, speed_of_sound)
    estimated = itd_to_lateral_angle_deg(measured_itd_seconds, head_radius_m, speed_of_sound)
    expected = itd_to_lateral_angle_deg(expected_itd, head_radius_m, speed_of_sound)
    return abs(estimated - expected)


def gcc_phat(
    left: np.ndarray,
    right: np.ndarray,
    fs: float,
    max_tau: float | None = None,
    upsample: int = 16,
) -> float:
    """Estimated ITD (seconds) between two signals via GCC-PHAT.

    Returns t_right - t_left: positive means the peak of the (right, left)
    cross-correlation falls at a positive lag, i.e. right arrives later.
    """
    n = left.shape[0] + right.shape[0]
    fft_len = 1
    while fft_len < n:
        fft_len *= 2

    left_fft = np.fft.rfft(left, n=fft_len)
    right_fft = np.fft.rfft(right, n=fft_len)
    cross = right_fft * np.conj(left_fft)
    cross /= np.maximum(np.abs(cross), 1e-15)

    upsampled_len = fft_len * upsample
    corr = np.fft.irfft(cross, n=upsampled_len)
    corr = np.concatenate((corr[-upsampled_len // 2 :], corr[: upsampled_len // 2]))

    max_shift = upsampled_len // 2
    if max_tau is not None:
        max_shift = min(int(max_tau * fs * upsample), max_shift)
        center = upsampled_len // 2
        corr = corr[center - max_shift : center + max_shift + 1]

    peak_idx = int(np.argmax(corr))
    # Parabolic sub-sample interpolation around the peak.
    if 0 < peak_idx < len(corr) - 1:
        y0, y1, y2 = corr[peak_idx - 1], corr[peak_idx], corr[peak_idx + 1]
        denom = y0 - 2 * y1 + y2
        offset = 0.5 * (y0 - y2) / denom if denom != 0 else 0.0
    else:
        offset = 0.0

    shift = (peak_idx + offset) - max_shift
    return shift / (fs * upsample)


def band_rms_db_ratio(
    left: np.ndarray,
    right: np.ndarray,
    fs: float,
    low_hz: float,
    high_hz: float,
) -> float:
    """ILD in dB for the [low_hz, high_hz] band: 20*log10(rms(left)/rms(right)).

    Positive = left louder = source lateralized left, matching the ITD sign
    convention above.
    """
    from scipy.signal import butter, sosfiltfilt

    nyq = fs / 2
    lo = max(low_hz, 1.0) / nyq
    hi = min(high_hz, nyq - 1.0) / nyq
    sos = butter(4, [lo, hi], btype="bandpass", output="sos")
    left_band = sosfiltfilt(sos, left)
    right_band = sosfiltfilt(sos, right)
    left_rms = np.sqrt(np.mean(left_band**2)) + 1e-15
    right_rms = np.sqrt(np.mean(right_band**2)) + 1e-15
    return float(20 * np.log10(left_rms / right_rms))


def log_spectral_distance_db(a: np.ndarray, b: np.ndarray, fs: float, low_hz: float, high_hz: float) -> float:
    """RMS difference, in dB, between two signals' log-magnitude spectra
    within [low_hz, high_hz]. Used to score front/back discriminability: a
    large distance between a direction and its ITD/ILD-identical mirror
    means the spectral (pinna) cue that disambiguates them is intact.
    """
    n = max(a.shape[0], b.shape[0])
    fft_len = 1
    while fft_len < n:
        fft_len *= 2
    freqs = np.fft.rfftfreq(fft_len, d=1.0 / fs)
    band = (freqs >= low_hz) & (freqs <= high_hz)

    mag_a = np.abs(np.fft.rfft(a, n=fft_len))[band]
    mag_b = np.abs(np.fft.rfft(b, n=fft_len))[band]
    log_a = 20 * np.log10(np.maximum(mag_a, 1e-9))
    log_b = 20 * np.log10(np.maximum(mag_b, 1e-9))
    return float(np.sqrt(np.mean((log_a - log_b) ** 2)))
