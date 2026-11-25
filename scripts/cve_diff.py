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

With --runtime DIR (one file per host listing the store paths of its built
system, the runtime closure), each finding is marked `runtime` when one of
its hosts has a package of that name in its runtime closure, `build` when
every one of its hosts has runtime data and none has it (a compiler or build
tool that never runs on the host), and `unknown` when a host has no runtime
data. A build-only finding fails only when it is in KEV; `unknown` is judged
like `runtime`. Packages are matched by name, not hash, so the base's
runtime closure can classify the head's findings: a PR scan has not built
the head. The cost is that a PR which both pulls a build-only package into
the running system and brings it a new CVE is judged by the base, where the
package was build-only; the daily scan of main (cve-status.sh) uses main's
own built systems and catches it.

`--status FILE` reads one report as the current state of main instead of
comparing two: nothing is new or fixed, and `--json` lists every finding
with whether it would fail the gate (`alert`).

`--json FILE` writes the findings, with EPSS, KEV, hosts and runtime, as JSON
for scripts/cve_track.py and scripts/cve_fix.py.

`--has-expired FILE` exits 0 when an entry's `until` date has passed (and
names them), 1 otherwise: cve-scan.sh then scans every host, since an
expired exception can sit on a host the change does not touch.

A selector `pname` covers every version of the package and `pname-version`
only that version, as in vulnix.

`--check-whitelist FILE` validates the accepted-CVE file and exits: every
entry must name one exact package (no `*`), list its CVEs, carry a comment,
and have an `until` date at most 90 days after today. cve-scan.sh runs it
before scanning, because vulnix itself accepts entries that silence every
CVE of a package forever.

Usage: cve_diff.py BASE.json HEAD.json [--threshold 7.0] [--epss-threshold 0.1]
                   [--fetch-intel | --intel FILE] [--summary FILE]...
                   [--whitelist FILE] [--today YYYY-MM-DD]
                   [--head-closures DIR --base-closures DIR] [--runtime DIR]
                   [--json FILE]
       cve_diff.py --status HEAD.json [--head-closures DIR] [--runtime DIR]
                   [--fetch-intel | --intel FILE] [--json FILE] ...
       cve_diff.py --check-whitelist FILE [--today YYYY-MM-DD]
       cve_diff.py --has-expired FILE [--today YYYY-MM-DD]
Exit codes: 0 nothing new fails the gate, 1 something does, 2 bad input.
"""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import http.client
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
    runtime: str = ""  # "runtime", "build", "unknown", or "" without runtime data


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


STORE_NAME = re.compile(r"^/nix/store/[0-9a-z]{32}-(.+)$")


def read_runtime(directory: Path) -> dict[str, set[str]]:
    """Per host, the names (store path minus hash) in its runtime closure."""
    out = {}
    for host, paths in read_closures(directory).items():
        out[host] = {m.group(1) for m in map(STORE_NAME.match, paths) if m}
    return out


def attribute(findings: dict[Key, Finding], closures: dict[str, set[str]]) -> dict[Key, Finding]:
    """Set each finding's hosts: those whose closure holds one of its derivations.

    vulnix counts derivations with the same name and patches as one and keeps
    the path of the first it loads, so a host whose closure holds an equal
    derivation at another store path would be missed. A host also matches on
    the derivation's name (its path minus the hash). That can name a host
    whose same-named derivation carries a patch for the CVE; reporting an
    extra host is the safe way to be wrong.
    """
    names = {h: {m.group(1) for m in map(STORE_NAME.match, paths) if m} for h, paths in closures.items()}

    def holds(host: str, drv: str) -> bool:
        if drv in closures[host]:
            return True
        m = STORE_NAME.match(drv)
        return bool(m) and m.group(1) in names[host]

    return {
        key: dataclasses.replace(f, hosts=tuple(h for h in closures if any(holds(h, d) for d in f.drvs)))
        for key, f in findings.items()
    }


def in_runtime(pname: str, names: set[str]) -> bool:
    """A store path named <pname>-<version>[-<output>] is in this closure."""
    pattern = re.compile(re.escape(pname) + r"-\d")
    return pname in names or any(pattern.match(n) for n in names)


def classify(findings: dict[Key, Finding], runtime: dict[str, set[str]]) -> dict[Key, Finding]:
    """Mark each finding runtime, build or unknown from its hosts' runtime closures."""
    out = {}
    for key, f in findings.items():
        known = [h for h in f.hosts if h in runtime]
        if any(in_runtime(f.pname, runtime[h]) for h in known):
            where = "runtime"
        elif f.hosts and len(known) == len(f.hosts):
            where = "build"
        else:
            where = "unknown"
        out[key] = dataclasses.replace(f, runtime=where)
    return out


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
    # HTTPException: a response cut short (IncompleteRead) is not an OSError.
    except (OSError, http.client.HTTPException, ValueError, KeyError, TypeError) as e:
        return Intel(error=f"could not fetch KEV/EPSS data ({e!r})", used=True)
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


def covers(name: str, finding: Finding) -> bool:
    """A whitelist selector `pname` covers every version; `pname-version` only that one."""
    return name == finding.pname or any(name == f"{finding.pname}-{v}" for v in finding.versions)


def expired_entries(path: Path, today: dt.date) -> dict[str, set[str]]:
    """Selector -> CVEs, for each whitelist entry whose until date has passed."""
    out = {}
    for name, entry in read_whitelist(path).items():
        try:
            until = as_date(entry.get("until"))
        except ValueError:
            continue
        if until is None or until > today:
            continue
        cves = entry.get("cve") or []
        out[name] = {cves} if isinstance(cves, str) else set(cves)
    return out


def expired(path: Path, head: dict[Key, Finding], today: dt.date) -> list[Finding]:
    """Head findings covered by a whitelist entry whose until date has passed."""
    return [
        finding
        for name, cves in expired_entries(path, today).items()
        for (_, cve), finding in head.items()
        if cve in cves and covers(name, finding)
    ]


@dataclass(frozen=True)
class Gate:
    threshold: float
    epss_threshold: float
    intel: Intel

    def reasons(self, f: Finding) -> list[str]:
        """Why this finding fails the gate; empty when it does not.

        A build-only finding fails only when it is known exploited."""
        out = []
        if f.cve in self.intel.kev:
            out.append("known exploited (CISA KEV)" + (", though build-time only" if f.runtime == "build" else ""))
        if f.runtime == "build":
            return out
        epss = self.intel.epss.get(f.cve)
        if epss is not None and epss >= self.epss_threshold:
            out.append(f"EPSS {epss:.0%}")
        if f.score is not None and f.score >= self.threshold:
            out.append(f"CVSS {f.score:.1f}")
        return out

    def fails(self, f: Finding) -> bool:
        return bool(self.reasons(f))

    def severe(self, f: Finding) -> bool:
        """Would fail the gate if it ran on the host."""
        return self.fails(dataclasses.replace(f, runtime="runtime"))

    def order(self, f: Finding) -> tuple:
        """Most likely to be exploited first: KEV, then runtime, EPSS, CVSS."""
        return (
            f.cve not in self.intel.kev,
            f.runtime == "build",
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
    build_only: list[Finding] = field(default_factory=list)  # new, would fail, but build-time only


def compare(base: dict[Key, Finding], head: dict[Key, Finding], gate: Gate) -> Result:
    new = [head[k] for k in head.keys() - base.keys()]
    passing = [f for f in new if not gate.fails(f)]
    build_only = [f for f in passing if f.runtime == "build" and gate.severe(f)]
    passing = [f for f in passing if f not in build_only]
    return Result(
        failing=sorted((f for f in new if gate.fails(f)), key=gate.order),
        unscored=sorted((f for f in passing if f.score is None), key=gate.order),
        below=sorted((f for f in passing if f.score is not None), key=gate.order),
        build_only=sorted(build_only, key=gate.order),
        fixed=sorted((base[k] for k in base.keys() - head.keys()), key=gate.order),
        exploited_open=sorted(
            (head[k] for k in head.keys() & base.keys() if k[1] in gate.intel.kev), key=gate.order
        ),
    )


def fmt_score(score: float | None) -> str:
    return "unscored" if score is None else f"{score:.1f}"


def fmt_hosts(hosts: tuple[str, ...], all_hosts: list[str]) -> str:
    if len(all_hosts) > 1 and len(hosts) == len(all_hosts):
        return f"all {len(hosts)} scanned"
    return ", ".join(hosts) if hosts else "-"


def table(findings: list[Finding], gate: Gate, all_hosts: list[str]) -> list[str]:
    cols = ["Package", "Version", "CVE", "CVSSv3"]
    if gate.intel.used:
        cols += ["EPSS", "KEV"]
    runtime = any(f.runtime for f in findings)
    if runtime:
        cols.append("Runs")
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
        if runtime:
            row.append({"runtime": "yes", "build": "build only", "unknown": "unknown"}.get(f.runtime, ""))
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
    if res.build_only:
        out += [
            f"### New, build-time only ({len(res.build_only)}, not failing)",
            "",
            "Severe enough to fail, but no host it is on has the package in its "
            "running system: it is only used to build. Fails only if known exploited.",
            "",
            *tbl(res.build_only),
            "",
        ]
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


def as_json(f: Finding, gate: Gate) -> dict:
    return {
        "pname": f.pname,
        "cve": f.cve,
        "score": f.score,
        "epss": gate.intel.epss.get(f.cve),
        "kev": f.cve in gate.intel.kev,
        "versions": list(f.versions),
        "drvs": list(f.drvs),
        "hosts": list(f.hosts),
        "runtime": f.runtime,
        "alert": gate.fails(f),
        "reasons": gate.reasons(f),
    }


def write_json(path: Path, gate: Gate, all_hosts, sections: dict[str, list[Finding]]) -> None:
    data = {
        "threshold": gate.threshold,
        "epss_threshold": gate.epss_threshold,
        "intel_error": gate.intel.error,
        "hosts": list(all_hosts),
        **{name: [as_json(f, gate) for f in fs] for name, fs in sections.items()},
    }
    path.write_text(json.dumps(data, indent=1) + "\n")


def status_summary(open_: list[Finding], gate: Gate, all_hosts: list[str]) -> str:
    alerts = [f for f in open_ if gate.fails(f)]
    out = ["## CVE status (vulnix)", ""]
    if gate.intel.error:
        out += [f"> [!WARNING]\n> {gate.intel.error}. Judged by CVSS alone.", ""]
    out += [
        f"{len(open_)} open finding(s), {len(alerts)} that would fail the gate ({criteria(gate)}).",
        "",
    ]
    if alerts:
        out += table(alerts, gate, all_hosts) + [""]
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
    ap.add_argument("--has-expired", type=Path, help="exit 0 if this file has an expired entry, else 1")
    ap.add_argument("--head-closures", type=Path, help="per-host closure listings for the head")
    ap.add_argument("--base-closures", type=Path, help="per-host closure listings for the base")
    ap.add_argument("--runtime", type=Path, help="per-host runtime closure listings")
    ap.add_argument("--status", type=Path, help="report this one scan as the current state")
    ap.add_argument("--json", type=Path, help="write the findings here as JSON")
    ap.add_argument("--today", type=dt.date.fromisoformat, default=dt.date.today())
    args = ap.parse_args(argv)

    if args.has_expired:
        try:
            names = sorted(expired_entries(args.has_expired, args.today))
        except (OSError, ValueError, tomllib.TOMLDecodeError) as e:
            print(f"error: {e}", file=sys.stderr)
            return 2
        for name in names:
            print(f"expired: {name}")
        return 0 if names else 1

    if args.check_whitelist:
        try:
            errors = check_whitelist(args.check_whitelist, args.today)
        except (OSError, ValueError, tomllib.TOMLDecodeError) as e:
            print(f"error: {e}", file=sys.stderr)
            return 2
        for e in errors:
            print(f"error: {e}", file=sys.stderr)
        return 2 if errors else 0

    if args.status:
        if args.base or args.base_closures:
            ap.error("--status takes one report, not BASE.json HEAD.json")
    elif not (args.base and args.head):
        ap.error("BASE.json and HEAD.json are required")
    elif bool(args.head_closures) != bool(args.base_closures):
        ap.error("--head-closures and --base-closures go together")
    try:
        if args.status:
            base, head = {}, load(args.status)
        else:
            base, head = load(args.base), load(args.head)
        all_hosts: list[str] = []
        if args.head_closures:
            head_closures = read_closures(args.head_closures)
            head = attribute(head, head_closures)
            if args.base_closures:
                base = attribute(base, read_closures(args.base_closures))
            all_hosts = list(head_closures)
        if args.runtime:
            runtime = read_runtime(args.runtime)
            head, base = classify(head, runtime), classify(base, runtime)
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
    if args.status:
        open_ = sorted(head.values(), key=gate.order)
        report = status_summary(open_, gate, all_hosts)
        sections = {"open": open_, "lapsed": lapsed}
        rc = 0
    else:
        res = compare(base, head, gate)
        report = summary(res, gate, base, head, all_hosts, lapsed)
        sections = {
            "failing": res.failing,
            "fixed": res.fixed,
            "unscored": res.unscored,
            "below": res.below,
            "build_only": res.build_only,
            "exploited_open": res.exploited_open,
            "lapsed": lapsed,
            "open": sorted(head.values(), key=gate.order),
        }
        rc = 1 if res.failing or lapsed else 0
    print(report)
    for path in args.summary:
        with path.open("a") as fh:
            fh.write(report + "\n")
    if args.json:
        write_json(args.json, gate, all_hosts, sections)
    return rc


if __name__ == "__main__":
    sys.exit(main())
