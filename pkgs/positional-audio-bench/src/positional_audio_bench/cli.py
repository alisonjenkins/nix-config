from __future__ import annotations

import argparse
import dataclasses
import json
import logging
import sys
from pathlib import Path

from . import nixconfig, scoring
from .biquad import BiquadStage
from .sofa import load_sofa

logger = logging.getLogger(__name__)


def _add_config_args(p: argparse.ArgumentParser) -> None:
    group = p.add_mutually_exclusive_group(required=True)
    group.add_argument("--config-json", type=Path, help='JSON file: {"angles": {...}, "compensationEq": [...]}')
    group.add_argument("--host", type=str, help="Evaluate a flake nixosConfiguration's live binauralSurround config")
    p.add_argument("--hrir", type=Path, required=True, help="Path to a SOFA HRIR file")
    p.add_argument("--flake-ref", type=str, default=".", help="Flake reference for --host (default: .)")


def _load_config(args: argparse.Namespace) -> tuple[dict[str, float], list[BiquadStage]]:
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
    frontback = "N/A (not measured by live-verify)" if result.frontback_score_db is None else f"{result.frontback_score_db:.1f} dB"
    print(f"Front-back discrimination: {frontback}")


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
    if result.frontback_score_db is None:
        failures.append("front-back score undefined for this azimuth sweep (no non-degenerate mirror pairs)")
    elif result.frontback_score_db < args.min_frontback_score:
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
        frontback = "N/A" if result.frontback_score_db is None else f"{result.frontback_score_db:.1f}"
        print(f"{label:<20} {result.mean_itd_error_deg:13.1f} {result.max_itd_error_deg:12.1f} {frontback:>11}")
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


def cmd_perceptual_test(args: argparse.Namespace) -> int:
    from . import perceptual

    _, eq_stages = _load_config(args)
    hrir = load_sofa(args.hrir)
    result = perceptual.run_perceptual_test(hrir, eq_stages, num_trials=args.trials, seed=args.seed)

    print(f"\nExact-bucket accuracy: {result.exact_bucket_accuracy * 100:.0f}%")
    print(f"Mean direction error: {result.mean_bucket_error_deg:.0f} deg")
    print(f"Front-back confusion rate: {result.front_back_confusion_rate * 100:.0f}%")

    if args.report is not None:
        args.report.write_text(
            json.dumps(
                {
                    "exact_bucket_accuracy": result.exact_bucket_accuracy,
                    "mean_bucket_error_deg": result.mean_bucket_error_deg,
                    "front_back_confusion_rate": result.front_back_confusion_rate,
                    "trials": [dataclasses.asdict(t) for t in result.trials],
                }
            )
        )
    return 0


def cmd_match_subject(args: argparse.Namespace) -> int:
    from . import subject_match

    measurements = {
        "fossa_height": args.fossa_height,
        "pinna_height": args.pinna_height,
        "pinna_width": args.pinna_width,
    }
    for name, value in args.measure:
        measurements[name] = value
    measurements = {k: v for k, v in measurements.items() if v is not None}

    results = subject_match.match(measurements, top_n=args.top_n)

    print(f"Matched on: {', '.join(measurements)}")
    print(f"{'HUTUBS subject':>15} {'Distance':>10}")
    for r in results:
        print(f"{r.subject_id:>15} {r.distance:>10.3f}")

    if results:
        winner = results[0].subject_id
        print(
            f"\nFetch the winner's SOFA file with, e.g.:\n"
            f"  nix store prefetch-file https://sofacoustics.org/data/database/hutubs/pp{winner}_HRIRs_measured.sofa\n"
            f"then score it: positional-audio-bench sweep-datasets --dataset hutubs-{winner}=<fetched-path> ...\n"
            f"This only checks data quality, not whether it actually localizes better for you — "
            f"that needs a real listening test (see the `perceptual-test` command)."
        )
    return 0


def _measure_arg(value: str) -> tuple[str, float]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("expected NAME=VALUE, e.g. cavum_concha_height=1.9")
    name, raw_value = value.split("=", 1)
    try:
        return name, float(raw_value)
    except ValueError as e:
        raise argparse.ArgumentTypeError(f"expected a number for {name!r}, got {raw_value!r}") from e


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

    perceptual_test = sub.add_parser(
        "perceptual-test",
        help="Blind forced-choice localization test through headphones (manual/local only, not for CI)",
    )
    _add_config_args(perceptual_test)
    perceptual_test.add_argument("--trials", type=int, default=20)
    perceptual_test.add_argument("--seed", type=int, default=None, help="Fix the trial order for a repeatable run")
    perceptual_test.add_argument("--report", type=Path, default=None, help="Write per-trial results as JSON")
    perceptual_test.set_defaults(func=cmd_perceptual_test)

    match_subject = sub.add_parser(
        "match-subject",
        help="Find the closest-matching real human ear in HUTUBS to your own pinna measurements",
    )
    match_subject.add_argument("--fossa-height", type=float, help="cm — see docs for how to measure")
    match_subject.add_argument("--pinna-height", type=float, help="cm")
    match_subject.add_argument("--pinna-width", type=float, help="cm")
    match_subject.add_argument(
        "--measure",
        action="append",
        type=_measure_arg,
        default=[],
        metavar="NAME=VALUE",
        help="Additional HUTUBS parameter (cavum_concha_height, cymba_concha_height, cavum_concha_width, "
        "intertragal_incisure, cavum_concha_depth_down, cavum_concha_depth_back, crus_of_helix_depth) — "
        "only worth providing if you have calipers, not just a ruler",
    )
    match_subject.add_argument("--top-n", type=int, default=3)
    match_subject.set_defaults(func=cmd_match_subject)

    return parser


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except ValueError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
