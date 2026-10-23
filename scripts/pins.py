#!/usr/bin/env python3
"""Keep track of every deliberate pin in this repo.

A pin freezes something (a flake input, a package version, an insecure-package
permit) so a nightly lock update cannot move it. Pins are debt: they stop
security fixes and new features arriving. Each one is recorded in
pins/registry.json with a reason, a date, a review deadline and, where it can
be automated, a probe that says whether the pin can go.

    pins.py check    CI gate: registry is valid and covers every pin in the code
    pins.py report   markdown table of all pins and their status
    pins.py probe    run each pin's probe (needs nix and gh)
    pins.py issues   open a GitHub issue for pins that are due, stale or removable

See .claude/skills/pins/SKILL.md for how to add, review and remove a pin.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parent.parent
REGISTRY = REPO / "pins" / "registry.json"

# A pin older than this is flagged even if its review date keeps being moved.
STALE_DAYS = 180
DUE_SOON_DAYS = 7
CLASSES = ("workaround", "exception", "lockstep", "tracked")
REQUIRED = ("id", "class", "kind", "site", "pinned", "since", "reviewed",
            "review_by", "reason", "removal")
PROBE_TIMEOUT_SECONDS = 1800
SKIP_DIRS = {".git", "node_modules", "result"}

Runner = Callable[[list[str], int], "subprocess.CompletedProcess[str]"]


def today() -> dt.date:
    """Today, or PINS_TODAY (YYYY-MM-DD) so tests and dry runs are repeatable."""
    override = os.environ.get("PINS_TODAY")
    return dt.date.fromisoformat(override) if override else dt.date.today()


def run_command(cmd: list[str], timeout: int) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, capture_output=True, text=True,
                          timeout=timeout, check=False)


def load_registry(path: Path = REGISTRY) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        data: dict[str, Any] = json.load(handle)
    return data


# --- detection: what is pinned in the code -------------------------------

_INPUT_ATTR = re.compile(r'^\s{4}([\w-]+)\.url\s*=\s*"github:([^"]+)"')
_INPUT_BLOCK = re.compile(r"^\s{4}([\w-]+)\s*=\s*\{")
_URL_LINE = re.compile(r'^\s+(inputs\.nixpkgs\.)?url\s*=\s*"github:([^"]+)"')
_REV = re.compile(r"[0-9a-f]{40}")
_TAG = re.compile(r"v?\d+(\.\d+)+")


def _pinned_ref(path: str) -> str | None:
    """The rev or tag in github:owner/repo/<ref>, or None for a branch."""
    parts = path.split("?")[0].split("/")
    if len(parts) < 3:
        return None
    ref = parts[2]
    if _REV.fullmatch(ref) or _TAG.fullmatch(ref):
        return ref
    return None


def detect_flake_pins(text: str) -> dict[str, str]:
    """Map input id to pinned ref for each rev- or tag-pinned flake input.

    A nested `inputs.nixpkgs.url` is reported as `<input>.inputs.nixpkgs`.
    """
    found: dict[str, str] = {}
    current = ""
    for line in text.splitlines():
        attr = _INPUT_ATTR.match(line)
        if attr:
            ref = _pinned_ref(attr.group(2))
            if ref:
                found[attr.group(1)] = ref
            continue
        block = _INPUT_BLOCK.match(line)
        if block:
            current = block.group(1)
            continue
        url = _URL_LINE.match(line)
        if url and current:
            ref = _pinned_ref(url.group(2))
            if ref:
                key = f"{current}.inputs.nixpkgs" if url.group(1) else current
                found[key] = ref
    return found


def detect_insecure(repo: Path) -> dict[str, list[str]]:
    """Map each permitted insecure package name to the files that permit it."""
    pattern = re.compile(r"permittedInsecurePackages\s*=\s*\[(.*?)\]", re.DOTALL)
    found: dict[str, list[str]] = {}
    for path in repo.rglob("*.nix"):
        rel = path.relative_to(repo)
        if any(part in SKIP_DIRS or part.startswith("result") for part in rel.parts):
            continue
        for match in pattern.finditer(path.read_text(encoding="utf-8")):
            for name in re.findall(r'"([^"]+)"', match.group(1)):
                found.setdefault(name, []).append(str(rel))
    return found


# --- validation ----------------------------------------------------------


def _date(value: Any) -> dt.date | None:
    try:
        return dt.date.fromisoformat(str(value))
    except ValueError:
        return None


def validate(reg: dict[str, Any], repo: Path, now: dt.date) -> tuple[list[str], list[str]]:
    """Return (errors, warnings). Errors fail CI; warnings are informational."""
    errors: list[str] = []
    warnings: list[str] = []
    max_days: dict[str, int] = reg.get("max_review_days", {})
    seen: set[str] = set()
    input_sites: set[str] = set()
    insecure_sites: set[str] = set()

    for pin in reg.get("pins", []):
        pid = str(pin.get("id", "?"))
        if pid in seen:
            errors.append(f"{pid}: duplicate id")
        seen.add(pid)
        missing = [f for f in REQUIRED if f not in pin]
        if missing:
            errors.append(f"{pid}: missing fields {missing}")
            continue
        if pin["class"] not in CLASSES:
            errors.append(f"{pid}: class must be one of {CLASSES}")
            continue
        since, reviewed, due = (_date(pin[k]) for k in ("since", "reviewed", "review_by"))
        if not (since and reviewed and due):
            errors.append(f"{pid}: since/reviewed/review_by must be YYYY-MM-DD")
            continue
        if since > now:
            errors.append(f"{pid}: since is in the future")
        if not since <= reviewed <= now:
            errors.append(f"{pid}: reviewed must be between since and today")
        limit = max_days.get(pin["class"])
        if limit is None:
            errors.append(f"{pid}: registry has no max_review_days for {pin['class']}")
        elif (due - reviewed).days > limit:
            errors.append(
                f"{pid}: review_by is {(due - reviewed).days} days after the last "
                f"review; {pin['class']} pins may wait at most {limit}")
        if len(str(pin["reason"])) < 30:
            errors.append(f"{pid}: reason is too short to explain the pin")
        if not pin.get("probe") and not pin.get("manual_test"):
            errors.append(f"{pid}: needs a probe or a manual_test")
        site = pin["site"]
        if "input" in site:
            input_sites.add(site["input"])
        elif "file" in site and "match" in site:
            file = repo / site["file"]
            if not file.is_file() or site["match"] not in file.read_text(encoding="utf-8"):
                errors.append(f"{pid}: {site['match']!r} not found in {site['file']}"
                              " (stale entry: was the pin removed?)")
            if pin["kind"] == "insecure-package":
                insecure_sites.add(site["match"])
        else:
            errors.append(f"{pid}: site needs `input` or `file` + `match`")
        if status(pin, now) in ("overdue", "stale", "needs-triage"):
            warnings.append(f"{pid}: {status(pin, now)}")

    flake = repo / "flake.nix"
    detected = detect_flake_pins(flake.read_text(encoding="utf-8")) if flake.is_file() else {}
    for name in sorted(set(detected) - input_sites):
        errors.append(f"flake input {name} is pinned to {detected[name]} but has no "
                      "registry entry; add one to pins/registry.json")
    for name in sorted(input_sites - set(detected)):
        errors.append(f"registry entry for flake input {name} but flake.nix no longer "
                      "pins it; remove the entry")
    for name, files in sorted(detect_insecure(repo).items()):
        if name not in insecure_sites:
            errors.append(f"{name} is in permittedInsecurePackages ({files[0]}) but has "
                          "no registry entry")
    return errors, warnings


def status(pin: dict[str, Any], now: dt.date) -> str:
    """overdue, stale (older than STALE_DAYS, never `tracked`), needs-triage,
    due-soon or ok, most urgent first."""
    since = _date(pin.get("since")) or now
    due = _date(pin.get("review_by")) or now
    if due < now:
        return "overdue"
    if pin.get("class") != "tracked" and (now - since).days > STALE_DAYS:
        return "stale"
    if pin.get("needs_triage"):
        return "needs-triage"
    if (due - now).days <= DUE_SOON_DAYS:
        return "due-soon"
    return "ok"


# --- probes --------------------------------------------------------------


def version_key(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in re.findall(r"\d+", version))


@dataclass
class ProbeResult:
    id: str
    holds: bool | None  # None: the probe itself failed
    meaning: str  # "removable" or "update-available"
    detail: str


def run_probe(pin: dict[str, Any], run: Runner = run_command) -> ProbeResult:
    probe = pin.get("probe")
    pid = str(pin["id"])
    if not probe:
        return ProbeResult(pid, None, "manual", pin.get("manual_test", ""))
    kind = probe["type"]
    timeout = int(probe.get("timeout", PROBE_TIMEOUT_SECONDS))
    meaning = str(probe.get("meaning", "removable"))
    try:
        if kind == "command":
            done = run(list(probe["cmd"]), timeout)
            return ProbeResult(pid, done.returncode == 0, meaning,
                               (done.stderr or done.stdout)[-300:].strip())
        if kind == "issue-closed":
            done = run(["gh", "api", f"repos/{probe['repo']}/issues/{probe['number']}",
                        "--jq", ".state"], timeout)
            state = done.stdout.strip()
            return ProbeResult(pid, state == "closed" if done.returncode == 0 else None,
                               "removable", f"{probe['repo']}#{probe['number']} is {state}")
        if kind == "version-at-least":
            done = run(["nix", "eval", "--raw", f"{probe['flake_ref']}#{probe['attr']}.version"],
                       timeout)
            if done.returncode != 0:
                return ProbeResult(pid, None, "removable", done.stderr[-300:].strip())
            have = done.stdout.strip()
            need = probe["version"]
            return ProbeResult(pid, version_key(have) >= version_key(need), "removable",
                               f"{probe['attr']} is {have}, need >= {need}")
        if kind == "newer-release":
            done = run(["gh", "api", f"repos/{probe['repo']}/releases/latest",
                        "--jq", ".tag_name"], timeout)
            if done.returncode != 0:
                # Some projects tag without publishing GitHub releases.
                done = run(["gh", "api", f"repos/{probe['repo']}/tags", "--jq",
                            ".[0].name"], timeout)
            if done.returncode != 0:
                return ProbeResult(pid, None, "update-available", done.stderr[-300:].strip())
            latest = done.stdout.strip()
            return ProbeResult(pid, latest != probe["current"], "update-available",
                               f"latest release {latest}, pinned {probe['current']}")
    except (subprocess.TimeoutExpired, OSError, KeyError) as err:
        return ProbeResult(pid, None, meaning, f"probe failed: {err!r}")
    return ProbeResult(pid, None, meaning, f"unknown probe type {kind!r}")


# --- issues --------------------------------------------------------------


@dataclass
class IssueSpec:
    title: str
    body: str


def plan_issues(reg: dict[str, Any], results: list[ProbeResult],
                now: dt.date) -> list[IssueSpec]:
    """What should be raised this week. Pure, so it can be tested."""
    by_id = {r.id: r for r in results}
    specs: list[IssueSpec] = []
    for pin in reg.get("pins", []):
        pid = pin["id"]
        result = by_id.get(pid)
        if result and result.holds:
            what = ("is probably removable" if result.meaning == "removable"
                    else "has an update available")
            specs.append(IssueSpec(
                f"pin {pid}: {what}",
                f"The probe for `{pid}` passed: {result.detail}\n\n"
                f"Reason it was pinned: {pin['reason']}\n\n"
                f"To act: {pin['removal']}\n\nSee pins/registry.json and the `pins` skill."))
        state = status(pin, now)
        if state == "overdue":
            specs.append(IssueSpec(
                f"pin {pid}: review overdue (due {pin['review_by']})",
                f"`{pid}` was due for review on {pin['review_by']}.\n\n"
                f"Reason: {pin['reason']}\n\nRemove it, or re-test it and move `reviewed` "
                f"and `review_by` forward with a note."))
        elif state == "needs-triage":
            specs.append(IssueSpec(
                f"pin {pid}: reason unknown, needs triage",
                f"`{pid}` is pinned but nobody has recorded why: {pin['reason']}\n\n"
                f"Test whether it can go: {pin['removal']}\n\n"
                f"Then delete the entry, or write the real reason and clear `needs_triage`."))
        elif state == "stale":
            specs.append(IssueSpec(
                f"pin {pid}: older than {STALE_DAYS} days",
                f"`{pid}` has been pinned since {pin['since']} ({STALE_DAYS}+ days) however "
                f"often it has been re-reviewed.\n\nReason: {pin['reason']}\n\n"
                f"Decide whether to fix the cause, replace the pin, or accept it explicitly."))
    return specs


def cmd_issues(reg: dict[str, Any], results: list[ProbeResult], repo: str,
               dry_run: bool, run: Runner = run_command) -> int:
    for spec in plan_issues(reg, results, today()):
        found = run(["gh", "issue", "list", "--repo", repo, "--state", "open",
                     "--search", f'"{spec.title}" in:title', "--json", "title",
                     "--jq", ".[].title"], 120)
        if spec.title in found.stdout.splitlines():
            print(f"exists  {spec.title}")
            continue
        if dry_run:
            print(f"would open  {spec.title}")
            continue
        made = run(["gh", "issue", "create", "--repo", repo, "--title", spec.title,
                    "--body", spec.body], 120)
        print(f"opened  {spec.title}" if made.returncode == 0
              else f"FAILED  {spec.title}: {made.stderr.strip()}")
    return 0


# --- commands ------------------------------------------------------------


def cmd_check(args: argparse.Namespace) -> int:
    reg = load_registry()
    errors, warnings = validate(reg, REPO, today())
    for line in warnings:
        print(f"warning: {line}")
    for line in errors:
        print(f"error: {line}")
    if args.fail_overdue and any(w.endswith(("overdue", "stale", "needs-triage"))
                                 for w in warnings):
        return 1
    print(f"{len(reg.get('pins', []))} pins, {len(errors)} errors, {len(warnings)} warnings")
    return 1 if errors else 0


def cmd_report(_args: argparse.Namespace) -> int:
    reg = load_registry()
    now = today()
    print("| pin | class | since | age | review by | status | why |")
    print("| --- | --- | --- | --- | --- | --- | --- |")
    for pin in sorted(reg["pins"], key=lambda p: p["review_by"]):
        age = (now - dt.date.fromisoformat(pin["since"])).days
        why = str(pin["reason"]).split(". ")[0][:90].replace("|", "/")
        print(f"| {pin['id']} | {pin['class']} | {pin['since']} | {age}d | "
              f"{pin['review_by']} | {status(pin, now)} | {why} |")
    return 0


def cmd_probe(args: argparse.Namespace) -> int:
    reg = load_registry()
    wanted = set(args.id)
    results: list[ProbeResult] = []
    for pin in reg["pins"]:
        if wanted and pin["id"] not in wanted:
            continue
        if args.dry_run:
            print(f"{pin['id']}: {json.dumps(pin.get('probe') or pin.get('manual_test'))}")
            continue
        results.append(run_probe(pin))
    if args.dry_run:
        return 0
    if args.json:
        print(json.dumps([r.__dict__ for r in results], indent=2))
    else:
        for r in results:
            verdict = {True: "YES", False: "no", None: "n/a"}[r.holds]
            print(f"{r.id:<34} {r.meaning:<17} {verdict:<4} {r.detail[:100]}")
    return 0


def cmd_issues_cli(args: argparse.Namespace) -> int:
    reg = load_registry()
    raw = json.loads(Path(args.probe_json).read_text(encoding="utf-8")) if args.probe_json else []
    results = [ProbeResult(**item) for item in raw]
    return cmd_issues(reg, results, args.repo, args.dry_run)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    check = sub.add_parser("check", help="validate the registry against the code")
    check.add_argument("--fail-overdue", action="store_true",
                       help="also fail when a pin is overdue or stale")
    check.set_defaults(func=cmd_check)
    sub.add_parser("report", help="print a markdown table").set_defaults(func=cmd_report)
    probe = sub.add_parser("probe", help="run pin probes")
    probe.add_argument("--id", action="append", default=[], help="only this pin")
    probe.add_argument("--json", action="store_true")
    probe.add_argument("--dry-run", action="store_true", help="print probes, run nothing")
    probe.set_defaults(func=cmd_probe)
    issues = sub.add_parser("issues", help="open GitHub issues for pins needing attention")
    issues.add_argument("--probe-json", help="output of `probe --json`")
    issues.add_argument("--repo", required=True, help="owner/name")
    issues.add_argument("--dry-run", action="store_true")
    issues.set_defaults(func=cmd_issues_cli)
    args = parser.parse_args(argv)
    code: int = args.func(args)
    return code


if __name__ == "__main__":
    sys.exit(main())
