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
are left out of `affected_by` by vulnix while they are in date.

With --whitelist, an entry whose `until` date has passed also fails the scan
for every head finding it used to cover, even one the base already had: once
an accepted CVE has merged it is in both reports, so the comparison alone
would let it outlive its expiry.

`--check-whitelist FILE` validates the accepted-CVE file and exits: every
entry must name one exact package (no `*`), list its CVEs, carry a comment,
and have an `until` date at most 90 days after today. cve-scan.sh runs it
before scanning, because vulnix itself accepts entries that silence every
CVE of a package forever.

Usage: cve_diff.py BASE.json HEAD.json [--threshold 7.0] [--summary FILE]
                   [--whitelist FILE] [--today YYYY-MM-DD]
       cve_diff.py --check-whitelist FILE [--today YYYY-MM-DD]
Exit codes: 0 nothing new at or above the threshold, 1 something is, 2 bad input.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
import tomllib
from dataclasses import dataclass
from pathlib import Path

MAX_EXCEPTION_DAYS = 90
PACKAGE_NAME = re.compile(r"^[A-Za-z0-9_.+-]+$")


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


def read_whitelist(path: Path) -> dict[str, dict]:
    data = tomllib.loads(path.read_text())
    if not all(isinstance(v, dict) for v in data.values()):
        raise ValueError(f"{path}: every entry must be a [\"package\"] table")
    return data


def as_date(value) -> dt.date | None:
    if isinstance(value, dt.date):
        return value
    if isinstance(value, str):
        return dt.date.fromisoformat(value)
    return None


def check_whitelist(path: Path, today: dt.date) -> list[str]:
    """Return one error per entry that breaks the accepted-CVE rules."""
    errors = []
    for name, entry in read_whitelist(path).items():
        where = f"{path}: [\"{name}\"]"
        if "*" in name or not PACKAGE_NAME.match(name):
            errors.append(f"{where}: must name one exact package, not a pattern")
        cves = entry.get("cve")
        if isinstance(cves, str):
            cves = [cves]
        if not cves or not all(isinstance(c, str) and c.startswith("CVE-") for c in cves):
            errors.append(f"{where}: needs a non-empty cve list")
        comment = entry.get("comment")
        if isinstance(comment, list):
            comment = " ".join(str(c) for c in comment)
        if not isinstance(comment, str) or not comment.strip():
            errors.append(f"{where}: needs a comment saying why it is safe here")
        try:
            until = as_date(entry.get("until"))
        except ValueError:
            until = None
        if until is None:
            errors.append(f"{where}: needs an until date (YYYY-MM-DD)")
        elif until > today + dt.timedelta(days=MAX_EXCEPTION_DAYS):
            errors.append(f"{where}: until {until} is more than {MAX_EXCEPTION_DAYS} days away")
    return errors


def expired(path: Path, head: dict[tuple[str, str], Finding], today: dt.date) -> list[Finding]:
    """Head findings covered by a whitelist entry whose until date has passed."""
    out = []
    for name, entry in read_whitelist(path).items():
        try:
            until = as_date(entry.get("until"))
        except ValueError:
            continue
        if until is None or until > today:
            continue
        cves = entry.get("cve") or []
        cves = {cves} if isinstance(cves, str) else set(cves)
        for (pname, cve), finding in head.items():
            if cve in cves and (name == pname or name.startswith(pname + "-")):
                out.append(finding)
    return out


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


def summary(failing, unscored, below, fixed, threshold: float, lapsed=()) -> str:
    out = ["## CVE scan (vulnix)", ""]
    if lapsed:
        out += [
            f"**{len(lapsed)} accepted CVE(s) whose exception in "
            "`pins/vulnix-whitelist.toml` has expired.** Fix them, or renew the "
            "exception with a new reason and `until` date.",
            "",
            *table(lapsed),
            "",
        ]
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
    ap.add_argument("base", type=Path, nargs="?")
    ap.add_argument("head", type=Path, nargs="?")
    ap.add_argument("--threshold", type=float, default=7.0)
    ap.add_argument("--summary", type=Path, help="append the Markdown report here")
    ap.add_argument("--whitelist", type=Path, help="fail findings of expired exceptions")
    ap.add_argument("--check-whitelist", type=Path, help="validate this file and exit")
    ap.add_argument("--today", type=dt.date.fromisoformat, default=dt.date.today())
    args = ap.parse_args(argv)

    if args.check_whitelist:
        try:
            errors = check_whitelist(args.check_whitelist, args.today)
        except (OSError, ValueError, tomllib.TOMLDecodeError) as e:
            print(f"error: {e}", file=sys.stderr)
            return 2
        for e in errors:
            print(f"error: {e}", file=sys.stderr)
        return 2 if errors else 0

    if not (args.base and args.head):
        ap.error("BASE.json and HEAD.json are required")
    try:
        base, head = load(args.base), load(args.head)
        lapsed = expired(args.whitelist, head, args.today) if args.whitelist else []
    except (OSError, ValueError, KeyError, TypeError, tomllib.TOMLDecodeError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    lapsed = sorted(
        (f for f in lapsed if f.score is None or f.score >= args.threshold), key=order
    )
    failing, unscored, below, fixed = compare(base, head, args.threshold)
    report = summary(failing, unscored, below, fixed, args.threshold, lapsed)
    print(report)
    if args.summary:
        with args.summary.open("a") as fh:
            fh.write(report + "\n")
    return 1 if failing or lapsed else 0


if __name__ == "__main__":
    sys.exit(main())
