from positional_audio_bench.biquad import BiquadStage, frequency_response_db

FS = 48000.0


def test_peaking_gain_at_center_freq_matches_configured_gain():
    stage = BiquadStage(type="bq_peaking", freq=2500.0, q=1.0, gain=6.0)
    response = frequency_response_db(stage, freq_hz=2500.0, fs=FS)
    assert abs(response - 6.0) < 0.1


def test_peaking_cut_at_center_freq_matches_configured_gain():
    stage = BiquadStage(type="bq_peaking", freq=1000.0, q=2.0, gain=-9.0)
    response = frequency_response_db(stage, freq_hz=1000.0, fs=FS)
    assert abs(response - (-9.0)) < 0.1


def test_peaking_far_from_center_freq_is_near_unity():
    stage = BiquadStage(type="bq_peaking", freq=2500.0, q=1.0, gain=10.0)
    response = frequency_response_db(stage, freq_hz=50.0, fs=FS)
    assert abs(response) < 1.0


def test_lowshelf_boosts_below_corner_and_flattens_above():
    stage = BiquadStage(type="bq_lowshelf", freq=200.0, q=0.707, gain=6.0)
    low = frequency_response_db(stage, freq_hz=20.0, fs=FS)
    high = frequency_response_db(stage, freq_hz=10000.0, fs=FS)
    assert abs(low - 6.0) < 0.5
    assert abs(high) < 0.5


def test_highshelf_boosts_above_corner_and_flattens_below():
    stage = BiquadStage(type="bq_highshelf", freq=5000.0, q=0.707, gain=8.0)
    high = frequency_response_db(stage, freq_hz=20000.0, fs=FS)
    low = frequency_response_db(stage, freq_hz=50.0, fs=FS)
    assert abs(high - 8.0) < 0.5
    assert abs(low) < 0.5


def test_zero_gain_peaking_is_unity_everywhere():
    stage = BiquadStage(type="bq_peaking", freq=1000.0, q=1.0, gain=0.0)
    for freq in (50.0, 1000.0, 10000.0):
        assert abs(frequency_response_db(stage, freq_hz=freq, fs=FS)) < 1e-6
