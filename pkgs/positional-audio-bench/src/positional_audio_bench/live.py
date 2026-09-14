"""Drive the real, running PipeWire binaural chain and score its captured
output — not a `nix flake check` concern (needs a live session and real
hardware), invoked manually via `just audio-bench-live`.

Per channel (FL/FR/FC/...): write an N-channel WAV with the test burst on
only that channel, play it into the 7.1 sink with `pw-cat --playback`, and
concurrently capture the binauralised stereo output from the chain's output
monitor with `pw-cat --record`. Score the capture the same way the offline
path scores a SOFA convolution, using the channel's configured azimuth as
ground truth — so live and offline numbers are directly comparable.
"""

from __future__ import annotations

import logging
import subprocess
import tempfile
import time
from pathlib import Path

import numpy as np
import soundfile as sf

from . import localization, scoring

logger = logging.getLogger(__name__)

CHANNEL_ORDER = ("FL", "FR", "FC", "LFE", "RL", "RR", "SL", "SR")
CAPTURE_HEADROOM_SECONDS = 0.5


def _make_channel_wav(path: Path, channel_index: int, num_channels: int, fs: float) -> float:
    burst = scoring.make_test_burst(fs=fs)
    frames = np.zeros((burst.shape[0], num_channels), dtype=np.float32)
    frames[:, channel_index] = burst.astype(np.float32)
    sf.write(path, frames, int(fs))
    return burst.shape[0] / fs


def _play_and_capture(playback_file: Path, capture_file: Path, sink_name: str, output_monitor: str, duration_s: float) -> None:
    capture_duration = duration_s + CAPTURE_HEADROOM_SECONDS
    record_proc = subprocess.Popen(
        [
            "pw-cat",
            "--record",
            "--target",
            output_monitor,
            "--channels",
            "2",
            str(capture_file),
        ]
    )
    try:
        time.sleep(0.2)  # let the recorder attach before playback starts
        subprocess.run(
            ["pw-cat", "--playback", "--target", sink_name, str(playback_file)],
            check=True,
            timeout=duration_s + 5,
        )
        time.sleep(capture_duration - duration_s)
    finally:
        # A bad sink/monitor name fails the playback subprocess.run and
        # raises before reaching here — without this, the record_proc would
        # leak and keep holding the monitor port for every run after it.
        record_proc.terminate()
        record_proc.wait(timeout=5)


def run_live_verify(
    sink_name: str,
    output_monitor: str,
    angles: dict[str, float],
) -> scoring.SweepResult:
    fs = scoring.SAMPLE_RATE_HZ
    num_channels = len(CHANNEL_ORDER)
    points = []

    with tempfile.TemporaryDirectory(prefix="positional-audio-bench-live-") as tmp:
        tmp_path = Path(tmp)
        for channel in CHANNEL_ORDER:
            if channel not in angles or channel == "LFE":
                continue
            channel_index = CHANNEL_ORDER.index(channel)
            azimuth_deg = angles[channel]

            playback_file = tmp_path / f"{channel}-play.wav"
            capture_file = tmp_path / f"{channel}-capture.wav"
            duration_s = _make_channel_wav(playback_file, channel_index, num_channels, fs)

            logger.info("channel %s (azimuth %.0f deg): playing + capturing", channel, azimuth_deg)
            _play_and_capture(playback_file, capture_file, sink_name, output_monitor, duration_s)

            captured, capture_fs = sf.read(capture_file, dtype="float64", always_2d=True)
            left, right = captured[:, 0], captured[:, 1]

            max_tau = 1.2 * localization.max_woodworth_itd_seconds()
            measured_itd = localization.gcc_phat(left, right, capture_fs, max_tau=max_tau)
            itd_error = localization.itd_angular_error_deg(measured_itd, azimuth_deg)
            ild_low = localization.band_rms_db_ratio(left, right, capture_fs, *scoring.ILD_LOW_BAND_HZ)
            ild_high = localization.band_rms_db_ratio(left, right, capture_fs, *scoring.ILD_HIGH_BAND_HZ)

            points.append(
                scoring.AnglePoint(
                    azimuth_deg=azimuth_deg,
                    elevation_deg=0.0,
                    itd_error_deg=itd_error,
                    ild_low_db=ild_low,
                    ild_high_db=ild_high,
                )
            )

    errors = [p.itd_error_deg for p in points]
    max_idx = int(np.argmax(errors)) if errors else 0
    return scoring.SweepResult(
        points=points,
        frontback_score_db=0.0,  # front/back mirror channels aren't guaranteed to exist in a speaker layout
        mean_itd_error_deg=float(np.mean(errors)) if errors else 0.0,
        max_itd_error_deg=float(errors[max_idx]) if errors else 0.0,
        max_itd_error_at=(points[max_idx].azimuth_deg, points[max_idx].elevation_deg) if points else (0.0, 0.0),
    )
