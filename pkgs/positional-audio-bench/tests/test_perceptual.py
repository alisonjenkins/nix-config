import pytest
from positional_audio_bench.perceptual import (
    PerceptualResult,
    Trial,
    bucket_distance_deg,
    nearest_bucket,
)


def test_nearest_bucket_exact_matches():
    assert nearest_bucket(0) == "F"
    assert nearest_bucket(90) == "L"
    assert nearest_bucket(180) == "B"
    assert nearest_bucket(270) == "R"


def test_nearest_bucket_rounds_to_closest():
    assert nearest_bucket(20) == "F"
    assert nearest_bucket(40) == "FL"
    assert nearest_bucket(359) == "F"


def test_bucket_distance_adjacent_is_45():
    assert bucket_distance_deg("F", "FL") == 45
    assert bucket_distance_deg("F", "FR") == 45


def test_bucket_distance_opposite_is_180():
    assert bucket_distance_deg("F", "B") == 180


def test_bucket_distance_wraps_around():
    assert bucket_distance_deg("FR", "FL") == 90  # via F, not the long way via B


def test_exact_bucket_accuracy_all_correct():
    trials = [Trial(0.0, "F", "F"), Trial(90.0, "L", "L")]
    result = PerceptualResult(trials=trials)
    assert result.exact_bucket_accuracy == 1.0


def test_exact_bucket_accuracy_all_wrong():
    trials = [Trial(0.0, "F", "B"), Trial(90.0, "L", "R")]
    result = PerceptualResult(trials=trials)
    assert result.exact_bucket_accuracy == 0.0


def test_mean_bucket_error_deg():
    trials = [Trial(0.0, "F", "FL"), Trial(0.0, "F", "F")]  # 45 deg off, then 0
    result = PerceptualResult(trials=trials)
    assert result.mean_bucket_error_deg == pytest.approx(22.5)


def test_front_back_confusion_rate_counts_only_confusions():
    trials = [
        Trial(0.0, "F", "B"),  # front guessed as back: confused
        Trial(180.0, "B", "F"),  # back guessed as front: confused
        Trial(0.0, "F", "FL"),  # still front-half: not confused
        Trial(180.0, "B", "BR"),  # still back-half: not confused
    ]
    result = PerceptualResult(trials=trials)
    assert result.front_back_confusion_rate == pytest.approx(0.5)


def test_front_back_confusion_rate_excludes_pure_left_right():
    trials = [Trial(90.0, "L", "R"), Trial(90.0, "L", "L")]
    result = PerceptualResult(trials=trials)
    assert result.front_back_confusion_rate == 0.0


def test_front_back_confusion_rate_zero_for_no_scoreable_trials():
    trials = [Trial(90.0, "L", "R")]
    result = PerceptualResult(trials=trials)
    assert result.front_back_confusion_rate == 0.0
