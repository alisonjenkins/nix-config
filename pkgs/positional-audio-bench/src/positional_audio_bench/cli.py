from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

from . import nixconfig, scoring
from .sofa import load_sofa

logger = logging.getLogger(__name__)


def _add_config_args(p: argparse.ArgumentParser) -> None:
    group = p.add_mutually_exclusive_group(required=True)
    group.add_argument("--config-json", type=Path, help='JSON file: {"angles": {...}, "compensationEq": [...]}')
    group.add_argument("--host", type=str, help="Evaluate a flake nixosConfiguration's live binauralSurround config")
    p.add_argument("--hrir", type=Path, required=True, help="Path to a SOFA HRIR file")
    p.add_argument("--flake-ref", type=str, default=".", help="Flake reference for --host (default: .)")


def _load_config(args: argparse.Namespace) -> tuple[dict[str, float], list]:
    if args.config_json is not None:
        return nixconfig.load_binaural_config(args.config_json)
    return nixconfig.load_binaural_config_from_host(args.host, args.flake_ref)


def _print_report(result: scoring.SweepResult, dataset_label: str) -> None:
    print(f"Dataset: {dataset_label}")
    print(f"{'Azimuth':>7} {'Elev':>6} {'ITD err (deg)':>13} {'ILD low/high (dB)':>19}")
    for p in result.points:
        print(
            f"{p.azimuth_deg:7.0f} {p.elevation_deg:6.0f} {p.itd_error_deg:13.1f} "
            f"{p.ild_low_db:8.1f} / {p.ild_high_db:6.1f}"
        )
    print(
        f"\nAggregate: mean ITD err {result.mean_itd_error_deg:.1f} deg, "
        f"max {result.max_itd_error_deg:.1f} deg @ "
        f"{result.max_itd_error_at[0]:.0f} az / {result.max_itd_error_at[1]:.0f} el"
    )
    print(f"Front-back discrimination: {result.frontback_score_db:.1f} dB")


def cmd_tune(args: argparse.Namespace) -> int:
    _, eq_stages = _load_config(args)
    hrir = load_sofa(args.hrir)
    result = scoring.run_sweep(hrir, eq_stages)
    _print_report(result, args.hrir.name)
    return 0


def cmd_regress(args: argparse.Namespace) -> int:
    _, eq_stages = _load_config(args)
    hrir = load_sofa(args.hrir)
    result = scoring.run_sweep(hrir, eq_stages)
    _print_report(result, args.hrir.name)

    if args.report is not None:
        args.report.write_text(
            json.dumps(
                {
                    "mean_itd_error_deg": result.mean_itd_error_deg,
                    "max_itd_error_deg": result.max_itd_error_deg,
                    "max_itd_error_at": result.max_itd_error_at,
                    "frontback_score_db": result.frontback_score_db,
                }
            )
        )

    failures = []
    if result.max_itd_error_deg > args.max_itd_error_deg:
        failures.append(
            f"max ITD error {result.max_itd_error_deg:.1f} deg exceeds threshold {args.max_itd_error_deg}"
        )
    if result.frontback_score_db < args.min_frontback_score:
        failures.append(
            f"front-back score {result.frontback_score_db:.1f} dB below threshold {args.min_frontback_score}"
        )

    if failures:
        for f in failures:
            print(f"REGRESSION: {f}", file=sys.stderr)
        return 1
    return 0


def cmd_sweep_datasets(args: argparse.Namespace) -> int:
    _, eq_stages = _load_config(args)
    rows = []
    for label, hrir_path in args.dataset:
        hrir = load_sofa(Path(hrir_path))
        result = scoring.run_sweep(hrir, eq_stages)
        rows.append((label, result))

    print(f"{'Dataset':<20} {'Mean ITD err':>13} {'Max ITD err':>12} {'Front-back':>11}")
    for label, result in rows:
        print(
            f"{label:<20} {result.mean_itd_error_deg:13.1f} {result.max_itd_error_deg:12.1f} "
            f"{result.frontback_score_db:11.1f}"
        )
    return 0


def cmd_live_verify(args: argparse.Namespace) -> int:
    from . import live

    angles, _ = _load_config(args)
    result = live.run_live_verify(
        sink_name=args.sink_name,
        output_monitor=args.output_monitor,
        angles=angles,
    )
    _print_report(result, f"live capture ({args.sink_name})")
    return 0


def _dataset_arg(value: str) -> tuple[str, str]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("expected LABEL=PATH")
    label, path = value.split("=", 1)
    return label, path


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="positional-audio-bench")
    sub = parser.add_subparsers(dest="command", required=True)

    tune = sub.add_parser("tune", help="Score one dataset/config, print the per-angle report")
    _add_config_args(tune)
    tune.set_defaults(func=cmd_tune)

    regress = sub.add_parser("regress", help="Score one dataset/config, exit non-zero on threshold violation")
    _add_config_args(regress)
    regress.add_argument("--max-itd-error-deg", type=float, required=True)
    regress.add_argument("--min-frontback-score", type=float, required=True)
    regress.add_argument("--report", type=Path, default=None, help="Write scores as JSON to this path")
    regress.set_defaults(func=cmd_regress)

    sweep = sub.add_parser("sweep-datasets", help="Score the same config against several HRIR datasets, ranked")
    group = sweep.add_mutually_exclusive_group(required=True)
    group.add_argument("--config-json", type=Path)
    group.add_argument("--host", type=str)
    sweep.add_argument("--flake-ref", type=str, default=".")
    sweep.add_argument("--dataset", action="append", type=_dataset_arg, required=True, metavar="LABEL=PATH")
    sweep.set_defaults(func=cmd_sweep_datasets)

    live_verify = sub.add_parser(
        "live-verify",
        help="Drive the real PipeWire binaural chain and score its captured output (manual/local only, not for CI)",
    )
    group = live_verify.add_mutually_exclusive_group(required=True)
    group.add_argument("--config-json", type=Path)
    group.add_argument("--host", type=str)
    live_verify.add_argument("--flake-ref", type=str, default=".")
    live_verify.add_argument("--sink-name", type=str, default="effect_input.binaural71")
    live_verify.add_argument("--output-monitor", type=str, required=True, help="Monitor port name to record from")
    live_verify.set_defaults(func=cmd_live_verify)

    return parser


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
