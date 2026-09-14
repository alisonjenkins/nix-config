import numpy as np
import pytest
from positional_audio_bench import localization

FS = 48000.0


def test_fold_to_front_hemisphere():
    assert localization.fold_to_front_hemisphere(0) == pytest.approx(0)
    assert localization.fold_to_front_hemisphere(30) == pytest.approx(30)
    assert localization.fold_to_front_hemisphere(90) == pytest.approx(90)
    assert localization.fold_to_front_hemisphere(150) == pytest.approx(30)
    assert localization.fold_to_front_hemisphere(180) == pytest.approx(0)
    assert localization.fold_to_front_hemisphere(330) == pytest.approx(30)  # mirrors 30 on the right


@pytest.mark.parametrize("azimuth", [0, 15, 30, 45, 60, 90, 120, 150, 180, 210, 270, 330])
def test_woodworth_itd_to_lateral_angle_round_trips(azimuth):
    itd = localization.woodworth_itd_seconds(azimuth)
    recovered = localization.itd_to_lateral_angle_deg(itd)
    expected = localization.fold_to_front_hemisphere(azimuth)
    assert recovered == pytest.approx(expected, abs=1e-6)


def test_itd_angular_error_is_zero_for_exact_woodworth_itd():
    for azimuth in (10, 45, 80, 100, 170):
        itd = localization.woodworth_itd_seconds(azimuth)
        error = localization.itd_angular_error_deg(itd, azimuth)
        assert error == pytest.approx(0.0, abs=1e-6)


def test_woodworth_itd_sign_matches_left_right_convention():
    # Azimuth 45 (left) should have the right ear lagging: positive ITD.
    assert localization.woodworth_itd_seconds(45) > 0
    # Azimuth 315 == -45 (right) should have the left ear lagging: negative ITD.
    assert localization.woodworth_itd_seconds(315) < 0
    # Straight ahead: no lag.
    assert localization.woodworth_itd_seconds(0) == pytest.approx(0.0, abs=1e-12)


def _make_delayed_pair(delay_samples: float, n: int = 4096, seed: int = 0) -> tuple[np.ndarray, np.ndarray]:
    rng = np.random.default_rng(seed)
    base = rng.standard_normal(n + 64)
    left = base[32 : 32 + n]
    # Fractional delay via a windowed sinc-free approach: use FFT phase shift for cleanliness.
    spectrum = np.fft.rfft(base)
    freqs = np.fft.rfftfreq(base.shape[0], d=1.0)
    shifted = np.fft.irfft(spectrum * np.exp(-2j * np.pi * freqs * delay_samples), n=base.shape[0])
    right = shifted[32 : 32 + n]
    return left, right


def test_gcc_phat_recovers_known_integer_delay():
    left, right = _make_delayed_pair(delay_samples=10)
    itd = localization.gcc_phat(left, right, fs=FS)
    assert itd == pytest.approx(10 / FS, abs=1 / FS)


def test_gcc_phat_recovers_known_fractional_delay():
    left, right = _make_delayed_pair(delay_samples=7.3)
    itd = localization.gcc_phat(left, right, fs=FS)
    assert itd == pytest.approx(7.3 / FS, abs=0.5 / FS)


def test_gcc_phat_negative_delay():
    left, right = _make_delayed_pair(delay_samples=-5.0)
    itd = localization.gcc_phat(left, right, fs=FS)
    assert itd == pytest.approx(-5.0 / FS, abs=0.5 / FS)


def _sine(freq: float, seconds: float, fs: float) -> np.ndarray:
    t = np.arange(int(fs * seconds)) / fs
    return np.sin(2 * np.pi * freq * t)


def test_band_rms_db_ratio_matches_known_gain():
    signal = _sine(1000.0, 0.2, FS)
    left = signal
    right = signal * 0.5  # -6.02 dB relative to left
    ratio = localization.band_rms_db_ratio(left, right, FS, 500.0, 2000.0)
    assert ratio == pytest.approx(20 * np.log10(2.0), abs=0.2)


def test_band_rms_db_ratio_zero_for_identical_signals():
    signal = _sine(1000.0, 0.2, FS)
    ratio = localization.band_rms_db_ratio(signal, signal, FS, 500.0, 2000.0)
    assert ratio == pytest.approx(0.0, abs=1e-6)


def test_log_spectral_distance_zero_for_identical_signals():
    signal = _sine(5000.0, 0.1, FS)
    distance = localization.log_spectral_distance_db(signal, signal, FS, 4000.0, 6000.0)
    assert distance == pytest.approx(0.0, abs=1e-6)


def test_log_spectral_distance_nonzero_for_different_signals():
    a = _sine(5000.0, 0.1, FS)
    b = _sine(5500.0, 0.1, FS)
    distance = localization.log_spectral_distance_db(a, b, FS, 4000.0, 6000.0)
    assert distance > 1.0
