#!/usr/bin/env python3
"""Compare two vulnix JSON reports and fail on newly introduced CVEs.

Gate 4 of docs/update-policy.md: an update must not introduce a new high or
critical CVE. `scripts/cve-scan.sh` runs vulnix over every NixOS host's
derivation closure on the PR's base and on its head; this script compares
the two reports.

A finding is a (package name, CVE) pair, so a version bump that still carries
the same CVE is not new, and a CVE that moves to a package that did not have
it before is. A new finding fails when its CVSSv3 base score is at or above
the threshold (default 7.0: high and critical). A new finding with no score
yet (NVD often lags) is listed as a warning but does not fail, because the
gate cannot tell how severe it is. CVEs accepted in pins/vulnix-whitelist.toml
never reach this script: vulnix leaves them out of `affected_by`.

Usage: cve_diff.py BASE.json HEAD.json [--threshold 7.0] [--summary FILE]
Exit codes: 0 nothing new at or above the threshold, 1 something is, 2 bad input.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Finding:
    pname: str
    cve: str
    score: float | None
    versions: tuple[str, ...]


def load(path: Path) -> dict[tuple[str, str], Finding]:
    """Read a vulnix --json report into findings keyed by (pname, CVE)."""
    data = json.loads(path.read_text())
    if not isinstance(data, list):
        raise ValueError(f"{path}: expected a JSON list from vulnix --json")
    versions: dict[tuple[str, str], set[str]] = {}
    scores: dict[tuple[str, str], float | None] = {}
    for item in data:
        pname = item.get("pname") or item["name"]
        for cve in item.get("affected_by", []):
            key = (pname, cve)
            versions.setdefault(key, set()).add(item.get("version") or "")
            score = item.get("cvssv3_basescore", {}).get(cve)
            if score is not None:
                scores[key] = max(float(score), scores.get(key) or 0.0)
            else:
                scores.setdefault(key, None)
    return {
        key: Finding(key[0], key[1], scores[key], tuple(sorted(versions[key])))
        for key in versions
    }


def fmt_score(score: float | None) -> str:
    return "unscored" if score is None else f"{score:.1f}"


def table(findings: list[Finding]) -> list[str]:
    lines = ["| Package | Version | CVE | CVSSv3 |", "| --- | --- | --- | --- |"]
    for f in findings:
        lines.append(
            f"| {f.pname} | {', '.join(f.versions)} "
            f"| [{f.cve}](https://nvd.nist.gov/vuln/detail/{f.cve}) | {fmt_score(f.score)} |"
        )
    return lines


def order(f: Finding) -> tuple[float, str, str]:
    return (-(f.score if f.score is not None else -1.0), f.pname, f.cve)


def compare(
    base: dict[tuple[str, str], Finding],
    head: dict[tuple[str, str], Finding],
    threshold: float,
) -> tuple[list[Finding], list[Finding], list[Finding], list[Finding]]:
    """Return (failing, unscored, below threshold, fixed) findings."""
    new = [head[k] for k in head.keys() - base.keys()]
    failing = sorted((f for f in new if f.score is not None and f.score >= threshold), key=order)
    unscored = sorted((f for f in new if f.score is None), key=order)
    below = sorted((f for f in new if f.score is not None and f.score < threshold), key=order)
    fixed = sorted((base[k] for k in base.keys() - head.keys()), key=order)
    return failing, unscored, below, fixed


def summary(failing, unscored, below, fixed, threshold: float) -> str:
    out = ["## CVE scan (vulnix)", ""]
    if failing:
        out += [
            f"**{len(failing)} new CVE(s) scored {threshold:.1f} or higher.** "
            "Wait for a fixed version, or accept each one in "
            "`pins/vulnix-whitelist.toml` with a reason and an `until` date.",
            "",
            *table(failing),
            "",
        ]
    else:
        out += [f"No new CVE scored {threshold:.1f} or higher.", ""]
    if unscored:
        out += ["### New, not yet scored by NVD (not failing)", "", *table(unscored), ""]
    if below:
        out += [f"### New, scored below {threshold:.1f} (not failing)", "", *table(below), ""]
    if fixed:
        out += [f"### Fixed by this change ({len(fixed)})", "", *table(fixed), ""]
    return "\n".join(out)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("base", type=Path)
    ap.add_argument("head", type=Path)
    ap.add_argument("--threshold", type=float, default=7.0)
    ap.add_argument("--summary", type=Path, help="append the Markdown report here")
    args = ap.parse_args(argv)
    try:
        base, head = load(args.base), load(args.head)
    except (OSError, ValueError, KeyError, TypeError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    failing, unscored, below, fixed = compare(base, head, args.threshold)
    report = summary(failing, unscored, below, fixed, args.threshold)
    print(report)
    if args.summary:
        with args.summary.open("a") as fh:
            fh.write(report + "\n")
    return 1 if failing else 0


if __name__ == "__main__":
    sys.exit(main())
