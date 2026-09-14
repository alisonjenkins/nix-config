"""RBJ cookbook biquads, matching PipeWire SPA filter-chain's `bq_lowshelf` /
`bq_peaking` / `bq_highshelf` plugins so the offline simulation scores the
same math the real chain runs.

Reference: Robert Bristow-Johnson, "Cookbook formulae for audio EQ biquad
filter coefficients" — the formulas SPA's biquad plugin implements.
"""

from __future__ import annotations

import dataclasses
import math

import numpy as np
from scipy.signal import lfilter


@dataclasses.dataclass(frozen=True)
class BiquadStage:
    type: str  # "bq_lowshelf" | "bq_peaking" | "bq_highshelf"
    freq: float
    q: float
    gain: float  # dB


def _coeffs(stage: BiquadStage, fs: float) -> tuple[np.ndarray, np.ndarray]:
    a = 10 ** (stage.gain / 40.0)
    w0 = 2 * math.pi * stage.freq / fs
    cos_w0 = math.cos(w0)
    sin_w0 = math.sin(w0)
    alpha = sin_w0 / (2 * stage.q)

    if stage.type == "bq_peaking":
        b0 = 1 + alpha * a
        b1 = -2 * cos_w0
        b2 = 1 - alpha * a
        a0 = 1 + alpha / a
        a1 = -2 * cos_w0
        a2 = 1 - alpha / a
    elif stage.type == "bq_lowshelf":
        sqrt_a = math.sqrt(a)
        b0 = a * ((a + 1) - (a - 1) * cos_w0 + 2 * sqrt_a * alpha)
        b1 = 2 * a * ((a - 1) - (a + 1) * cos_w0)
        b2 = a * ((a + 1) - (a - 1) * cos_w0 - 2 * sqrt_a * alpha)
        a0 = (a + 1) + (a - 1) * cos_w0 + 2 * sqrt_a * alpha
        a1 = -2 * ((a - 1) + (a + 1) * cos_w0)
        a2 = (a + 1) + (a - 1) * cos_w0 - 2 * sqrt_a * alpha
    elif stage.type == "bq_highshelf":
        sqrt_a = math.sqrt(a)
        b0 = a * ((a + 1) + (a - 1) * cos_w0 + 2 * sqrt_a * alpha)
        b1 = -2 * a * ((a - 1) + (a + 1) * cos_w0)
        b2 = a * ((a + 1) + (a - 1) * cos_w0 - 2 * sqrt_a * alpha)
        a0 = (a + 1) - (a - 1) * cos_w0 + 2 * sqrt_a * alpha
        a1 = 2 * ((a - 1) - (a + 1) * cos_w0)
        a2 = (a + 1) - (a - 1) * cos_w0 - 2 * sqrt_a * alpha
    else:
        raise ValueError(f"unknown biquad type {stage.type!r}")

    b = np.array([b0, b1, b2], dtype=np.float64) / a0
    a_coef = np.array([1.0, a1 / a0, a2 / a0], dtype=np.float64)
    return b, a_coef


def frequency_response_db(stage: BiquadStage, freq_hz: float, fs: float) -> float:
    """Magnitude response of a single stage at one frequency, in dB."""
    b, a = _coeffs(stage, fs)
    w = 2 * math.pi * freq_hz / fs
    z_inv = np.exp(-1j * w)
    num = b[0] + b[1] * z_inv + b[2] * z_inv**2
    den = a[0] + a[1] * z_inv + a[2] * z_inv**2
    return float(20 * np.log10(np.abs(num / den)))


def apply_cascade(signal: np.ndarray, stages: list[BiquadStage], fs: float) -> np.ndarray:
    """Apply each stage in order, matching a chained biquad filter-chain."""
    out = signal
    for stage in stages:
        b, a = _coeffs(stage, fs)
        out = lfilter(b, a, out)
    return out
