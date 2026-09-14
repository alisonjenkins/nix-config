import pytest
from positional_audio_bench.subject_match import D_PARAM_NAMES, Subject, load_subjects, match


def _subjects():
    return [
        Subject(id=1, d={"fossa_height": 1.0, "pinna_height": 6.0, "pinna_width": 3.0}),
        Subject(id=2, d={"fossa_height": 1.5, "pinna_height": 6.5, "pinna_width": 3.2}),
        Subject(id=3, d={"fossa_height": 2.0, "pinna_height": 7.0, "pinna_width": 3.5}),
        Subject(id=4, d={"fossa_height": None, "pinna_height": 6.4, "pinna_width": 3.1}),
    ]


def test_match_picks_closest_subject():
    results = match({"fossa_height": 1.05, "pinna_height": 6.1, "pinna_width": 3.05}, subjects=_subjects(), top_n=1)
    assert results[0].subject_id == 1


def test_match_excludes_subjects_missing_a_requested_param():
    results = match({"fossa_height": 1.5, "pinna_height": 6.5, "pinna_width": 3.2}, subjects=_subjects(), top_n=10)
    assert all(r.subject_id != 4 for r in results)


def test_match_top_n_limits_results():
    results = match({"pinna_height": 6.5}, subjects=_subjects(), top_n=2)
    assert len(results) == 2


def test_match_zero_distance_for_exact_population_mean():
    subjects = _subjects()[:3]
    results = match({"pinna_height": 6.5}, subjects=subjects, top_n=1)
    # subject 2's pinna_height (6.5) is exactly the population mean of [6.0, 6.5, 7.0]
    assert results[0].subject_id == 2
    assert results[0].distance == pytest.approx(0.0, abs=1e-9)


def test_match_rejects_unknown_parameter():
    with pytest.raises(ValueError):
        match({"not_a_real_param": 1.0}, subjects=_subjects())


def test_match_rejects_empty_measurements():
    with pytest.raises(ValueError):
        match({}, subjects=_subjects())


def test_load_subjects_returns_hutubs_population():
    subjects = load_subjects()
    assert len(subjects) == 96
    assert all(set(s.d.keys()) == set(D_PARAM_NAMES) for s in subjects)
    # At least the majority should have usable fossa/pinna height/width data.
    usable = [s for s in subjects if all(s.d[p] is not None for p in ("fossa_height", "pinna_height", "pinna_width"))]
    assert len(usable) >= 80


def test_load_subjects_matches_against_real_population():
    subjects = load_subjects()
    results = match({"fossa_height": 1.5, "pinna_height": 6.4, "pinna_width": 2.9}, subjects=subjects, top_n=3)
    assert len(results) == 3
    assert results[0].distance <= results[1].distance <= results[2].distance
