#!/usr/bin/env python3
"""Render the CVE tracking issue from the daily scan of main.

scripts/cve-status.sh writes status.json (cve_diff.py --status --json): every
finding on main with KEV, EPSS, its hosts, whether it runs there and whether
it would fail the PR gate (`alert`). This script turns it into the body of
one GitHub issue, "CVE status of main", that the daily workflow edits in
place, plus two optional comments:

- an alert, when a finding becomes alert-grade that was not the day before:
  a new CVE, or an old one that has just been added to KEV or whose EPSS
  has crossed the threshold;
- a weekly digest (Mondays, or --digest): what is open, what is new and
  what was fixed in the last 7 days.

Findings that only build (runtime "build") are counted but not tracked,
unless they are alert-grade (known exploited). What was seen when is kept in
a hidden, compressed `cve-state` comment at the end of the body, so the only state is the
issue itself. Pure: reads files, writes files, calls nothing.

Usage: cve_track.py --status status.json [--previous body.md] [--fixes fixes.json]
                    [--commit SHA] [--run-url URL] [--today YYYY-MM-DD] [--digest]
                    --body OUT [--alert OUT] [--digest-out OUT]
--alert and --digest-out are only written when there is something to say.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import datetime as dt
import json
import re
import sys
import zlib
from pathlib import Path

MARKER = "<!-- cve-status:tracking -->"
TITLE = "CVE status of main"
STATE = re.compile(r"<!-- cve-state:v2 ([A-Za-z0-9+/=]+) -->")
BODY_LIMIT = 65000  # GitHub allows 65536 characters
FIXED_KEEP_DAYS = 8
DIGEST_TOP = 10


def key(f: dict) -> str:
    return f"{f['pname']}|{f['cve']}"


def read_state(body: str) -> dict | None:
    m = STATE.search(body or "")
    if not m:
        return None
    try:
        state = json.loads(zlib.decompress(base64.b64decode(m.group(1))))
    except (binascii.Error, zlib.error, ValueError):
        return None
    return state if isinstance(state, dict) else None


def encode_state(state: dict) -> str:
    """Compressed: a few thousand findings would not fit in an issue as JSON."""
    raw = json.dumps(state, separators=(",", ":")).encode()
    return f"<!-- cve-state:v2 {base64.b64encode(zlib.compress(raw, 9)).decode()} -->"


def tracked(f: dict) -> bool:
    return f.get("runtime") != "build" or f.get("alert")


def next_state(prev: dict | None, findings: list[dict], today: dt.date) -> dict:
    prev = prev or {}
    d = today.isoformat()
    now_open = {key(f) for f in findings if tracked(f)}
    now_alert = {key(f) for f in findings if f.get("alert")}
    p_open, p_alert = prev.get("open", {}), prev.get("alerts", {})
    fixed = {
        k: v
        for k, v in prev.get("fixed", {}).items()
        if k not in now_open and (today - dt.date.fromisoformat(v)).days <= FIXED_KEEP_DAYS
    }
    fixed.update({k: d for k in p_open.keys() - now_open})
    return {
        "open": {k: p_open.get(k, d) for k in sorted(now_open)},
        "alerts": {k: p_alert.get(k, d) for k in sorted(now_alert)},
        "fixed": dict(sorted(fixed.items())),
    }


def fmt_pct(v) -> str:
    return "-" if v is None else f"{v:.1%}"


def fix_note(f: dict, fixes: dict) -> str:
    fix = fixes.get(f["pname"])
    if not fix:
        return ""
    if fix.get("pr"):
        return f"[fix PR]({fix['pr']})"
    return fix.get("note", "")


def fmt_hosts(hosts: list[str], all_hosts: list[str]) -> str:
    if len(all_hosts) > 1 and len(hosts) == len(all_hosts):
        return f"all {len(hosts)}"
    return ", ".join(hosts) if hosts else "-"


def table(findings: list[dict], state: dict, fixes: dict, all_hosts: list[str]) -> list[str]:
    lines = [
        "| Package | Version | CVE | CVSSv3 | EPSS | KEV | Runs | Hosts | Since | Fix |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for f in findings:
        score = "unscored" if f.get("score") is None else f"{f['score']:.1f}"
        runs = {"runtime": "yes", "build": "build only", "unknown": "unknown"}.get(f.get("runtime", ""), "")
        lines.append(
            f"| {f['pname']} | {', '.join(f.get('versions', []))} "
            f"| [{f['cve']}](https://nvd.nist.gov/vuln/detail/{f['cve']}) | {score} "
            f"| {fmt_pct(f.get('epss'))} | {'yes' if f.get('kev') else ''} | {runs} "
            f"| {fmt_hosts(f.get('hosts', []), all_hosts)} "
            f"| {state['open'].get(key(f)) or state['alerts'].get(key(f), '')} | {fix_note(f, fixes)} |"
        )
    return lines


def host_table(findings: list[dict], all_hosts: list[str]) -> list[str]:
    lines = [
        "| Host | Open, runs | Alerts | Known exploited | Build only |",
        "| --- | --- | --- | --- | --- |",
    ]
    for host in all_hosts:
        mine = [f for f in findings if host in f.get("hosts", [])]
        lines.append(
            f"| {host} | {sum(1 for f in mine if f.get('runtime') != 'build')} "
            f"| {sum(1 for f in mine if f.get('alert'))} "
            f"| {sum(1 for f in mine if f.get('kev'))} "
            f"| {sum(1 for f in mine if f.get('runtime') == 'build')} |"
        )
    return lines


def criteria(status: dict) -> str:
    if status.get("intel_error"):
        return f"CVSSv3 {status['threshold']:.1f}+"
    return f"CVSSv3 {status['threshold']:.1f}+, in CISA KEV, or EPSS {status['epss_threshold']:.0%}+"


def render_body(status, state, fixes, today, commit="", run_url="") -> str:
    findings = status["open"]
    all_hosts = status.get("hosts", [])
    alerts = [f for f in findings if f.get("alert")]
    others = [f for f in findings if not f.get("alert") and f.get("runtime") != "build"]
    build = [f for f in findings if not f.get("alert") and f.get("runtime") == "build"]
    where = f" at `{commit[:12]}`" if commit else ""
    run = f" ([run]({run_url}))" if run_url else ""
    head = [
        MARKER,
        f"## {TITLE}",
        "",
        f"Updated {today.isoformat()}{where}{run} by `cve-daily.yaml`. An alert is a "
        f"finding that would fail the PR gate ({criteria(status)}) and runs on a host, "
        "or is known exploited even if it only builds.",
        "",
    ]
    if status.get("intel_error"):
        head += [f"> [!WARNING]\n> {status['intel_error']}. Judged by CVSS alone today.", ""]
    head += [*host_table(findings, all_hosts), ""]
    if alerts:
        head += [f"### Alerts ({len(alerts)})", "", *table(alerts, state, fixes, all_hosts), ""]
    else:
        head += ["### Alerts (0)", "", "Nothing open would fail the PR gate.", ""]
    tail = [
        f"{len(build)} more finding(s) are in packages that only build, not run, and are not listed.",
        "",
        encode_state(state),
    ]

    def build(shown: int) -> str:
        middle = []
        if others:
            middle = [f"### Other open findings that run on a host ({len(others)})", ""]
            middle += table(others[:shown], state, fixes, all_hosts)
            if shown < len(others):
                middle += ["", f"_{len(others) - shown} more not shown; the run's job summary has them all._"]
            middle.append("")
        return "\n".join(head + middle + tail)

    # The most rows that fit, by bisection.
    lo, hi = 0, len(others)
    if len(build(hi)) <= BODY_LIMIT:
        return build(hi)
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if len(build(mid)) <= BODY_LIMIT:
            lo = mid
        else:
            hi = mid - 1
    return build(lo)


def render_alert(new_alerts: list[dict], state, fixes, all_hosts) -> str:
    return "\n".join([
        f"**{len(new_alerts)} new alert(s) on main.** Each would fail the PR gate and runs on a "
        "host, or is known exploited. A fix PR is opened by itself when nixos-unstable or "
        "master has one that rebuilds little; otherwise the Fix column says what is waited on.",
        "",
        *table(new_alerts, state, fixes, all_hosts),
    ])


def render_digest(status, state, fixes, today) -> str:
    findings = status["open"]
    week = (today - dt.timedelta(days=7)).isoformat()
    open_ = [f for f in findings if tracked(f)]
    new = [f for f in open_ if state["open"].get(key(f), "") > week]
    fixed = sorted(k for k, d in state["fixed"].items() if d > week)
    alerts = [f for f in findings if f.get("alert")]
    prs = sorted({fix["pr"] for fix in fixes.values() if fix.get("pr")})
    out = [
        f"### Weekly CVE digest, {today.isoformat()}",
        "",
        f"- **{len(alerts)}** alert(s) open.",
        f"- **{len(open_)}** finding(s) in packages that run on a host; **{len(new)}** new "
        f"in the last 7 days, **{len(fixed)}** fixed.",
        f"- Fix PRs open: {', '.join(prs) if prs else 'none'}.",
        "",
    ]
    if alerts:
        out += ["Top alerts:", "", *table(alerts[:DIGEST_TOP], state, fixes, status.get("hosts", [])), ""]
    if fixed:
        shown = ", ".join(k.replace("|", " ") for k in fixed[:30])
        out += [f"Fixed this week: {shown}{' …' if len(fixed) > 30 else ''}", ""]
    return "\n".join(out)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--status", type=Path, required=True)
    ap.add_argument("--previous", type=Path)
    ap.add_argument("--fixes", type=Path)
    ap.add_argument("--commit", default="")
    ap.add_argument("--run-url", default="")
    ap.add_argument("--today", type=dt.date.fromisoformat, default=dt.date.today())
    ap.add_argument("--digest", action="store_true", help="write the digest even if it is not Monday")
    ap.add_argument("--body", type=Path, required=True)
    ap.add_argument("--alert", type=Path)
    ap.add_argument("--digest-out", type=Path)
    args = ap.parse_args(argv)
    try:
        status = json.loads(args.status.read_text())
        findings = status["open"]
        prev_body = args.previous.read_text() if args.previous and args.previous.exists() else ""
        fixes = json.loads(args.fixes.read_text()) if args.fixes and args.fixes.exists() else {}
    except (OSError, ValueError, KeyError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    prev = read_state(prev_body)
    state = next_state(prev, findings, args.today)
    args.body.write_text(render_body(status, state, fixes, args.today, args.commit, args.run_url) + "\n")
    # The first run has nothing to compare against; the new issue is the alert.
    new_alerts = [f for f in findings if f.get("alert") and prev is not None and key(f) not in prev.get("alerts", {})]
    if args.alert and new_alerts:
        args.alert.write_text(render_alert(new_alerts, state, fixes, status.get("hosts", [])) + "\n")
    if args.digest_out and (args.digest or args.today.weekday() == 0) and prev is not None:
        args.digest_out.write_text(render_digest(status, state, fixes, args.today) + "\n")
    print(f"{len(findings)} finding(s), {len(state['alerts'])} alert(s), {len(new_alerts)} new alert(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
