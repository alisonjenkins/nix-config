#!/usr/bin/env python3
"""Compare two vulnix JSON reports and fail on newly introduced CVEs.

Gate 4 of docs/update-policy.md: an update must not introduce a new CVE that
is likely to hurt. `scripts/cve-scan.sh` runs vulnix over the derivation
closure of every NixOS host the PR changes, on the PR's base and on its head;
this script compares the two reports.

A finding is a (package name, CVE) pair, so a version bump that still carries
the same CVE is not new, and a CVE that moves to a package that did not have
it before is. A new finding fails when any of these hold:

- its CVSSv3 base score is at or above --threshold (default 7.0: high and
  critical);
- it is in CISA's Known Exploited Vulnerabilities catalog (KEV): someone is
  exploiting it now, whatever its score, and whether or not NVD has scored
  it yet;
- its EPSS score (FIRST's estimate of the chance it is exploited in the next
  30 days) is at or above --epss-threshold (default 0.1).

CVSS says how bad a CVE would be; KEV and EPSS say how likely it is to be
used. A new finding that passes all three is listed but does not fail. The
report orders findings by that likelihood: KEV first, then EPSS, then CVSS.

The KEV catalog and EPSS scores come from --fetch-intel (the network) or
--intel FILE (tests). When the fetch fails the gate falls back to CVSS alone
and says so at the top of the report, so an outage at CISA or FIRST cannot
block every update, and cannot pass one silently either.

CVEs accepted in pins/vulnix-whitelist.toml are left out of `affected_by` by
vulnix while they are in date. With --whitelist, an entry whose `until` date
has passed also fails the scan for every head finding it used to cover that
is unscored or would fail as new, even one the base already had: once an
accepted CVE has merged it is in both reports, so the comparison alone would
let it outlive its expiry.

With --head-closures DIR and --base-closures DIR (one file per host, named
after it, listing the store paths in that host's derivation closure), each
finding is attributed to the hosts that contain it, and the report opens
with a per-host count of what is new, fixed and still open.

`--check-whitelist FILE` validates the accepted-CVE file and exits: every
entry must name one exact package (no `*`), list its CVEs, carry a comment,
and have an `until` date at most 90 days after today. cve-scan.sh runs it
before scanning, because vulnix itself accepts entries that silence every
CVE of a package forever.

Usage: cve_diff.py BASE.json HEAD.json [--threshold 7.0] [--epss-threshold 0.1]
                   [--fetch-intel | --intel FILE] [--summary FILE]...
                   [--whitelist FILE] [--today YYYY-MM-DD]
                   [--head-closures DIR --base-closures DIR]
       cve_diff.py --check-whitelist FILE [--today YYYY-MM-DD]
Exit codes: 0 nothing new fails the gate, 1 something does, 2 bad input.
"""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import json
import re
import sys
import tomllib
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

MAX_EXCEPTION_DAYS = 90
PACKAGE_NAME = re.compile(r"^[A-Za-z0-9_.+-]+$")
CVE_ID = re.compile(r"^CVE-\d{4}-\d+$")
KEV_URL = "https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json"
EPSS_URL = "https://api.first.org/data/v1/epss"
EPSS_BATCH = 50
FETCH_TIMEOUT = 60

Key = tuple[str, str]


@dataclass(frozen=True)
class Finding:
    pname: str
    cve: str
    score: float | None
    versions: tuple[str, ...]
    drvs: tuple[str, ...] = ()
    hosts: tuple[str, ...] = ()


@dataclass
class Intel:
    """Exploitation data: the KEV catalog and EPSS scores by CVE."""

    kev: set[str] = field(default_factory=set)
    epss: dict[str, float] = field(default_factory=dict)
    error: str | None = None  # why the data is missing, when it is
    used: bool = False  # False: CVSS only, nothing was asked for


def load(path: Path) -> dict[Key, Finding]:
    """Read a vulnix --json report into findings keyed by (pname, CVE)."""
    data = json.loads(path.read_text())
    if not isinstance(data, list):
        raise ValueError(f"{path}: expected a JSON list from vulnix --json")
    versions: dict[Key, set[str]] = {}
    drvs: dict[Key, set[str]] = {}
    scores: dict[Key, float | None] = {}
    for item in data:
        pname = item.get("pname") or item["name"]
        for cve in item.get("affected_by", []):
            key = (pname, cve)
            versions.setdefault(key, set()).add(item.get("version") or "")
            drvs.setdefault(key, set())
            if item.get("derivation"):
                drvs[key].add(item["derivation"])
            score = (item.get("cvssv3_basescore") or {}).get(cve)
            if score is not None:
                scores[key] = max(float(score), scores.get(key) or 0.0)
            else:
                scores.setdefault(key, None)
    return {
        key: Finding(key[0], key[1], scores[key], tuple(sorted(versions[key])), tuple(sorted(drvs[key])))
        for key in versions
    }


def read_closures(directory: Path) -> dict[str, set[str]]:
    """One file per host, named after it, listing its closure's store paths."""
    if not directory.is_dir():
        raise ValueError(f"{directory}: not a directory")
    return {
        p.name: {line.strip() for line in p.read_text().splitlines() if line.strip()}
        for p in sorted(directory.iterdir())
        if p.is_file()
    }


def attribute(findings: dict[Key, Finding], closures: dict[str, set[str]]) -> dict[Key, Finding]:
    """Set each finding's hosts: those whose closure holds one of its derivations."""
    return {
        key: dataclasses.replace(
            f, hosts=tuple(h for h, paths in closures.items() if any(d in paths for d in f.drvs))
        )
        for key, f in findings.items()
    }


def _get_json(url: str):
    req = urllib.request.Request(url, headers={"User-Agent": "nix-config-cve-scan", "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=FETCH_TIMEOUT) as resp:  # noqa: S310 (fixed https URLs)
        return json.load(resp)


def fetch_intel(cves: set[str]) -> Intel:
    """Fetch the KEV catalog and the EPSS scores of these CVEs."""
    intel = Intel(used=True)
    try:
        catalog = _get_json(KEV_URL)
        intel.kev = {v["cveID"] for v in catalog["vulnerabilities"]}
        wanted = sorted(c for c in cves if CVE_ID.match(c))
        for i in range(0, len(wanted), EPSS_BATCH):
            batch = wanted[i:i + EPSS_BATCH]
            query = urllib.parse.urlencode({"cve": ",".join(batch), "limit": len(batch)})
            for row in _get_json(f"{EPSS_URL}?{query}")["data"]:
                intel.epss[row["cve"]] = float(row["epss"])
    except (OSError, ValueError, KeyError, TypeError) as e:
        return Intel(error=f"could not fetch KEV/EPSS data ({e})", used=True)
    return intel


def read_intel(path: Path) -> Intel:
    """Read {"kev": [CVE...], "epss": {CVE: probability}} from a file."""
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        raise ValueError(f"{path}: expected a JSON object with kev and epss")
    return Intel(
        kev=set(data.get("kev", [])),
        epss={k: float(v) for k, v in data.get("epss", {}).items()},
        error=data.get("error"),
        used=True,
    )


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


def expired(path: Path, head: dict[Key, Finding], today: dt.date) -> list[Finding]:
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


@dataclass(frozen=True)
class Gate:
    threshold: float
    epss_threshold: float
    intel: Intel

    def reasons(self, f: Finding) -> list[str]:
        """Why this finding fails the gate; empty when it does not."""
        out = []
        if f.cve in self.intel.kev:
            out.append("known exploited (CISA KEV)")
        epss = self.intel.epss.get(f.cve)
        if epss is not None and epss >= self.epss_threshold:
            out.append(f"EPSS {epss:.0%}")
        if f.score is not None and f.score >= self.threshold:
            out.append(f"CVSS {f.score:.1f}")
        return out

    def fails(self, f: Finding) -> bool:
        return bool(self.reasons(f))

    def order(self, f: Finding) -> tuple:
        """Most likely to be exploited first: KEV, then EPSS, then CVSS."""
        return (
            f.cve not in self.intel.kev,
            -self.intel.epss.get(f.cve, -1.0),
            -(f.score if f.score is not None else -1.0),
            f.pname,
            f.cve,
        )


@dataclass
class Result:
    failing: list[Finding]
    unscored: list[Finding]
    below: list[Finding]
    fixed: list[Finding]
    exploited_open: list[Finding]  # in KEV, already on the base, still on the head


def compare(base: dict[Key, Finding], head: dict[Key, Finding], gate: Gate) -> Result:
    new = [head[k] for k in head.keys() - base.keys()]
    passing = [f for f in new if not gate.fails(f)]
    return Result(
        failing=sorted((f for f in new if gate.fails(f)), key=gate.order),
        unscored=sorted((f for f in passing if f.score is None), key=gate.order),
        below=sorted((f for f in passing if f.score is not None), key=gate.order),
        fixed=sorted((base[k] for k in base.keys() - head.keys()), key=gate.order),
        exploited_open=sorted(
            (head[k] for k in head.keys() & base.keys() if k[1] in gate.intel.kev), key=gate.order
        ),
    )


def fmt_score(score: float | None) -> str:
    return "unscored" if score is None else f"{score:.1f}"


def fmt_hosts(hosts: tuple[str, ...], all_hosts: list[str]) -> str:
    if all_hosts and len(hosts) == len(all_hosts):
        return f"all {len(hosts)} scanned"
    return ", ".join(hosts) if hosts else "-"


def table(findings: list[Finding], gate: Gate, all_hosts: list[str]) -> list[str]:
    cols = ["Package", "Version", "CVE", "CVSSv3"]
    if gate.intel.used:
        cols += ["EPSS", "KEV"]
    if all_hosts:
        cols.append("Hosts")
    lines = ["| " + " | ".join(cols) + " |", "|" + " --- |" * len(cols)]
    for f in findings:
        row = [
            f.pname,
            ", ".join(f.versions),
            f"[{f.cve}](https://nvd.nist.gov/vuln/detail/{f.cve})",
            fmt_score(f.score),
        ]
        if gate.intel.used:
            epss = gate.intel.epss.get(f.cve)
            row += ["-" if epss is None else f"{epss:.1%}", "yes" if f.cve in gate.intel.kev else ""]
        if all_hosts:
            row.append(fmt_hosts(f.hosts, all_hosts))
        lines.append("| " + " | ".join(row) + " |")
    return lines


def host_table(base: dict[Key, Finding], head: dict[Key, Finding], all_hosts: list[str], gate: Gate) -> list[str]:
    """Per host: findings new, fixed and still open, compared on that host alone."""
    lines = [
        "| Host | New | New, failing | Fixed | Still open | Known exploited |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for host in all_hosts:
        on_head = {k for k, f in head.items() if host in f.hosts}
        on_base = {k for k, f in base.items() if host in f.hosts}
        new = on_head - on_base
        failing = sum(1 for k in new if gate.fails(head[k]))
        exploited = sum(1 for k in on_head if k[1] in gate.intel.kev)
        lines.append(
            f"| {host} | {len(new)} | {failing} | {len(on_base - on_head)} "
            f"| {len(on_head & on_base)} | {exploited} |"
        )
    return lines


def criteria(gate: Gate) -> str:
    if gate.intel.used and not gate.intel.error:
        return (
            f"CVSSv3 {gate.threshold:.1f}+, in CISA KEV, or EPSS "
            f"{gate.epss_threshold:.0%}+"
        )
    return f"CVSSv3 {gate.threshold:.1f}+"


def summary(res: Result, gate: Gate, base=None, head=None, all_hosts=(), lapsed=()) -> str:
    all_hosts = list(all_hosts)

    def tbl(findings):
        return table(findings, gate, all_hosts)

    out = ["## CVE scan (vulnix)", ""]
    if gate.intel.error:
        out += [
            f"> [!WARNING]\n> {gate.intel.error}. This run judged new CVEs by CVSS "
            "alone, so an unscored or medium CVE that is being exploited would not fail.",
            "",
        ]
    elif not gate.intel.used:
        out += ["Judged by CVSS alone (no KEV/EPSS data asked for).", ""]
    if all_hosts and base is not None and head is not None:
        out += [f"Scanned {len(all_hosts)} host(s) whose closure this change touches.", ""]
        out += [*host_table(base, head, all_hosts, gate), ""]
    if lapsed:
        out += [
            f"**{len(lapsed)} accepted CVE(s) whose exception in "
            "`pins/vulnix-whitelist.toml` has expired.** Fix them, or renew the "
            "exception with a new reason and `until` date.",
            "",
            *tbl(lapsed),
            "",
        ]
    if res.failing:
        out += [
            f"**{len(res.failing)} new CVE(s) that fail the gate ({criteria(gate)}).** "
            "Wait for a fixed version, or accept each one in "
            "`pins/vulnix-whitelist.toml` with a reason and an `until` date.",
            "",
            *tbl(res.failing),
            "",
        ]
        out += [f"- {f.pname} {f.cve}: {'; '.join(gate.reasons(f))}" for f in res.failing]
        out.append("")
    else:
        out += [f"No new CVE fails the gate ({criteria(gate)}).", ""]
    if res.unscored:
        out += ["### New, not yet scored by NVD (not failing)", "", *tbl(res.unscored), ""]
    if res.below:
        out += ["### New, below the gate (not failing)", "", *tbl(res.below), ""]
    if res.exploited_open:
        out += [
            f"### Known exploited, already on the base and still open ({len(res.exploited_open)})",
            "",
            "Not caused by this change, so not failing, but each is in CISA KEV.",
            "",
            *tbl(res.exploited_open),
            "",
        ]
    if res.fixed:
        out += [f"### Fixed by this change ({len(res.fixed)})", "", *tbl(res.fixed), ""]
    return "\n".join(out)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("base", type=Path, nargs="?")
    ap.add_argument("head", type=Path, nargs="?")
    ap.add_argument("--threshold", type=float, default=7.0)
    ap.add_argument("--epss-threshold", type=float, default=0.1)
    intel_src = ap.add_mutually_exclusive_group()
    intel_src.add_argument("--fetch-intel", action="store_true", help="fetch CISA KEV and EPSS data")
    intel_src.add_argument("--intel", type=Path, help="read KEV and EPSS data from this JSON file")
    ap.add_argument("--summary", type=Path, action="append", default=[], help="append the Markdown report here")
    ap.add_argument("--whitelist", type=Path, help="fail findings of expired exceptions")
    ap.add_argument("--check-whitelist", type=Path, help="validate this file and exit")
    ap.add_argument("--head-closures", type=Path, help="per-host closure listings for the head")
    ap.add_argument("--base-closures", type=Path, help="per-host closure listings for the base")
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
    if bool(args.head_closures) != bool(args.base_closures):
        ap.error("--head-closures and --base-closures go together")
    try:
        base, head = load(args.base), load(args.head)
        all_hosts: list[str] = []
        if args.head_closures:
            head_closures = read_closures(args.head_closures)
            head = attribute(head, head_closures)
            base = attribute(base, read_closures(args.base_closures))
            all_hosts = list(head_closures)
        lapsed = expired(args.whitelist, head, args.today) if args.whitelist else []
        if args.intel:
            intel = read_intel(args.intel)
        elif args.fetch_intel:
            intel = fetch_intel({cve for _, cve in head.keys() | base.keys()})
        else:
            intel = Intel()
    except (OSError, ValueError, KeyError, TypeError, tomllib.TOMLDecodeError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    if intel.error:
        print(f"warning: {intel.error}; judging by CVSS alone", file=sys.stderr)
    gate = Gate(args.threshold, args.epss_threshold, intel)
    lapsed = sorted((f for f in lapsed if f.score is None or gate.fails(f)), key=gate.order)
    res = compare(base, head, gate)
    report = summary(res, gate, base, head, all_hosts, lapsed)
    print(report)
    for path in args.summary:
        with path.open("a") as fh:
            fh.write(report + "\n")
    return 1 if res.failing or lapsed else 0


if __name__ == "__main__":
    sys.exit(main())
