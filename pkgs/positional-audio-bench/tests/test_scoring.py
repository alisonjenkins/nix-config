from typing import Sequence

import numpy as np
from positional_audio_bench import localization, scoring
from positional_audio_bench.sofa import HRIRSet

FS = 48000.0
TAPS = 256


def _ideal_woodworth_hrir(azimuths_deg: Sequence[float]) -> HRIRSet:
    """A synthetic HRIR set with no ILD or spectral coloration, just a pure
    delay matching the Woodworth model exactly — an integration sanity check
    that `run_sweep` recovers ~0 ITD error when the "measured" HRIR is built
    from the same ground-truth model it's scored against.
    """
    positions = np.array([[az, 0.0, 1.0] for az in azimuths_deg])
    ir_left = np.zeros((len(azimuths_deg), TAPS))
    ir_right = np.zeros((len(azimuths_deg), TAPS))
    center_tap = TAPS // 2

    for i, az in enumerate(azimuths_deg):
        itd = localization.woodworth_itd_seconds(az)
        delay_samples = itd * FS
        # Positive ITD means right lags: delay the right ear's impulse.
        left_tap = center_tap
        right_tap = center_tap + delay_samples
        ir_left[i, int(round(left_tap))] = 1.0
        ir_right[i, int(round(right_tap))] = 1.0

    return HRIRSet(positions=positions, ir_left=ir_left, ir_right=ir_right, sample_rate=FS)


def test_run_sweep_recovers_near_zero_itd_error_for_ideal_hrir():
    azimuths = list(range(0, 360, 30))
    hrir = _ideal_woodworth_hrir(azimuths)

    result = scoring.run_sweep(hrir, eq_stages=[], azimuths_deg=tuple(azimuths), elevations_deg=(0.0,))

    assert result.mean_itd_error_deg < 3.0
    assert result.max_itd_error_deg < 10.0


def test_run_sweep_with_eq_stage_still_completes():
    from positional_audio_bench.biquad import BiquadStage

    azimuths = list(range(0, 360, 45))
    hrir = _ideal_woodworth_hrir(azimuths)
    eq = [BiquadStage(type="bq_peaking", freq=2500.0, q=1.0, gain=-6.0)]

    result = scoring.run_sweep(hrir, eq_stages=eq, azimuths_deg=tuple(azimuths), elevations_deg=(0.0,))

    assert len(result.points) == len(azimuths)
    assert result.mean_itd_error_deg < 5.0


def test_run_sweep_frontback_score_is_none_for_degenerate_grid():
    # 90/270 are the interaural poles: their mirror (180 - az) lands back on
    # az itself, so there are no non-degenerate mirror pairs in this grid.
    azimuths = (90, 270)
    hrir = _ideal_woodworth_hrir(azimuths)

    result = scoring.run_sweep(hrir, eq_stages=[], azimuths_deg=azimuths, elevations_deg=(0.0,))

    assert result.frontback_score_db is None
