#!/usr/bin/env python3
"""Check that the sources an ADR quotes still say what the ADR says they say.

The ADR's evidence tables are the source of truth. A row is

    | ID | finding | quote or code | source |

and every "double-quoted" string or `backticked` snippet in the quote column
is a verbatim quote. A manifest next to the ADR (docs/adr/NNNN-sources.json)
holds only what the table cannot: per evidence ID, the URLs (or a local file)
to read and when a human last re-read them. A quote column of `n/a` means the
row has no quotable line (an absence or repository claim).

    adr-sources.py lint  MANIFEST   offline: every evidence ID has a manifest
                                    entry, no entry is orphaned, every row
                                    with quotes has somewhere to look,
                                    no review date is overdue, every decision
                                    cites evidence that exists and every
                                    evidence row is cited (or listed under
                                    `background` with a reason)
    adr-sources.py check MANIFEST   lint, then fetch every source and look for
                                    every quote of the row, and run each
                                    entry's `probes`
    adr-sources.py repo  MANIFEST   lint, then `nix eval` each of the manifest's
                                    `repo_claims` (a host, an option, a key and
                                    the value the ADR says it has)

An entry's `urls` items are a string, or an object {"url": ..., "quotes": [0, 2]}.
A quote may be in any string url (or the `file`); a quote listed under an
object item must be in that URL, so a row about two repositories fails when
one of them loses its line. Indexes count the row's quotes from 0.

A local `file` (such as /proc/config.gz) describes one machine, so an entry
names it with `"host": "<hostname>"` and `check` compares the file only where
socket.gethostname() equals it. Anywhere else, or when the file is absent, the
source is skipped out loud and `check` ends with "N sources unchecked" (exit 0).

A quote must be at least 8 characters once normalised, or finding it proves
nothing. An entry may add `"anchor": {"0": "tcp_ecn"}`: the quote with that
index (from 0) then counts only where the anchor string sits within the 300
normalised characters before it, which pins a generic quote to its setting.

A probe tests what a quote cannot, mainly an absence: strings that must be
`present` or `absent` in a source, optionally within the span `between` two
marker strings. Point one at a floating source (a branch) and the check fails
the day an absence stops being true.

A row fails in one of these ways, and they mean different things:

    wrong    every source is version-pinned and none has the quote, or a
             pinned probe fails: the ADR quotes it wrongly
    drifted  a source is floating ("latest", "stable", a branch) and lacks the
             quote: upstream changed, so re-read it and revisit the ADR
    revisit  an `absent` probe on a floating source found the string: the
             premise of a decision changed

Exit 0 when everything is current, 1 on any finding, 2 on bad usage.
"""

from __future__ import annotations

import argparse
import datetime as dt
import gzip
import json
import os
import re
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from html.parser import HTMLParser
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

# Block tags separate words; inline tags (a, span, code) do not.
BLOCK_TAGS = frozenset(("p", "div", "br", "li", "ul", "ol", "tr", "td", "th",
                        "pre", "section", "table", "h1", "h2", "h3", "h4", "h5", "h6"))
SKIP_TAGS = frozenset(("script", "style"))

# A URL is version-pinned when it names a release tag or a commit.
PINNED_URL = re.compile(
    r"^https://(?:raw\.githubusercontent\.com|github\.com)/[^/]+/[^/]+/"
    r"(?:blob/)?(?:v?\d+(?:\.\d+)+|[0-9a-f]{7,40})/"
    r"|^https://git\.kernel\.org/.*[?&]id=[0-9a-f]{7,40}")
REPO = Path(__file__).resolve().parent.parent
ID_ROW = re.compile(r"^\|\s*([A-Z]\d+)\s*\|")
CITATION = re.compile(r"\b([A-Z]\d{1,2})\b")
USER_AGENT = "nix-config-adr-sources/1 (+https://github.com/alisonjenkins/nix-config)"
FETCH_TRIES = 3
FETCH_TIMEOUT_S = 30
NO_QUOTE = "n/a"
# Shorter quotes ("Default: 2") occur on any page, so finding one proves nothing.
MIN_QUOTE_CHARS = 8
ANCHOR_WINDOW = 300  # normalised characters before a quote in which its anchor must sit

Fetcher = Callable[[str], str]


class _Text(HTMLParser):
    """Collect the visible text of an HTML page."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []
        self._skip = 0

    def handle_starttag(self, tag: str, attrs: Any) -> None:
        del attrs
        if tag in SKIP_TAGS:
            self._skip += 1
        elif tag in BLOCK_TAGS:
            self.parts.append(" ")

    def handle_endtag(self, tag: str) -> None:
        if tag in SKIP_TAGS:
            self._skip = max(0, self._skip - 1)
        elif tag in BLOCK_TAGS:
            self.parts.append(" ")

    def handle_data(self, data: str) -> None:
        if not self._skip:
            self.parts.append(data)


def html_text(page: str) -> str:
    parser = _Text()
    parser.feed(page)
    parser.close()
    return "".join(parser.parts)


def normalise(text: str, markup: bool = False) -> str:
    """Make a quote and a page comparable: drop markup, unify quotes, fold space."""
    if markup:
        text = html_text(text)
    for fancy, plain in (("‘", "'"), ("’", "'"),
                         ("“", '"'), ("”", '"'),
                         (" ", " "), ("`", "")):
        text = text.replace(fancy, plain)
    # A quote wrapped across source comment lines has the comment leader mid-quote.
    text = re.sub(r"(?m)^\s*(?:\*|//|#)\s?", "", text)
    return re.sub(r"\s+", " ", text).strip()


def split_cells(line: str) -> list[str]:
    """Split a table row on pipes that are not inside a backtick span."""
    cells, cur, in_code = [], [], False
    text = line.strip().strip("|")
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "\\" and text[i + 1:i + 2] == "|":
            cur.append("|")  # markdown's escaped pipe is a literal pipe
            i += 2
            continue
        if ch == "`":
            in_code = not in_code
        if ch == "|" and not in_code:
            cells.append("".join(cur).strip())
            cur = []
        else:
            cur.append(ch)
        i += 1
    cells.append("".join(cur).strip())
    return cells


def quotes(cell: str) -> list[str]:
    """Verbatim strings in a quote cell: "double quoted" or `backticked`.

    Scans left to right so a quote that contains backticks, or a snippet that
    contains double quotes, is taken whole by whichever opens first.
    """
    found: list[str] = []
    i = 0
    while i < len(cell):
        if cell[i] in '"`':
            end = cell.find(cell[i], i + 1)
            if end == -1:
                raise ValueError(f"unterminated {cell[i]} at offset {i} in {cell!r}")
            found.append(cell[i + 1:end])
            i = end + 1
        else:
            i += 1
    return [q for q in found if q.strip()]


def adr_rows(adr_text: str) -> dict[str, list[str]]:
    """Map each evidence ID to the verbatim strings its row quotes."""
    rows: dict[str, list[str]] = {}
    for line in adr_text.splitlines():
        match = ID_ROW.match(line)
        if not match:
            continue
        if match.group(1) in rows:
            raise ValueError(f"{match.group(1)}: evidence ID appears more than once")
        cells = split_cells(line)
        quote_cell = cells[2] if len(cells) > 2 else ""
        try:
            rows[match.group(1)] = [] if quote_cell == NO_QUOTE else quotes(quote_cell)
        except ValueError as err:
            raise ValueError(f"{match.group(1)}: {err}") from err
    return rows


def is_floating(entry: dict[str, Any], url: str) -> bool:
    if "floating" in entry:
        return bool(entry["floating"])
    return not PINNED_URL.match(url)


def url_of(item: str | dict[str, Any]) -> str:
    """The URL of a `urls` item, which is a string or {"url": ..., "quotes": [...]}."""
    return item if isinstance(item, str) else str(item.get("url", ""))


def entry_urls(entry: dict[str, Any]) -> list[str]:
    return [url_of(item) for item in entry.get("urls", [])]


def url_problems(ident: str, entry: dict[str, Any], quote_count: int) -> list[str]:
    """Lint the `urls` items: object form well-formed, every quote has a place to look."""
    problems = []
    assigned: set[int] = set()
    has_open_source = "file" in entry
    for item in entry.get("urls", []):
        if isinstance(item, str):
            has_open_source = True
            continue
        url = url_of(item)
        if not url:
            problems.append(f"{ident}: urls item without a url")
            continue
        indexes = item.get("quotes")
        if (not isinstance(indexes, list) or not indexes
                or not all(isinstance(i, int) and not isinstance(i, bool) for i in indexes)):
            problems.append(f"{ident}: {url}: quotes must be a list of row quote indexes")
            continue
        for index in indexes:
            if not 0 <= index < quote_count:
                problems.append(f"{ident}: {url}: quote index {index} is out of range")
            else:
                assigned.add(index)
    if not has_open_source:
        for index in sorted(set(range(quote_count)) - assigned):
            problems.append(f"{ident}: quote index {index} is assigned to no url "
                            f"and no string url or file is listed")
    return problems


def probe_problems(ident: str, probes: list[dict[str, Any]]) -> list[str]:
    problems = []
    for probe in probes:
        label = f"{ident}: probe {probe.get('url', '?')}"
        if not probe.get("url"):
            problems.append(f"{ident}: probe without a url")
        if not (probe.get("present") or probe.get("absent")):
            problems.append(f"{label}: give present or absent strings")
        if "between" in probe and len(probe["between"]) != 2:
            problems.append(f"{label}: between needs a start and an end string")
    return problems


def decision_items(adr_text: str) -> list[str]:
    """The numbered items under '## Decision', each with its continuation lines."""
    section = re.search(r"^## Decision\n(.*?)(?=^## |\Z)", adr_text, re.S | re.M)
    if not section:
        return []
    items = re.split(r"(?m)^(?=\d+\. )", section.group(1))
    return [item.strip() for item in items if re.match(r"\d+\. ", item)]


def decision_problems(adr_text: str, rows: dict[str, list[str]],
                      background: dict[str, str] | None = None) -> list[str]:
    """Every decision cites evidence that exists; every evidence row is cited.

    Cited means named outside the evidence tables, so a table row cannot cite
    itself. A decision with no citation is advice with no support. Evidence
    that is deliberately kept as reference, with no decision resting on it,
    is listed with a reason under `background` in the manifest.
    """
    background = background or {}
    problems = []
    items = decision_items(adr_text)
    if not items:
        problems.append("no numbered items under '## Decision'; "
                        "a renamed heading would otherwise skip this lint")
    for item in items:
        number = item.split(".", 1)[0]
        cited = set(CITATION.findall(item))
        if not cited:
            problems.append(f"decision {number}: cites no evidence ID")
        for ident in sorted(cited - set(rows)):
            problems.append(f"decision {number}: cites {ident}, which is not in the ADR")
    prose = "\n".join(line for line in adr_text.splitlines()
                      if not ID_ROW.match(line))
    cited_in_prose = set(CITATION.findall(prose))
    for ident in sorted(set(rows) - cited_in_prose - set(background)):
        problems.append(f"{ident}: evidence no decision or finding cites")
    for ident, reason in background.items():
        if ident not in rows:
            problems.append(f"{ident}: background entry is not in the ADR")
        elif ident in cited_in_prose:
            problems.append(f"{ident}: background entry is now cited; remove it")
        if not reason.strip():
            problems.append(f"{ident}: background needs a reason")
    return problems


def lint(manifest: dict[str, Any], rows: dict[str, list[str]],
         today: dt.date) -> list[str]:
    problems: list[str] = []
    limits = manifest.get("max_review_days", {})
    entries = manifest["sources"]
    for ident in sorted(set(rows) - set(entries)):
        problems.append(f"{ident}: in the ADR, not in the manifest")
    for ident in sorted(set(entries) - set(rows)):
        problems.append(f"{ident}: in the manifest, not in the ADR")
    for ident, entry in entries.items():
        if ident not in rows:
            continue
        problems += probe_problems(ident, entry.get("probes", []))
        for want in rows[ident]:
            if len(normalise(want)) < MIN_QUOTE_CHARS:
                problems.append(f"{ident}: quote {want!r} is too short to prove anything")
        problems += anchor_problems(ident, entry, len(rows[ident]))
        has_quotes = bool(rows[ident])
        if "none" in entry:
            if not entry["none"].strip():
                problems.append(f"{ident}: none needs a reason")
            if has_quotes:
                problems.append(f"{ident}: marked none but the ADR row quotes strings")
        else:
            if not has_quotes:
                problems.append(f"{ident}: the ADR row has no quotes; give a none reason")
            if not (entry.get("urls") or entry.get("file")):
                problems.append(f"{ident}: give urls or a file to read")
            problems += url_problems(ident, entry, len(rows[ident]))
        problems += review_problems(ident, entry, limits, today)
    return problems


def review_problems(ident: str, entry: dict[str, Any], limits: dict[str, int],
                    today: dt.date) -> list[str]:
    """Is the human re-read recent enough for every kind of source the entry reads?"""
    if "reviewed" not in entry:
        return [f"{ident}: missing reviewed"]
    try:
        age = (today - dt.date.fromisoformat(entry["reviewed"])).days
    except (TypeError, ValueError):
        return [f"{ident}: reviewed {entry['reviewed']!r} is not an ISO date"]
    kinds = {"floating" if is_floating(entry, u) else "pinned" for u in entry_urls(entry)}
    kinds |= {"floating" if is_floating(p, p["url"]) else "pinned"
              for p in entry.get("probes", []) if p.get("url")}
    problems = []
    for kind in sorted(kinds or {"pinned"}):
        if kind in limits and age > limits[kind]:
            problems.append(
                f"{ident}: reviewed {entry['reviewed']}, {age} days ago, "
                f"over the {limits[kind]}-day limit for {kind} sources")
    return problems


class _DropAuthOnRedirect(urllib.request.HTTPRedirectHandler):
    """urllib copies every header to a redirect target; keep the token on its host."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # type: ignore[no-untyped-def]
        new = super().redirect_request(req, fp, code, msg, headers, newurl)
        if new is not None and urlsplit(new.full_url).netloc != urlsplit(req.full_url).netloc:
            new.remove_header("Authorization")
        return new


_OPENER = urllib.request.build_opener(_DropAuthOnRedirect)


def transient(err: OSError) -> bool:
    """Worth retrying: a timeout, a dropped connection, a 429 or a 5xx.

    A 404 or 403 will not change in seconds, so retrying only delays the finding.
    """
    if isinstance(err, urllib.error.HTTPError):
        return err.code == 429 or err.code >= 500
    return True


class RateLimited(OSError):
    """The API refused because the hourly quota is spent; waiting seconds will not help."""


def rate_limited(err: OSError) -> bool:
    return (isinstance(err, urllib.error.HTTPError) and err.code == 403
            and err.headers is not None
            and err.headers.get("X-RateLimit-Remaining") == "0")


def fetch(where: str, opener: Any = _OPENER) -> str:
    """Return the text at a URL or local path; raise OSError when it cannot be had."""
    if "://" not in where:
        raw = Path(where).read_bytes()
        return gzip.decompress(raw).decode() if where.endswith(".gz") else raw.decode()
    headers = {"User-Agent": USER_AGENT}
    token = os.environ.get("GITHUB_TOKEN")
    if token and where.startswith("https://api.github.com/"):
        headers["Authorization"] = f"Bearer {token}"  # 60 requests an hour without
    req = urllib.request.Request(where, headers=headers)
    for attempt in range(FETCH_TRIES):
        try:
            with opener.open(req, timeout=FETCH_TIMEOUT_S) as resp:
                body = resp.read().decode("utf-8", errors="replace")
                kind = resp.headers.get("Content-Type", "")
                return html_text(body) if "html" in kind else body
        except OSError as err:
            if rate_limited(err):
                raise RateLimited(f"{where}: {err}") from err
            if attempt == FETCH_TRIES - 1 or not transient(err):
                raise OSError(f"{where}: {err}") from err
            time.sleep(2 ** attempt)
    raise AssertionError("unreachable: the last attempt returns or raises")


def check(manifest: dict[str, Any], rows: dict[str, list[str]],
          fetcher: Fetcher = fetch, unchecked: list[str] | None = None,
          hostname: str | None = None) -> list[str]:
    """Fetch each distinct source once; every quote must be in one of its row's.

    A source that cannot be read here (an absent local file, a file for another
    host) is skipped out loud and appended to `unchecked`, not failed: it is
    expected off the machine it describes.
    """
    findings: list[str] = []
    pages: dict[str, str | None] = {}
    unchecked = unchecked if unchecked is not None else []
    hostname = socket.gethostname() if hostname is None else hostname

    def page(where: str) -> str | None:
        if where not in pages:
            try:
                pages[where] = normalise(fetcher(where))
            except FileNotFoundError:
                pages[where] = None
                print(f"skipped {where}: not present on this machine")
                unchecked.append(where)
            except RateLimited:
                pages[where] = None
                findings.append(f"rate limited: {where}")
            except OSError as err:
                pages[where] = None
                findings.append(f"unreachable: {err}")
        return pages[where]

    for ident, entry in manifest["sources"].items():
        findings += probe_findings(ident, entry, page)
        if "none" in entry or not rows.get(ident):
            continue
        if "file" in entry and entry.get("host") != hostname:
            print(f"skipped {entry['file']} for {ident}: file source is host-specific "
                  f"(entry host {entry.get('host')!r}, this host {hostname!r})")
            unchecked.append(f"{ident}: {entry['file']}")
            entry = {k: v for k, v in entry.items() if k != "file"}
        findings += quote_findings(ident, entry, rows[ident], page)
    return findings


def quote_in(text: str, needle: str, anchor: str | None) -> bool:
    """Is the quote in the page, and with an anchor, within ANCHOR_WINDOW characters before one?"""
    if anchor is None:
        return needle in text
    start = text.find(needle)
    while start != -1:
        if anchor in text[max(0, start - ANCHOR_WINDOW):start]:
            return True
        start = text.find(needle, start + 1)
    return False


def anchor_problems(ident: str, entry: dict[str, Any], quote_count: int) -> list[str]:
    problems = []
    for key, value in entry.get("anchor", {}).items():
        if not key.isdigit():
            problems.append(f"{ident}: anchor key {key!r} is not a quote index")
        elif int(key) >= quote_count:
            problems.append(f"{ident}: anchor for quote index {key} is out of range")
        elif not isinstance(value, str) or not normalise(value):
            problems.append(f"{ident}: anchor for quote index {key} needs a non-empty string")
    return problems


def quote_findings(ident: str, entry: dict[str, Any], wanted: list[str],
                   page: Callable[[str], str | None]) -> list[str]:
    """Look for each quote of a row.

    A quote assigned to URLs (`quotes` on an object item) must be in every one
    of them. Any other quote may be in any string url or the file.
    """
    findings: list[str] = []
    open_sources = [i for i in entry.get("urls", []) if isinstance(i, str)]
    open_sources += [entry["file"]] if "file" in entry else []
    for index, want in enumerate(wanted):
        needle = normalise(want)
        raw_anchor = entry.get("anchor", {}).get(str(index))
        anchor = normalise(raw_anchor) if raw_anchor else None
        with_anchor = f" (with anchor {raw_anchor!r})" if anchor else ""
        owners = [url_of(i) for i in entry.get("urls", [])
                  if isinstance(i, dict) and index in i.get("quotes", [])]
        if owners:
            for where in owners:
                text = page(where)
                if text is not None and not quote_in(text, needle, anchor):
                    verdict = "drifted" if is_floating(entry, where) else "wrong"
                    findings.append(
                        f"{ident}: {verdict}: {want!r}{with_anchor} not in {where}")
            continue
        readable = [(w, t) for w in open_sources if (t := page(w)) is not None]
        if not readable:
            continue
        if not any(quote_in(t, needle, anchor) for _, t in readable):
            pinned = all(not is_floating(entry, w) for w in open_sources)
            names = ", ".join(w for w, _ in readable)
            findings.append(f"{ident}: {'wrong' if pinned else 'drifted'}: "
                            f"{want!r}{with_anchor} not in {names}")
    return findings


def probe_findings(ident: str, entry: dict[str, Any],
                   page: Callable[[str], str | None]) -> list[str]:
    """Run an entry's probes: strings that must be present or must be absent.

    A probe is how an absence claim ("no tcp_prague in net/ipv4") is tested.
    On a floating source a broken absence means the premise changed and the
    decision resting on it needs revisiting; on a pinned one the ADR is wrong.
    `between` narrows the text to the span from a start string to the next end
    string, and a span that is not found is itself a finding, so a moved
    marker cannot turn a probe into a silent pass.
    """
    findings = []
    for probe in entry.get("probes", []):
        url = probe["url"]
        text = page(url)
        if text is None:
            continue
        floating = is_floating(probe, url)
        if "between" in probe:
            start, end = (normalise(s) for s in probe["between"])
            begin = text.find(start)
            stop = text.find(end, begin + len(start)) if begin != -1 else -1
            if begin == -1 or stop == -1:
                findings.append(f"{ident}: probe: span {probe['between']!r} not in {url}")
                continue
            text = text[begin:stop]
        for want in probe.get("present", []):
            if normalise(want) not in text:
                verdict = "drifted" if floating else "wrong"
                findings.append(f"{ident}: {verdict}: probe expects {want!r} in {url}")
        for unwanted in probe.get("absent", []):
            if normalise(unwanted) in text:
                verdict = "revisit" if floating else "wrong"
                findings.append(f"{ident}: {verdict}: probe expects {unwanted!r} "
                                f"absent from {url}, but it is there")
    return findings


def nix_eval(host: str, option: str) -> Any:
    """Evaluate one NixOS option of a host in this flake, as JSON."""
    attr = f".#nixosConfigurations.{host}.config.{option}"
    proc = subprocess.run(["nix", "eval", "--json", attr], cwd=REPO,
                          capture_output=True, text=True, check=False)
    if proc.returncode:
        raise OSError(f"nix eval {attr} failed: {proc.stderr.strip()[-300:]}")
    return json.loads(proc.stdout)


def repo_problems(claims: list[dict[str, Any]]) -> list[str]:
    problems = []
    for n, claim in enumerate(claims, 1):
        for field in ("claim", "host", "option", "equals"):
            if field not in claim:
                problems.append(f"repo claim {n}: missing {field}")
    return problems


def repo_findings(claims: list[dict[str, Any]],
                  evaluator: Callable[[str, str], Any] = nix_eval) -> list[str]:
    """Compare what the ADR says this repository sets with what it evaluates to.

    The ADR's context describes the fleet as it is today. When a decision lands
    or a module changes, the evaluated value moves and the claim fails, which
    is the prompt to update the ADR.
    """
    findings = []
    values: dict[tuple[str, str], Any] = {}
    for claim in claims:
        where = (claim["host"], claim["option"])
        if where not in values:
            try:
                values[where] = evaluator(*where)
            except OSError as err:
                findings.append(f"repo: unevaluable: {err}")
                values[where] = None
        value = values[where]
        if value is None:
            continue
        key = claim.get("key")
        got = value.get(key) if key and isinstance(value, dict) else value
        if got != claim["equals"]:
            findings.append(
                f"repo: {claim['claim']}: {claim['host']} {claim['option']}"
                f"{'[' + key + ']' if key else ''} is {got!r}, "
                f"the ADR says {claim['equals']!r}")
    return findings


def load(path: Path) -> tuple[dict[str, Any], dict[str, list[str]], str]:
    manifest = json.loads(path.read_text())
    adr = (path.parent / manifest["adr"]).read_text()
    return manifest, adr_rows(adr), adr


def main(argv: list[str] | None = None, fetcher: Fetcher = fetch,
         evaluator: Callable[[str, str], Any] = nix_eval) -> int:
    parser = argparse.ArgumentParser(description=(__doc__ or "").split("\n")[0])
    parser.add_argument("command", choices=("lint", "check", "repo"))
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--today", type=dt.date.fromisoformat,
                        default=dt.datetime.now(dt.timezone.utc).date())
    args = parser.parse_args(argv)
    try:
        manifest, rows, adr = load(args.manifest)
    except ValueError as err:
        print(f"{args.manifest.name}: {err}")
        return 1
    claims = manifest.get("repo_claims", [])
    findings = lint(manifest, rows, args.today)
    findings += decision_problems(adr, rows, manifest.get("background"))
    findings += repo_problems(claims)
    unchecked: list[str] = []
    if args.command == "check":
        findings += check(manifest, rows, fetcher, unchecked)
    if args.command == "repo":
        findings += repo_findings(claims, evaluator)
    for line in findings:
        print(line)
    if not findings:
        print(f"{args.manifest.name}: {len(rows)} evidence rows, "
              f"{len(claims)} repo claims current")
    if unchecked:
        print(f"{len(unchecked)} sources unchecked")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
