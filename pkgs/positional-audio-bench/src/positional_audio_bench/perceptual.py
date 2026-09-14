"""A blind forced-choice localization test — the actual way to tell whether
a candidate HRIR (a personalized match, an alternate dataset, whatever)
localizes better for a specific listener.

`scoring.run_sweep`'s ITD/front-back metrics score a HRIR's cues against an
idealized spherical-head model and against its own mirror-direction
distinctiveness. Neither of those is "does this match the listener's own
ears" — a well-matched personal HRTF can legitimately score *worse* there
while sounding better, because the listener's brain is listening for cues
shaped like their own pinna, not for maximally distinct cues in the
abstract. This is the only part of the tool that asks a human.

Manual/local only, like `live.py` — needs a real listener and headphones,
not something `nix flake check` can run.
"""

from __future__ import annotations

import dataclasses
import random
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf

from .biquad import BiquadStage
from .scoring import binauralize, make_test_burst
from .sofa import HRIRSet

# 45-degree compass buckets, matching the granularity a listener can
# reliably report without a numeric protractor.
COMPASS_BUCKETS = ("F", "FR", "R", "BR", "B", "BL", "L", "FL")
BUCKET_AZIMUTH_DEG = {"F": 0, "FL": 45, "L": 90, "BL": 135, "B": 180, "BR": 225, "R": 270, "FR": 315}
FRONT_BUCKETS = {"F", "FR", "FL"}
BACK_BUCKETS = {"B", "BR", "BL"}


def nearest_bucket(azimuth_deg: float) -> str:
    az = azimuth_deg % 360.0
    return min(COMPASS_BUCKETS, key=lambda b: min(abs(BUCKET_AZIMUTH_DEG[b] - az), 360 - abs(BUCKET_AZIMUTH_DEG[b] - az)))


def bucket_distance_deg(a: str, b: str) -> float:
    diff = abs(BUCKET_AZIMUTH_DEG[a] - BUCKET_AZIMUTH_DEG[b])
    return min(diff, 360 - diff)


@dataclasses.dataclass(frozen=True)
class Trial:
    true_azimuth_deg: float
    true_bucket: str
    guessed_bucket: str


@dataclasses.dataclass(frozen=True)
class PerceptualResult:
    trials: list[Trial]

    @property
    def exact_bucket_accuracy(self) -> float:
        return sum(1 for t in self.trials if t.guessed_bucket == t.true_bucket) / len(self.trials)

    @property
    def mean_bucket_error_deg(self) -> float:
        return sum(bucket_distance_deg(t.true_bucket, t.guessed_bucket) for t in self.trials) / len(self.trials)

    @property
    def front_back_confusion_rate(self) -> float:
        scored = [
            t
            for t in self.trials
            if t.true_bucket in FRONT_BUCKETS | BACK_BUCKETS and t.guessed_bucket in FRONT_BUCKETS | BACK_BUCKETS
        ]
        if not scored:
            return 0.0
        confused = sum(
            1
            for t in scored
            if (t.true_bucket in FRONT_BUCKETS) != (t.guessed_bucket in FRONT_BUCKETS)
        )
        return confused / len(scored)


def run_perceptual_test(
    hrir: HRIRSet,
    eq_stages: list[BiquadStage],
    num_trials: int,
    seed: int | None = None,
) -> PerceptualResult:
    rng = random.Random(seed)
    burst = make_test_burst(fs=hrir.sample_rate)
    trials: list[Trial] = []

    with tempfile.TemporaryDirectory(prefix="positional-audio-bench-perceptual-") as tmp:
        tmp_path = Path(tmp)
        order = list(range(num_trials))
        rng.shuffle(order)  # playback order independent of trial index, so it can't be inferred

        azimuths = [rng.choice(COMPASS_BUCKETS) for _ in range(num_trials)]
        true_azimuths_deg = [float(BUCKET_AZIMUTH_DEG[b]) for b in azimuths]

        print(f"{num_trials} trials. For each sound, answer with the compass code that matches where it seemed to")
        print(f"come from: {', '.join(COMPASS_BUCKETS)} (F=front, B=back, L=left, R=right, FL=front-left, etc).")
        print("Put your headphones on now.\n")

        for playback_index, trial_num in enumerate(order):
            azimuth_deg = true_azimuths_deg[trial_num]
            left, right = binauralize(hrir, azimuth_deg, 0.0, burst, eq_stages)
            stereo = np.column_stack([left, right])
            # HRIR convolution isn't gain-normalized; without this a loud
            # peak could land straight in the listener's ears at full scale.
            peak = np.max(np.abs(stereo)) + 1e-9
            stereo = stereo / peak * 0.5

            trial_file = tmp_path / f"trial_{playback_index}.wav"
            sf.write(trial_file, stereo, int(hrir.sample_rate))

            subprocess.run(["pw-cat", "--playback", str(trial_file)], check=True, timeout=10)

            guess = ""
            while guess not in COMPASS_BUCKETS:
                guess = input(f"[{playback_index + 1}/{num_trials}] direction? ").strip().upper()

            trials.append(
                Trial(true_azimuth_deg=azimuth_deg, true_bucket=azimuths[trial_num], guessed_bucket=guess)
            )

    return PerceptualResult(trials=trials)
