"""Measurement report, CSV parsing and the go / no-go / inconclusive verdict.

Field names follow specs/005-vr-foveated-rendering-injector/data-model.md
("Measurement report" and "Verdict").
"""

import csv
import datetime
import io
import math
import statistics
from dataclasses import dataclass
from typing import Any, Dict, List, Mapping, Optional, Sequence, Tuple

from . import stats

BUILDS = ("stock", "patched-off", "patched-on")
CONDITIONS = ("off", "on")
ARTEFACTS = ("tolerable", "not-tolerable", "unknown")
META_KEYS = ("game", "appId", "gameBuild", "driver", "gpu", "undervoltMv", "headsetOrDisplay")
FRAMES_HEADER = ["frame", "gpu_ms", "eye_pass_ms", "unix_s"]
SAMPLER_HEADER = ["time_s", "power_w", "core_mhz", "gpu_busy_percent", "temp_c", "unix_s"]

# Spread at or above this share of the off median means the runs were too
# noisy to call a null result a real "no gain" (spec 005 data-model, Verdict).
NOISY_SHARE = 0.05

# A log may start or stop this close to the window edge. One frame is about
# 11 ms at 90 Hz and one sample 50 ms, so a second absorbs shutdown jitter
# without hiding a run that stopped early.
WINDOW_EDGE_TOLERANCE_S = 1.0  # the 5 % rule


class InputError(ValueError):
    """Bad input file; the message starts with `<file>:<line>`."""


@dataclass(frozen=True)
class Frame:
    frame: int
    gpu_ms: float
    eye_pass_ms: float
    unix_s: float


@dataclass(frozen=True)
class PowerSample:
    time_s: float
    power_w: float
    core_mhz: float
    gpu_busy_percent: float
    temp_c: Optional[float]
    unix_s: float


@dataclass(frozen=True)
class Window:
    skip_seconds: float
    window_seconds: float
    window_start_unix_s: float
    window_end_unix_s: float

    def to_json(self) -> Dict[str, float]:
        return {
            "skipSeconds": self.skip_seconds,
            "windowSeconds": self.window_seconds,
            "windowStartUnixS": self.window_start_unix_s,
            "windowEndUnixS": self.window_end_unix_s,
        }


def _rows(text: str, source: str, header: Sequence[str]):
    reader = csv.reader(io.StringIO(text))
    try:
        first = next(reader)
    except StopIteration:
        raise InputError(f"{source}:1: empty file, expected header {','.join(header)}")
    if first != list(header):
        raise InputError(
            f"{source}:1: header is {','.join(first)!r}, expected {','.join(header)!r}")
    for row in reader:
        if not row:
            continue
        yield reader.line_num, row


def _number(raw: str, source: str, line: int, field: str) -> float:
    try:
        value = float(raw)
    except ValueError:
        raise InputError(f"{source}:{line}: {field} is not a number: {raw!r}")
    if not math.isfinite(value) or value < 0:
        raise InputError(f"{source}:{line}: {field} must be finite and not negative: {raw!r}")
    return value


def parse_frames_csv(text: str, source: str) -> List[Frame]:
    out = []
    for line, row in _rows(text, source, FRAMES_HEADER):
        if len(row) != len(FRAMES_HEADER):
            raise InputError(
                f"{source}:{line}: expected {len(FRAMES_HEADER)} fields, got {len(row)}")
        out.append(Frame(
            int(_number(row[0], source, line, "frame")),
            _number(row[1], source, line, "gpu_ms"),
            _number(row[2], source, line, "eye_pass_ms"),
            _number(row[3], source, line, "unix_s")))
    if not out:
        raise InputError(f"{source}: no frame rows after the header")
    return out


def parse_sampler_csv(text: str, source: str) -> List[PowerSample]:
    out = []
    for line, row in _rows(text, source, SAMPLER_HEADER):
        if len(row) != len(SAMPLER_HEADER):
            raise InputError(
                f"{source}:{line}: expected {len(SAMPLER_HEADER)} fields, got {len(row)}")
        temp = row[4].strip()
        out.append(PowerSample(
            _number(row[0], source, line, "time_s"),
            _number(row[1], source, line, "power_w"),
            _number(row[2], source, line, "core_mhz"),
            _number(row[3], source, line, "gpu_busy_percent"),
            _number(temp, source, line, "temp_c") if temp else None,
            _number(row[5], source, line, "unix_s")))
    if not out:
        raise InputError(f"{source}: no sampler rows after the header")
    return out


def trim_to_window(frames: Sequence[Frame], samples: Optional[Sequence[PowerSample]],
                   skip_s: float, window_s: Optional[float], run_label: str = "run"
                   ) -> Tuple[List[Frame], Optional[List[PowerSample]], Window]:
    """Keep the frames and samples whose `unix_s` lies in the measured window.

    The window starts at the first frame's `unix_s` plus `skip_s` and ends
    `window_s` later, or at the last frame when `window_s` is None. Both ends
    are inclusive. `frames` must not be empty.
    """
    if not math.isfinite(skip_s) or skip_s < 0:
        raise ValueError(f"skip_s must be finite and not negative, got {skip_s!r}")
    if window_s is not None and (not math.isfinite(window_s) or window_s <= 0):
        raise ValueError(f"window_s must be finite and positive, got {window_s!r}")
    if not frames:
        raise ValueError(f"{run_label}: no frames to trim")
    start = frames[0].unix_s + skip_s
    end = frames[-1].unix_s if window_s is None else start + window_s
    kept_frames = [f for f in frames if start <= f.unix_s <= end]
    if not kept_frames:
        raise InputError(
            f"{run_label}: no frames left after trimming to the window "
            f"[{start}, {end}] (frame log spans {frames[0].unix_s} to {frames[-1].unix_s})")
    if frames[-1].unix_s < end - WINDOW_EDGE_TOLERANCE_S:
        raise InputError(
            f"{run_label}: the frame log ends at {frames[-1].unix_s}, but the window runs to "
            f"{end}; the run stopped early")
    window = Window(skip_s, end - start, start, end)
    if samples is None:
        return kept_frames, None, window
    first, last = min(s.unix_s for s in samples), max(s.unix_s for s in samples)
    if last < start or first > end:
        raise InputError(
            f"{run_label}: sampler samples ({first} to {last}) do not overlap the "
            f"frame window [{start}, {end}]; were the two logs recorded together?")
    kept_samples = [s for s in samples if start <= s.unix_s <= end]
    if len(kept_samples) < 2:
        raise InputError(
            f"{run_label}: fewer than 2 sampler samples inside the window [{start}, {end}], "
            f"got {len(kept_samples)}")
    if first > start + WINDOW_EDGE_TOLERANCE_S:
        raise InputError(
            f"{run_label}: the sampler starts at {first}, after the window start {start}; "
            "the mean power would miss the start of the window")
    if last < end - WINDOW_EDGE_TOLERANCE_S:
        raise InputError(
            f"{run_label}: the sampler ends at {last}, before the window end {end}; "
            "the mean power would miss the end of the window")
    return kept_frames, kept_samples, window


def build_run(frames: Sequence[Frame], samples: Optional[Sequence[PowerSample]],
              run_label: str, skip_s: float = 0.0,
              window_s: Optional[float] = None) -> Dict[str, Any]:
    if not frames:
        raise stats.InvalidSample(f"{run_label}: no frames")
    frames, samples, window = trim_to_window(frames, samples, skip_s, window_s, run_label)
    gpu = [f.gpu_ms for f in frames]
    eye = [f.eye_pass_ms for f in frames]
    run: Dict[str, Any] = {
        "frames": len(frames),
        "medianGpuMs": stats.run_median(gpu, f"{run_label} gpu_ms"),
        "p99GpuMs": stats.run_p99(gpu, f"{run_label} gpu_ms"),
        "medianEyePassMs": stats.run_median(eye, f"{run_label} eye_pass_ms"),
        "meanPowerW": None,
        "meanCoreMhz": None,
        "startTempC": None,
        "endTempC": None,
        "window": window.to_json(),
    }
    if samples:
        run["meanPowerW"] = stats.mean_power(
            [(s.time_s, s.power_w) for s in samples], f"{run_label} power")
        run["meanCoreMhz"] = statistics.fmean(s.core_mhz for s in samples)
        temps = [s.temp_c for s in samples if s.temp_c is not None]
        if temps:
            run["startTempC"] = temps[0]
            run["endTempC"] = temps[-1]
    return run


def _utc_iso(now: datetime.datetime) -> str:
    if now.tzinfo is None:
        raise ValueError("date must be timezone-aware (UTC)")
    return now.astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _metric(runs: Sequence[Mapping[str, Any]], key: str) -> Optional[List[float]]:
    values = [r[key] for r in runs]
    return None if any(v is None for v in values) else values


def build_measurement_report(meta: Mapping[str, Any], condition: str, build: str,
                             runs: Sequence[Mapping[str, Any]],
                             now: datetime.datetime) -> Dict[str, Any]:
    if condition not in CONDITIONS:
        raise ValueError(f"condition {condition!r} is not one of {CONDITIONS}")
    if build not in BUILDS:
        raise ValueError(f"build {build!r} is not one of {BUILDS}")
    missing = [k for k in META_KEYS if k not in meta]
    if missing:
        raise ValueError(f"meta is missing: {', '.join(missing)}")
    medians = _metric(runs, "medianGpuMs")
    eye_medians = _metric(runs, "medianEyePassMs")
    if medians is None or eye_medians is None:
        raise ValueError(f"{condition}: a run has no median GPU or eye-pass time")
    median_gpu = statistics.median(medians)
    if median_gpu <= 0:
        raise stats.InvalidSample(
            f"{condition}: median GPU frame time is {median_gpu!r}, cannot compute eyePassShare")
    power = _metric(runs, "meanPowerW")
    out: Dict[str, Any] = {k: meta[k] for k in META_KEYS}
    out.update({
        "build": build,
        "condition": condition,
        "runs": [dict(r) for r in runs],
        "noise": {
            "medianGpuMs": stats.noise(medians, f"{condition} medians"),
            "meanPowerW": stats.noise(power, f"{condition} power") if power else None,
        },
        "eyePassShare": statistics.median(eye_medians) / median_gpu,
        "date": _utc_iso(now),
    })
    return out


def decide_verdict(off_runs: Sequence[Mapping[str, Any]], on_runs: Sequence[Mapping[str, Any]],
                   artefacts: str) -> Dict[str, Any]:
    """Apply the data-model verdict rule to two conditions' runs.

    A metric is compared only if every run in both conditions has it. A
    "reduction" is a beyond-noise drop; `go` needs one in either metric.
    A null result is `no-go` only when every compared metric's spread is
    below 5 % of its off median; otherwise the runs were too noisy to tell.
    """
    if artefacts not in ARTEFACTS:
        raise ValueError(f"artefacts {artefacts!r} is not one of {ARTEFACTS}")
    gains = {"medianGpuMs": stats.gain_beyond_noise(
        _require(off_runs, "medianGpuMs"), _require(on_runs, "medianGpuMs"), "median GPU ms")}
    off_power, on_power = _metric(off_runs, "meanPowerW"), _metric(on_runs, "meanPowerW")
    if off_power is not None and on_power is not None:
        gains["meanPowerW"] = stats.gain_beyond_noise(off_power, on_power, "mean power W")

    def change(key: str) -> Optional[float]:
        return gains[key].relative_change if key in gains else None

    base = {
        "gpuTimeChange": change("medianGpuMs"),
        "powerChange": change("meanPowerW"),
        "noise": {
            key: ({"off": gains[key].noise_off, "on": gains[key].noise_on}
                  if key in gains else None)
            for key in ("medianGpuMs", "meanPowerW")
        },
        "artefacts": artefacts,
    }
    reductions = [k for k, g in gains.items() if g.beyond_noise and g.diff < 0]
    increases = [k for k, g in gains.items() if g.beyond_noise and g.diff > 0]
    noisy = [k for k, g in gains.items()
             if max(g.noise_off, g.noise_on) / g.median_off >= NOISY_SHARE]

    if artefacts == "not-tolerable":
        verdict, reason = "no-go", "artefacts not tolerable"
    elif reductions and artefacts == "tolerable":
        verdict, reason = "go", f"beyond-noise reduction in {', '.join(reductions)}; artefacts tolerable"
    elif reductions:
        verdict, reason = "inconclusive", "artefacts not judged"
    elif increases:
        verdict, reason = "no-go", f"no reduction; {', '.join(increases)} rose beyond noise"
    elif noisy:
        verdict, reason = "inconclusive", (
            f"no beyond-noise change and noise is {NOISY_SHARE:.0%} or more of the off median "
            f"in {', '.join(noisy)}")
    else:
        verdict, reason = "no-go", "no beyond-noise reduction and noise below 5% of the off median"
    return dict(base, verdict=verdict, reason=reason)


def _require(runs: Sequence[Mapping[str, Any]], key: str) -> List[float]:
    values = _metric(runs, key)
    if values is None:
        raise ValueError(f"a run has no {key}")
    return values


def build_report(meta: Mapping[str, Any], off_runs: Sequence[Mapping[str, Any]],
                 on_runs: Sequence[Mapping[str, Any]], artefacts: str,
                 now: datetime.datetime) -> Dict[str, Any]:
    off_build = meta.get("offBuild", "patched-off")
    on_build = meta.get("onBuild", "patched-on")
    verdict = decide_verdict(off_runs, on_runs, artefacts)
    reports = [
        build_measurement_report(meta, "off", off_build, off_runs, now),
        build_measurement_report(meta, "on", on_build, on_runs, now),
    ]
    verdict_row = {
        "game": meta["game"], "date": _utc_iso(now), "driver": meta["driver"],
    }
    verdict_row.update(verdict)
    return {"reports": reports, "verdict": verdict_row}
