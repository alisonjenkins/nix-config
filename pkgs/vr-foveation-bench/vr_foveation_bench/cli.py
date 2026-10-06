"""Command line: `vr-foveation-bench` `sample`, `report` and `verdict`.

Exit status: 0 done, 1 bad input (message on stderr), 2 too few runs.
Logs and diagnostics go to stderr; stdout carries only the summary.
"""

import argparse
import datetime
import json
import logging
import math
import os
import signal
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence

from . import report, sampler, stats, verdicts

EXIT_OK = 0
EXIT_BAD_INPUT = 1
EXIT_TOO_FEW_RUNS = 2

log = logging.getLogger("vr_foveation_bench")


class _Parser(argparse.ArgumentParser):
    """argparse exits 2 on usage errors, which here means "too few runs"."""

    def error(self, message: str):
        self.print_usage(sys.stderr)
        self.exit(EXIT_BAD_INPUT, f"{self.prog}: error: {message}\n")


def _hex_int(raw: str) -> int:
    try:
        return int(raw, 16)
    except ValueError:
        raise argparse.ArgumentTypeError(f"not a hexadecimal PCI device id: {raw!r}")


def _seconds(raw: str, allow_zero: bool) -> float:
    try:
        value = float(raw)
    except ValueError:
        raise argparse.ArgumentTypeError(f"not a number: {raw!r}")
    if not math.isfinite(value) or value < 0 or (value == 0 and not allow_zero):
        bound = "0 or more" if allow_zero else "above 0"
        raise argparse.ArgumentTypeError(f"must be a finite number of seconds {bound}: {raw!r}")
    return value


def _skip_seconds(raw: str) -> float:
    return _seconds(raw, allow_zero=True)


def _window_seconds(raw: str) -> float:
    return _seconds(raw, allow_zero=False)


def build_parser() -> argparse.ArgumentParser:
    parser = _Parser(prog="vr-foveation-bench",
                     description="Measure GPU time and power for the VR foveation benchmark.")
    sub = parser.add_subparsers(dest="command", required=True, parser_class=_Parser)

    s = sub.add_parser("sample", help="sample the discrete GPU's sensors to a CSV file")
    s.add_argument("--out", required=True, help="CSV file to write")
    s.add_argument("--interval", type=float, default=sampler.DEFAULT_INTERVAL_S,
                   help="seconds between samples (default %(default)s)")
    s.add_argument("--duration", type=float, default=None,
                   help="stop after this many seconds (default: until SIGINT/SIGTERM)")
    s.add_argument("--pci-device", type=_hex_int, default=sampler.DEFAULT_PCI_DEVICE,
                   help="PCI device id of the GPU to sample (default 0x%(default)04x)")
    s.add_argument("--sysfs-root", default=sampler.DEFAULT_SYSFS_ROOT,
                   help="sysfs root (default %(default)s)")

    r = sub.add_parser("report", help="compare off and on runs and write a report")
    r.add_argument("--meta", required=True, help="JSON file with game, appId, gameBuild, driver, "
                   "gpu, undervoltMv, headsetOrDisplay (optional offBuild, onBuild)")
    r.add_argument("--off", nargs="+", required=True, metavar="FRAMES.csv")
    r.add_argument("--on", nargs="+", required=True, metavar="FRAMES.csv")
    r.add_argument("--off-power", nargs="+", default=[], metavar="SAMPLER.csv")
    r.add_argument("--on-power", nargs="+", default=[], metavar="SAMPLER.csv")
    r.add_argument("--artefacts", required=True, choices=report.ARTEFACTS)
    r.add_argument("--skip-seconds", type=_skip_seconds, default=0.0, metavar="S",
                   help="drop this long after the first frame of each run (default %(default)s)")
    r.add_argument("--window-seconds", type=_window_seconds, default=None, metavar="W",
                   help="measure this long after the skip (default: to the end of the frame log)")
    r.add_argument("--out", default="report.json", help="report file (default %(default)s)")
    r.add_argument("--force", action="store_true", help="overwrite --out if it exists")

    v = sub.add_parser("verdict", help="add or replace a game's row in the verdicts table")
    v.add_argument("--report", required=True, help="report JSON written by `report`")
    v.add_argument("--verdicts", required=True, help="Markdown verdicts file (created if absent)")
    v.add_argument("--artefact-notes", required=True, metavar="TEXT",
                   help="the owner's note on visual artefacts")
    return parser


def _read_text(path: str) -> str:
    try:
        return Path(path).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise report.InputError(f"{path}: cannot read: {exc}") from exc


def _load_meta(path: str) -> Dict[str, Any]:
    try:
        meta = json.loads(_read_text(path))
    except json.JSONDecodeError as exc:
        raise report.InputError(f"{path}:{exc.lineno}: invalid JSON: {exc.msg}") from exc
    if not isinstance(meta, dict):
        raise report.InputError(f"{path}: expected a JSON object")
    missing = [k for k in report.META_KEYS if k not in meta]
    if missing:
        raise report.InputError(f"{path}: missing keys: {', '.join(missing)}")
    return meta


def _load_runs(label: str, frame_files: Sequence[str], power_files: Sequence[str],
               skip_s: float, window_s: Optional[float]) -> List[Dict[str, Any]]:
    if power_files and len(power_files) != len(frame_files):
        raise report.InputError(
            f"--{label}-power has {len(power_files)} file(s) but --{label} has "
            f"{len(frame_files)}; give one sampler file per run")
    runs = []
    for i, path in enumerate(frame_files):
        frames = report.parse_frames_csv(_read_text(path), path)
        samples = None
        if power_files:
            samples = report.parse_sampler_csv(_read_text(power_files[i]), power_files[i])
        try:
            runs.append(report.build_run(frames, samples, f"{label} run {i} ({path})",
                                         skip_s, window_s))
        except stats.InvalidSample as exc:
            raise report.InputError(str(exc)) from exc
    return runs


def _summary(out: Dict[str, Any]) -> str:
    lines = []
    for rep in out["reports"]:
        medians = ", ".join(f"{r['medianGpuMs']:.3f}" for r in rep["runs"])
        lines.append(f"{rep['condition']} ({rep['build']}): {len(rep['runs'])} runs, "
                     f"median GPU ms per run: {medians}")
        windows = "; ".join(
            f"{r['window']['windowStartUnixS']:.3f}-{r['window']['windowEndUnixS']:.3f} "
            f"(skip {r['window']['skipSeconds']:g} s, {r['window']['windowSeconds']:.3f} s, "
            f"{r['frames']} frames)" for r in rep["runs"])
        lines.append(f"  window per run (unix s): {windows}")
        power_noise = rep["noise"]["meanPowerW"]
        power_text = "" if power_noise is None else f", {power_noise:.2f} W"
        lines.append(f"  noise (spread of medians): {rep['noise']['medianGpuMs']:.3f} ms"
                     f"{power_text}; eye-pass share {rep['eyePassShare']:.1%}")
    v = out["verdict"]
    lines.append(f"GPU time change: {_pct(v['gpuTimeChange'])}, power change: {_pct(v['powerChange'])}")
    lines.append(f"verdict: {v['verdict']} ({v['reason']})")
    return "\n".join(lines)


def _pct(value: Optional[float]) -> str:
    return "n/a" if value is None else f"{value:+.1%}"


def _cmd_report(args: argparse.Namespace, now: datetime.datetime) -> int:
    if not args.force and Path(args.out).exists():
        raise report.InputError(f"{args.out}: already exists; pass --force to overwrite it")
    meta = _load_meta(args.meta)
    off_runs = _load_runs("off", args.off, args.off_power, args.skip_seconds, args.window_seconds)
    on_runs = _load_runs("on", args.on, args.on_power, args.skip_seconds, args.window_seconds)
    out = report.build_report(meta, off_runs, on_runs, args.artefacts, now)
    # "x" closes the race between the check above and the write.
    with open(args.out, "w" if args.force else "x", encoding="utf-8") as handle:
        handle.write(json.dumps(out, indent=2) + "\n")
    log.info("event=report_written path=%s verdict=%s off_runs=%d on_runs=%d",
             args.out, out["verdict"]["verdict"], len(off_runs), len(on_runs))
    print(_summary(out))
    return EXIT_OK


def _default_file_mode() -> int:
    """The mode a plain file write gets: 0666 minus the process umask."""
    umask = os.umask(0)
    os.umask(umask)
    return 0o666 & ~umask


def _write_atomic(path: Path, text: str) -> None:
    """Replace `path` through a temporary file in the same directory.

    The verdicts file holds every game's record, so a crash mid-write must not
    truncate it; the rename is all-or-nothing. The mode of an existing file is kept.
    """
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        mode = path.stat().st_mode & 0o777 if path.exists() else _default_file_mode()
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def _cmd_verdict(args: argparse.Namespace) -> int:
    try:
        data = json.loads(_read_text(args.report))
    except json.JSONDecodeError as exc:
        raise report.InputError(f"{args.report}:{exc.lineno}: invalid JSON: {exc.msg}") from exc
    if not isinstance(data, dict):
        raise report.InputError(f"{args.report}: expected a JSON object")
    path = Path(args.verdicts)
    if not path.parent.is_dir():
        raise report.InputError(f"{path.parent}: directory does not exist; create it first")
    row = verdicts.row_from_report(data, args.artefact_notes)
    current = _read_text(args.verdicts) if path.exists() else ""
    _write_atomic(path, verdicts.upsert(current, row))
    log.info("event=verdict_written path=%s game=%s driver=%s verdict=%s",
             args.verdicts, row["game"], row["driver"], row["verdict"])
    print(verdicts.render_table([row]).splitlines()[-1])
    return EXIT_OK


def _cmd_sample(args: argparse.Namespace) -> int:
    paths = sampler.find_gpu(args.sysfs_root, args.pci_device)
    stop = {"now": False}

    def request_stop(signum, _frame):
        stop["now"] = True

    old = {s: signal.signal(s, request_stop) for s in (signal.SIGINT, signal.SIGTERM)}
    try:
        rows = sampler.sample_to_file(paths, args.out, args.interval, args.duration,
                                      time.monotonic, time.time, time.sleep,
                                      lambda: stop["now"])
    finally:
        for s, handler in old.items():
            signal.signal(s, handler)
    log.info("event=sample_written path=%s rows=%d", args.out, rows)
    return EXIT_OK


def main(argv: Optional[Sequence[str]] = None,
         now: Optional[datetime.datetime] = None) -> int:
    logging.basicConfig(level=logging.INFO, stream=sys.stderr, force=True,
                        format="%(asctime)s %(levelname)s %(message)s",
                        datefmt="%Y-%m-%dT%H:%M:%SZ")
    logging.Formatter.converter = time.gmtime
    try:
        args = build_parser().parse_args(argv)
    except SystemExit as exc:
        return exc.code if isinstance(exc.code, int) else EXIT_OK
    try:
        if args.command == "sample":
            return _cmd_sample(args)
        if args.command == "verdict":
            return _cmd_verdict(args)
        return _cmd_report(args, now or datetime.datetime.now(datetime.timezone.utc))
    except stats.TooFewRuns as exc:
        print(f"vr-foveation-bench: too few runs: {exc}", file=sys.stderr)
        return EXIT_TOO_FEW_RUNS
    except (report.InputError, stats.InvalidSample, stats.UnequalRunCounts, ValueError,
            sampler.SensorError, sampler.GpuNotFound, OSError) as exc:
        print(f"vr-foveation-bench: {exc}", file=sys.stderr)
        return EXIT_BAD_INPUT


if __name__ == "__main__":
    sys.exit(main())
