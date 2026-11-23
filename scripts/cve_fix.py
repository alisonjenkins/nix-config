#!/usr/bin/env python3
"""Find fixes for the CVE alerts on main, and open a PR for the cheap ones.

Reads status.json from scripts/cve-status.sh. For each package with an
alert (a finding that would fail the PR gate), it asks, in order:

1. Is the package a top-level nixpkgs attribute of that name? If not, there
   is no one-line swap, and a person has to look.
2. Does the head of nixos-26.05 (the channel the hosts use) have a version
   vulnix no longer flags for these CVEs? Then the nightly update brings it:
   nothing to do.
3. Does nixos-unstable? Hydra builds it, so taking the package from there
   costs only the rebuild of what depends on it. When that rebuild is small
   (at most --max-rebuilds derivations in the hosts' closures), it adds the
   package to overlays/cve-fixes.json with a pins/registry.json entry,
   proves the swap with scripts/cve-scan.sh (the CVE must show as fixed and
   nothing may fail), and opens a PR. The PR is never auto-merged. When the
   rebuild is large (openssl, glibc) the note says to wait for nixos-26.05.
4. Does master? Not built by Hydra yet, so it is only noted.

"vulnix no longer flags it" is vulnix's own version matching run on the
candidate derivation, so the answer is the same one the gate would give.
Results go to --out as {pname: {"note": ..., "pr": url?}} for
scripts/cve_track.py's Fix column. Without --apply nothing is written, and
nothing is pushed or opened without --publish.

Usage: cve_fix.py --status status.json --closures DIR --out fixes.json
                  [--apply --repo OWNER/NAME --base-sha SHA --ready ready.json]
                  [--max-rebuilds 40] [--max-packages 15] [--today YYYY-MM-DD]
       cve_fix.py --publish ready.json --repo OWNER/NAME --out fixes.json
  --apply proves each cheap fix and keeps it as a local branch; it needs
  only a read token (GH_TOKEN) to see existing PRs. --publish pushes those
  branches and opens the PRs; give it the updater App's token, minted just
  before, since the proving can outlast the App token's hour and a PR made
  with GITHUB_TOKEN starts no checks.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

REPO = Path(__file__).resolve().parent.parent
FIXES_FILE = "overlays/cve-fixes.json"
REGISTRY_FILE = "pins/registry.json"
REVIEW_DAYS = 30
CHANNEL = "github:NixOS/nixpkgs/nixos-26.05"
UNSTABLE = "github:NixOS/nixpkgs/nixos-unstable"
MASTER = "github:NixOS/nixpkgs/master"
ATTR = re.compile(r"^[A-Za-z_][A-Za-z0-9_'-]*$")

Runner = Callable[..., subprocess.CompletedProcess]


def run_command(cmd: list[str], timeout: int = 1800, cwd: Path | None = None,
                env: dict | None = None) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                              check=False, cwd=cwd, env=env)
    except subprocess.TimeoutExpired as e:
        return subprocess.CompletedProcess(cmd, 124, "", f"timed out after {e.timeout}s")


@dataclass
class Candidate:
    pname: str
    cves: list[str]
    drvs: list[str]
    hosts: list[str]
    versions: list[str]


@dataclass
class Outcome:
    note: str
    action: str = "none"  # "none" or "pr"
    source: str = ""
    version: str = ""
    rebuilds: int = 0
    pr: str = ""
    extra: dict = field(default_factory=dict)


def candidates(status: dict, limit: int) -> list[Candidate]:
    """Alerted packages, most urgent first (status.json is already ordered)."""
    by: dict[str, Candidate] = {}
    for f in status["open"]:
        if not f.get("alert"):
            continue
        c = by.setdefault(f["pname"], Candidate(f["pname"], [], [], [], []))
        c.cves.append(f["cve"])
        c.drvs += [d for d in f.get("drvs", []) if d not in c.drvs]
        c.hosts += [h for h in f.get("hosts", []) if h not in c.hosts]
        c.versions += [v for v in f.get("versions", []) if v not in c.versions]
    return list(by.values())[:limit]


class Finder:
    def __init__(self, run: Runner, closures: dict[str, set[str]], whitelist: Path,
                 nixpkgs_rev: str, max_rebuilds: int):
        self.run = run
        self.closures = closures
        self.whitelist = whitelist
        self.locked = f"github:NixOS/nixpkgs/{nixpkgs_rev}"
        self.max_rebuilds = max_rebuilds
        self.env = {**os.environ, "NIXPKGS_ALLOW_UNFREE": "1"}

    def info(self, ref: str, attr: str) -> dict | None:
        """pname, version and drvPath of ref#attr, or None."""
        done = self.run(
            ["nix", "eval", "--impure", "--json", f"{ref}#{attr}", "--apply",
             "p: { pname = p.pname or null; version = p.version or null; drvPath = p.drvPath; }"],
            timeout=900, env=self.env)
        if done.returncode != 0:
            return None
        try:
            return json.loads(done.stdout)
        except json.JSONDecodeError:
            return None

    def still_flagged(self, drv: str, pname: str, cves: list[str]) -> set[str] | None:
        """The CVEs of `cves` vulnix still reports for pname in drv; None if vulnix failed."""
        done = self.run(
            ["nix", "shell", "--inputs-from", str(REPO), "nixpkgs#vulnix", "--command",
             "vulnix", "--json", "--whitelist", str(self.whitelist), drv], timeout=1800)
        if done.returncode not in (0, 2, 3):
            return None
        try:
            items = json.loads(done.stdout or "[]")
        except json.JSONDecodeError:
            return None
        flagged = set()
        for item in items:
            if (item.get("pname") or item.get("name")) == pname:
                flagged |= set(item.get("affected_by", [])) & set(cves)
        return flagged

    def rebuilds(self, drvs: list[str]) -> int | None:
        """Derivations in the hosts' closures that depend on these ones."""
        done = self.run(["nix-store", "--query", "--referrers-closure", *drvs], timeout=600)
        if done.returncode != 0:
            return None
        on_hosts = set().union(*self.closures.values()) if self.closures else set()
        return len((set(done.stdout.split()) & on_hosts) - set(drvs))

    def fixed_in(self, ref: str, c: Candidate, current: dict) -> tuple[bool | None, dict | None]:
        info = self.info(ref, c.pname)
        if not info or info.get("pname") != c.pname:
            return None, None
        if info.get("version") == current.get("version"):
            return False, info  # same version: vulnix would say the same
        # Instantiate: vulnix needs the .drv files in the store, and the
        # drvPath nix eval printed may have come from its cache without them.
        drv = self.run(["nix", "path-info", "--impure", "--derivation", f"{ref}#{c.pname}"],
                       timeout=900, env=self.env)
        if drv.returncode != 0 or not drv.stdout.strip():
            return None, info
        flagged = self.still_flagged(drv.stdout.strip(), c.pname, c.cves)
        if flagged is None:
            return None, info
        return not flagged, info

    def find(self, c: Candidate) -> Outcome:
        if not ATTR.match(c.pname):
            return Outcome("no nixpkgs attribute of this name; needs a person")
        current = self.info(self.locked, c.pname)
        if not current or current.get("pname") != c.pname:
            return Outcome("not a top-level nixpkgs package of this name; needs a person")
        ok, info = self.fixed_in(CHANNEL, c, current)
        if ok:
            return Outcome(f"fixed in nixos-26.05 ({info['version']}); the nightly update brings it",
                           source="nixos-26.05", version=info["version"])
        ok, info = self.fixed_in(UNSTABLE, c, current)
        if ok:
            n = self.rebuilds(c.drvs)
            if n is None:
                return Outcome(f"fixed in nixos-unstable ({info['version']}); could not count rebuilds")
            if n > self.max_rebuilds:
                return Outcome(
                    f"fixed in nixos-unstable ({info['version']}), but taking it would rebuild "
                    f"{n} derivations; wait for nixos-26.05", source="nixos-unstable",
                    version=info["version"], rebuilds=n)
            return Outcome(f"fixed in nixos-unstable ({info['version']})", action="pr",
                           source="unstable", version=info["version"], rebuilds=n,
                           extra={"current": current.get("version")})
        ok, info = self.fixed_in(MASTER, c, current)
        if ok:
            return Outcome(f"fixed in nixpkgs master ({info['version']}), not yet in a channel",
                           source="master", version=info["version"])
        return Outcome("no fixed version in nixpkgs yet")


# --- applying a fix -----------------------------------------------------------


def add_fix(fixes_text: str, pname: str, out: Outcome, cves: list[str], today: dt.date) -> str:
    data = json.loads(fixes_text) if fixes_text.strip() else {"fixes": {}}
    data.setdefault("fixes", {})[pname] = {
        "from": out.source,
        "version": out.version,
        "cves": sorted(cves),
        "since": today.isoformat(),
    }
    data["fixes"] = dict(sorted(data["fixes"].items()))
    return json.dumps(data, indent=2) + "\n"


def registry_entry(pname: str, out: Outcome, cves: list[str], today: dt.date) -> dict:
    current = out.extra.get("current") or "?"
    return {
        "id": f"cve-fix-{pname}",
        "class": "workaround",
        "kind": "overlay-override",
        "site": {"file": FIXES_FILE, "match": f'"{pname}"'},
        "pinned": f"{pname} {out.version} from nixos-unstable (nixos-26.05 has {current})",
        "since": today.isoformat(),
        "reviewed": today.isoformat(),
        "review_by": (today + dt.timedelta(days=REVIEW_DAYS)).isoformat(),
        "reason": (
            f"{', '.join(sorted(cves))} in {pname} {current}, alerted by the daily CVE scan "
            f"(cve-daily.yaml). nixos-unstable's {out.version} is not flagged for them and "
            f"nixos-26.05 does not have it yet. Taking it rebuilds {out.rebuilds} derivation(s) "
            "on the hosts. Opened by scripts/cve_fix.py."
        ),
        "removal": (
            f"Delete the \"{pname}\" entry from {FIXES_FILE} and this registry entry once "
            f"nixos-26.05 has {pname} {out.version} or later (the probe says so)."
        ),
        "upstream": "https://github.com/NixOS/nixpkgs",
        "probe": {"type": "version-at-least", "input": "nixpkgs", "attr": pname,
                  "version": out.version},
    }


def add_registry_entry(text: str, entry: dict) -> str:
    """Append to the hand-formatted registry without reformatting the rest."""
    end = text.rstrip().rfind("]")
    if end < 0 or json.loads(text) is None:
        raise ValueError("pins/registry.json has no pins list")
    block = "\n".join("    " + line for line in json.dumps(entry, indent=2).splitlines())
    head = text[:end].rstrip()
    sep = "," if not head.endswith("[") else ""
    new = f"{head}{sep}\n{block}\n  ]\n}}\n"
    json.loads(new)  # still valid
    return new


def pr_body(pname: str, out: Outcome, c: Candidate, scan_report: str) -> str:
    current = out.extra.get("current") or "?"
    cves = ", ".join(f"[{v}](https://nvd.nist.gov/vuln/detail/{v})" for v in sorted(c.cves))
    return f"""## Why

The daily CVE scan of main alerts on {cves} in `{pname}` {current}, on {', '.join(c.hosts) or 'unknown hosts'}.
nixos-26.05 has no fixed version yet. nixos-unstable has `{pname}` {out.version}, which vulnix
no longer flags for these CVEs.

## What

- Takes `{pname}` from nixos-unstable through `overlays/cve-fixes.json` (the `cve-fixes` overlay).
  Hydra has built it, so only what depends on it rebuilds: {out.rebuilds} derivation(s) in the hosts' closures.
- Registers the override in `pins/registry.json` as `cve-fix-{pname}`. Its probe tells the weekly pins
  run when nixos-26.05 has {out.version}, and the entry is due for review in {REVIEW_DAYS} days.
- Proven before opening: `scripts/cve-scan.sh` against main shows the CVEs as fixed and nothing new failing.

Opened by `scripts/cve_fix.py` from `cve-daily.yaml`. Not auto-merged.

<details><summary>CVE scan of this change</summary>

{scan_report[:30000]}

</details>
"""


def apply_fix(run: Runner, c: Candidate, out: Outcome, repo: str, base_sha: str,
              today: dt.date) -> Outcome:
    branch = f"cve-fix/{c.pname}"
    title = f"fix(cve): take {c.pname} {out.version} from nixos-unstable"
    found = run(["gh", "pr", "list", "--repo", repo, "--head", branch, "--state", "all",
                 "--json", "url,state,title"], timeout=120)
    if found.returncode != 0:
        return Outcome(out.note + "; could not list PRs")
    for pr in json.loads(found.stdout or "[]"):
        if pr["state"] == "OPEN":
            out.pr = pr["url"]
            return out
        if pr["title"] == title:
            # Closed without the fix landing: someone decided against it.
            return Outcome(f"{out.note}; the fix PR {pr['url']} was closed, not reopened")
    with tempfile.TemporaryDirectory() as tmp:
        wt = Path(tmp) / "wt"
        if run(["git", "-C", str(REPO), "worktree", "add", "--quiet", "--detach", str(wt), base_sha],
               timeout=300).returncode != 0:
            return Outcome(out.note + "; could not prepare a branch")
        try:
            fixes = wt / FIXES_FILE
            fixes.write_text(add_fix(fixes.read_text() if fixes.exists() else "", c.pname, out, c.cves, today))
            reg = wt / REGISTRY_FILE
            reg.write_text(add_registry_entry(reg.read_text(), registry_entry(c.pname, out, c.cves, today)))
            msg = f"{title}\n\nFixes {', '.join(sorted(c.cves))}."
            for step in (["git", "-C", str(wt), "add", FIXES_FILE, REGISTRY_FILE],
                         ["git", "-C", str(wt), "commit", "--quiet", "-m", msg]):
                if run(step, timeout=120).returncode != 0:
                    return Outcome(out.note + "; could not commit the fix")
            report, scan_json = Path(tmp) / "report.md", Path(tmp) / "scan.json"
            env = {**os.environ, "CVE_REPORT": str(report), "CVE_JSON": str(scan_json)}
            env.pop("GITHUB_STEP_SUMMARY", None)
            scan = run(["scripts/cve-scan.sh", base_sha], timeout=5400, cwd=wt, env=env)
            try:
                result = json.loads(scan_json.read_text())
            except (OSError, ValueError):
                result = {}
            fixed = {f["cve"] for f in result.get("fixed", []) if f["pname"] == c.pname}
            if scan.returncode != 0 or result.get("failing") or not set(c.cves) <= fixed:
                return Outcome(out.note + "; a swap was tried but did not pass the CVE gate, needs a person")
            # A local branch for --publish to push: the worktree goes, the commit stays.
            if run(["git", "-C", str(wt), "branch", "--force", branch, "HEAD"], timeout=60).returncode != 0:
                return Outcome(out.note + "; could not keep the fix branch")
            out.extra["ready"] = {
                "branch": branch,
                "title": title,
                "body": pr_body(c.pname, out, c, report.read_text() if report.exists() else ""),
            }
            return out
        finally:
            run(["git", "-C", str(REPO), "worktree", "remove", "--force", str(wt)], timeout=120)


def publish(run: Runner, ready: list[dict], repo: str) -> dict[str, str]:
    """Push each proven fix branch and open its PR. Returns {pname: PR URL}."""
    opened = {}
    for r in ready:
        push = run(["git", "-C", str(REPO), "-c", "credential.helper=",
                    "-c", "credential.helper=!gh auth git-credential", "push", "--force",
                    f"https://github.com/{repo}.git", f"refs/heads/{r['branch']}:refs/heads/{r['branch']}"],
                   timeout=300)
        if push.returncode != 0:
            print(f"{r['pname']}: could not push {r['branch']}: {push.stderr.strip()[-300:]}", file=sys.stderr)
            continue
        with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as fh:
            fh.write(r["body"])
        made = run(["gh", "pr", "create", "--repo", repo, "--base", "main", "--head", r["branch"],
                    "--title", r["title"], "--body-file", fh.name], timeout=120)
        Path(fh.name).unlink(missing_ok=True)
        if made.returncode != 0:
            print(f"{r['pname']}: could not open the PR: {made.stderr.strip()[-300:]}", file=sys.stderr)
            continue
        opened[r["pname"]] = made.stdout.strip().splitlines()[-1]
        print(f"{r['pname']}: opened {opened[r['pname']]}")
    return opened


def locked_rev(lock: Path, name: str = "nixpkgs") -> str:
    data = json.loads(lock.read_text())
    return data["nodes"][data["nodes"]["root"]["inputs"][name]]["locked"]["rev"]


def read_closures(directory: Path) -> dict[str, set[str]]:
    return {p.name: set(p.read_text().split()) for p in sorted(directory.iterdir()) if p.is_file()}


def main(argv: list[str] | None = None, run: Runner = run_command) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--status", type=Path)
    ap.add_argument("--closures", type=Path)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--apply", action="store_true", help="prove each cheap fix and keep a local branch for it")
    ap.add_argument("--ready", type=Path, help="with --apply: where to list the proven fixes")
    ap.add_argument("--publish", type=Path, help="push the fixes listed here, open their PRs, add them to --out")
    ap.add_argument("--repo")
    ap.add_argument("--base-sha")
    ap.add_argument("--max-rebuilds", type=int, default=40)
    ap.add_argument("--max-packages", type=int, default=15)
    ap.add_argument("--today", type=dt.date.fromisoformat, default=dt.date.today())
    ap.add_argument("--lock", type=Path, default=REPO / "flake.lock")
    ap.add_argument("--whitelist", type=Path, default=REPO / "pins/vulnix-whitelist.toml")
    args = ap.parse_args(argv)
    if args.publish:
        if not args.repo:
            ap.error("--publish needs --repo")
        try:
            ready = json.loads(args.publish.read_text())
            results = json.loads(args.out.read_text()) if args.out.exists() else {}
        except (OSError, ValueError) as e:
            print(f"error: {e}", file=sys.stderr)
            return 2
        for pname, url in publish(run, ready, args.repo).items():
            results.setdefault(pname, {"note": ""})["pr"] = url
        args.out.write_text(json.dumps(results, indent=1) + "\n")
        return 0
    if not (args.status and args.closures):
        ap.error("--status and --closures are required")
    if args.apply and not (args.repo and args.base_sha and args.ready):
        ap.error("--apply needs --repo, --base-sha and --ready")
    try:
        status = json.loads(args.status.read_text())
        closures = read_closures(args.closures)
        rev = locked_rev(args.lock)
        existing = json.loads((REPO / FIXES_FILE).read_text()).get("fixes", {}) \
            if (REPO / FIXES_FILE).exists() else {}
    except (OSError, ValueError, KeyError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    finder = Finder(run, closures, args.whitelist, rev, args.max_rebuilds)
    results, ready = {}, []
    for c in candidates(status, args.max_packages):
        if c.pname in existing:
            out = Outcome(f"already taken from {existing[c.pname]['from']} in {FIXES_FILE}, "
                          "yet still flagged; needs a person")
        else:
            out = finder.find(c)
            if out.action == "pr" and args.apply:
                out = apply_fix(run, c, out, args.repo, args.base_sha, args.today)
        if "ready" in out.extra:
            ready.append({"pname": c.pname, **out.extra["ready"]})
        results[c.pname] = {"note": out.note, **({"pr": out.pr} if out.pr else {})}
        print(f"{c.pname}: {out.note}{' ' + out.pr if out.pr else ''}")
    args.out.write_text(json.dumps(results, indent=1) + "\n")
    if args.ready:
        args.ready.write_text(json.dumps(ready, indent=1) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
