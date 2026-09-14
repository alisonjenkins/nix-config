"""Nearest-neighbour matching of a listener's own pinna measurements against
the HUTUBS anthropometry database (96 real human subjects), to find a real
ear closer to theirs than a generic dummy-head HRTF.

This does NOT validate whether the matched subject's HRTF localizes better
for the listener — `scoring.run_sweep`'s ITD/front-back metrics score cue
strength and fit to an idealized spherical head, not fit to a specific
listener's own pinna, so a genuinely well-matched personal HRTF could score
*lower* there while still sounding better by ear. The sweep score is only a
data-quality sanity check on the matched subject's file. The real answer is
a perceptual test — see `perceptual.py`.

Restricted to three parameters — fossa height (d4), pinna height (d5), pinna
width (d6) — because they're large enough (population SD ~0.3-0.5cm) to
measure with a ruler against an ear photo without the noise swamping the
signal. The other seven CIPIC/HUTUBS pinna parameters (cavum concha
height/width/depth, cymba concha height, intertragal incisure, crus of helix
depth, and the two rotation/flare angles) have population SDs down around
1-2mm — comparable to or smaller than home-measurement error, so including
them would add noise, not information.
"""

from __future__ import annotations

import dataclasses
import importlib.resources
import json
import math

D_PARAM_NAMES = (
    "cavum_concha_height",
    "cymba_concha_height",
    "cavum_concha_width",
    "fossa_height",
    "pinna_height",
    "pinna_width",
    "intertragal_incisure",
    "cavum_concha_depth_down",
    "cavum_concha_depth_back",
    "crus_of_helix_depth",
)

DEFAULT_MATCH_PARAMS = ("fossa_height", "pinna_height", "pinna_width")


@dataclasses.dataclass(frozen=True)
class Subject:
    id: int
    d: dict[str, float | None]  # name -> mean of left/right, or None if either side missing


def load_subjects() -> list[Subject]:
    raw = importlib.resources.files("positional_audio_bench.data").joinpath("hutubs_anthropometry.json").read_text()
    rows = json.loads(raw)

    subjects = []
    for row in rows:
        d = {}
        for i, name in enumerate(D_PARAM_NAMES):
            left, right = row["d_left"][i], row["d_right"][i]
            if left is None and right is None:
                d[name] = None
            elif left is None:
                d[name] = right
            elif right is None:
                d[name] = left
            else:
                d[name] = (left + right) / 2
        subjects.append(Subject(id=row["id"], d=d))
    return subjects


def _population_stats(subjects: list[Subject], param: str) -> tuple[float, float]:
    values: list[float] = [d for s in subjects if (d := s.d[param]) is not None]
    mean = sum(values) / len(values)
    variance = sum((v - mean) ** 2 for v in values) / len(values)
    return mean, math.sqrt(variance)


@dataclasses.dataclass(frozen=True)
class MatchResult:
    subject_id: int
    distance: float


def match(
    measurements: dict[str, float],
    subjects: list[Subject] | None = None,
    top_n: int = 3,
) -> list[MatchResult]:
    """Rank subjects by z-scored Euclidean distance over whichever
    `measurements` keys (from `D_PARAM_NAMES`) are provided. Subjects missing
    any of the provided parameters are skipped, not penalized — there's no
    principled way to impute a pinna measurement from population statistics
    alone.
    """
    if not measurements:
        raise ValueError("at least one measurement is required")
    unknown = set(measurements) - set(D_PARAM_NAMES)
    if unknown:
        raise ValueError(f"unknown parameter(s): {sorted(unknown)}")

    all_subjects = subjects if subjects is not None else load_subjects()
    stats = {name: _population_stats(all_subjects, name) for name in measurements}

    results = []
    for subject in all_subjects:
        if any(subject.d[name] is None for name in measurements):
            continue
        distance_sq = 0.0
        for name, target in measurements.items():
            mean, std = stats[name]
            value: float = subject.d[name]  # type: ignore[assignment]  # None already excluded above
            distance_sq += ((value - mean) / std - (target - mean) / std) ** 2
        results.append(MatchResult(subject_id=subject.id, distance=math.sqrt(distance_sq)))

    results.sort(key=lambda r: r.distance)
    return results[:top_n]
