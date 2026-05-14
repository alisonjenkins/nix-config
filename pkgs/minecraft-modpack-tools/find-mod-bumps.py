#!/usr/bin/env python3
"""Find newer compatible mod versions for a NeoForge modpack.

Algorithm (per the dep-graph leaf-first walk the user requested):
  1. Read the existing mod set:
       - arkana-mods.nix (CurseForge entries, by projectID/fileID)
       - extras.nix (replacements override arkana entries; skipped/disabled
         remove them entirely)
       - overlays.nix (CurseForge entries via the `curseforge` helper +
         Modrinth entries via the `modrinth` helper)
  2. Walk the built server tree's mods/ to map filename -> modId via
     each jar's META-INF/neoforge.mods.toml, and build:
       - current_version[modId]
       - deps[modId] = [(dep_modId, versionRange, type), ...]
       - source[modId] = ("curseforge", projectID) | ("modrinth", projectId)
  3. Reverse-edge the graph -> dependents[modId].
  4. Topo-sort leaves first (no dependents -> first).
  5. For each modId in that order, query the appropriate source
     (cfwidget for CF, api.modrinth.com for Modrinth) for all
     1.21.1+NeoForge versions; walk newest-first; for each candidate:
       a. download jar, parse its mods.toml for declared deps
       b. for each dep: planned version = bumped[dep] or current[dep];
          fail if dep version not in candidate's required range
       c. for each existing dependent of this mod: fail if candidate
          version not in dependent's existing required range
       d. first candidate that passes both = winner; record bump.
  6. Print the bump table + ready-to-paste replacement entries split
     by destination file (extras.nix vs overlays.nix vs in-place
     overlays Modrinth lines).

Generic — no Arkana-specific assumptions beyond default file paths
(override with --mods-nix / --extras-nix / --overlays-nix). Use from
any modpack derivation that follows the same nix layout.

Usage:
  find-mod-bumps /path/to/server-tree
  find-mod-bumps /path/to/server-tree --only ars_nouveau,bookshelf
  find-mod-bumps /path/to/server-tree --skip glitchcore,apotheosis
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from collections import defaultdict
from pathlib import Path
from typing import Optional

try:
    import tomllib  # type: ignore[import-not-found]  # Python 3.11+ stdlib
except ImportError:
    import tomli as tomllib  # type: ignore


# ---------------------------------------------------------------------------
# mods.toml parsing — same shape as dep-tree.py for future shared-module
# extraction.
# ---------------------------------------------------------------------------

def parse_modstoml_bytes(raw: bytes):
    """Parse a NeoForge mods.toml. Returns (mods_list, deps_dict) or
    (None, None) on parse failure. Triple-quoted descriptions break
    tomllib if they contain control chars; we strip them first."""
    text = raw.decode("utf-8", errors="replace")
    text = re.sub(r"description\s*=\s*'''.*?'''", "description=''", text, flags=re.S)
    try:
        d = tomllib.loads(text)
    except tomllib.TOMLDecodeError:
        return None, None
    return d.get("mods", []), d.get("dependencies", {})


def parse_jar_mods(jar_path: Path):
    """Return {modId: {version, deps}} extracted from one jar (and its
    JIJ children). deps is [(dep_modId, versionRange, type), ...]."""
    out = {}
    if not jar_path.exists():
        return out
    try:
        zf = zipfile.ZipFile(jar_path)
    except zipfile.BadZipFile:
        return out
    with zf:
        for name in ("META-INF/neoforge.mods.toml", "META-INF/mods.toml"):
            if name in zf.namelist():
                mods, deps = parse_modstoml_bytes(zf.read(name))
                if mods is None:
                    break
                # `deps` is `Optional[Dict]` per pyright; guard explicitly so
                # parse failures upstream don't blow up here.
                deps_dict = deps or {}
                for m in mods:
                    mid = m.get("modId")
                    if not mid:
                        continue
                    ver = m.get("version", "")
                    deplist = []
                    raw = deps_dict.get(mid, [])
                    if isinstance(raw, dict):
                        raw = [raw]
                    for d in raw:
                        deplist.append((
                            d.get("modId", ""),
                            d.get("versionRange", ""),
                            d.get("type", "required"),
                        ))
                    out[mid] = {"version": ver, "deps": deplist}
                break
    return out


# ---------------------------------------------------------------------------
# Maven-style version-range checks (same syntax as dep-tree.py).
# ---------------------------------------------------------------------------

def parse_version_range(spec: str):
    if not spec or spec == "*":
        return None
    m = re.match(r"^\s*([\[(])\s*([^,\]\)]*)\s*,\s*([^,\]\)]*)\s*([\])])\s*$", spec)
    if not m:
        return ("[", spec.strip(), "", ")")
    return (m.group(1), m.group(2), m.group(3), m.group(4))


def version_key(v: str):
    v = (v or "").strip().lstrip("v")
    v = re.sub(r"^(?:Neo)?Forge-", "", v, flags=re.I)
    v = re.sub(r"^1\.21(?:\.\d+)?-", "", v)
    head = re.match(r"^(\d+(?:\.\d+)*)", v)
    if not head:
        return (0,)
    parts = []
    for p in head.group(1).split("."):
        try:
            parts.append(int(p))
        except ValueError:
            parts.append(0)
    return tuple(parts)


def in_range(version: str, spec: str) -> bool:
    if not version:
        return True
    pr = parse_version_range(spec)
    if pr is None:
        return True
    lo_b, lo, hi, hi_b = pr
    vk = version_key(version)
    if lo:
        lk = version_key(lo)
        if (lo_b == "[" and vk < lk) or (lo_b == "(" and vk <= lk):
            return False
    if hi:
        hk = version_key(hi)
        if (hi_b == "]" and vk > hk) or (hi_b == ")" and vk >= hk):
            return False
    return True


# ---------------------------------------------------------------------------
# Pack-state parsers. Two source files now: arkana-mods.nix + extras.nix
# (CurseForge), and overlays.nix (Modrinth + CurseForge via different
# helpers). State is keyed by filename -> {source, ids, dest_file} so the
# downstream bump walk can dispatch to the right API and emit the right
# replacement-entry format.
# ---------------------------------------------------------------------------

# arkana-mods.nix entry shape: 4 fields in fixed order, ending in filename.
ENTRY_RE = re.compile(
    r"projectID\s*=\s*(\d+)\s*;\s*"
    r"fileID\s*=\s*(\d+)\s*;\s*"
    r"required\s*=\s*\w+\s*;\s*"
    r"filename\s*=\s*\"([^\"]+)\"",
    re.S,
)
# extras.nix replacements have orig + new IDs.
REPLACE_RE = re.compile(
    r"origProjectID\s*=\s*(\d+)\s*;\s*"
    r"origFileID\s*=\s*(\d+)\s*;\s*"
    r"projectID\s*=\s*(\d+)\s*;\s*"
    r"fileID\s*=\s*(\d+)\s*;\s*"
    r"required\s*=\s*\w+\s*;\s*"
    r"filename\s*=\s*\"([^\"]+)\"",
    re.S,
)
# extras.nix skipped/disabled — no fileID for "all versions" wildcard.
SKIPDIS_RE = re.compile(r"projectID\s*=\s*(\d+)\s*;\s*fileID\s*=\s*(?:(\d+)|null)")

# overlays.nix Modrinth entries — `modrinth "PROJECT" "VERSION" "FILENAME"`.
# Filename in the helper call may differ slightly from the on-disk
# filename when the Nix template uses `${...}` interpolation, but for our
# pack the two match exactly. We match the on-disk filename via the
# `filename       = "..."` line near the helper invocation.
OVERLAY_MODRINTH_RE = re.compile(
    r"filename\s*=\s*\"([^\"]+)\"\s*;[\s\S]{0,400}?"
    r"modrinth\s+\"([A-Za-z0-9]+)\"\s+\"([A-Za-z0-9]+)\"",
    re.S,
)
# overlays.nix CurseForge entries — `projectID = N; fileID = M; jar =
# curseforge ...`. No `required = ...` field (entries here aren't part of
# the manifest required-list semantics; that's the modpack's concern).
OVERLAY_CURSEFORGE_RE = re.compile(
    r"filename\s*=\s*\"([^\"]+)\"[\s\S]{0,300}?"
    r"projectID\s*=\s*(\d+)\s*;\s*"
    r"fileID\s*=\s*(\d+)\s*;\s*"
    r"jar\s*=\s*curseforge",
    re.S,
)


def load_pack_state(mods_nix: Path, extras_nix: Path, overlays_nix: Optional[Path]):
    """Build the merged effective mod-source map.

    Returns {filename: entry} where each entry has at minimum:
        source       — "curseforge" or "modrinth"
        dest_file    — "extras.nix" (replacement format) or
                       "overlays.nix" (modrinth helper / curseforge helper)
        For curseforge:  project_id, file_id
        For modrinth:    project_id, version_id

    Resolution order: arkana base -> extras replacements override by
    (origProjectID, origFileID) -> extras skipped/disabled remove ->
    overlays additive (no overlap with arkana set in practice).
    """
    state = {}

    # 1) arkana-mods.nix (CurseForge, dest extras.nix when bumped)
    arkana_text = mods_nix.read_text()
    by_orig = {}
    for m in ENTRY_RE.finditer(arkana_text):
        pid, fid, fname = int(m.group(1)), int(m.group(2)), m.group(3)
        by_orig[(pid, fid)] = fname

    # 2) extras.nix replacements override arkana entries by orig key.
    extras_text = extras_nix.read_text() if extras_nix.exists() else ""
    if extras_text:
        repl_start = extras_text.find("replacements = [")
        if repl_start != -1:
            repl_end = extras_text.find("];", repl_start)
            for m in REPLACE_RE.finditer(extras_text[repl_start:repl_end]):
                opid, ofid = int(m.group(1)), int(m.group(2))
                npid, nfid, fname = int(m.group(3)), int(m.group(4)), m.group(5)
                by_orig.pop((opid, ofid), None)
                by_orig[(npid, nfid)] = fname

        # 3) extras skipped/disabled — drop from working set.
        for section in ("skipped = [", "disabled = ["):
            s = extras_text.find(section)
            if s == -1:
                continue
            e = extras_text.find("];", s)
            for m in SKIPDIS_RE.finditer(extras_text[s:e]):
                pid = int(m.group(1))
                fid = int(m.group(2)) if m.group(2) else None
                if fid is None:
                    for k in list(by_orig.keys()):
                        if k[0] == pid:
                            del by_orig[k]
                else:
                    by_orig.pop((pid, fid), None)

    for (pid, fid), fname in by_orig.items():
        state[fname] = {
            "source": "curseforge",
            "dest_file": "extras.nix",
            "project_id": pid,
            "file_id": fid,
        }

    # 4) overlays.nix entries — both helper families.
    if overlays_nix and overlays_nix.exists():
        ov_text = overlays_nix.read_text()
        for m in OVERLAY_MODRINTH_RE.finditer(ov_text):
            fname, project_id, version_id = m.group(1), m.group(2), m.group(3)
            state[fname] = {
                "source": "modrinth",
                "dest_file": "overlays.nix",
                "project_id": project_id,
                "version_id": version_id,
            }
        for m in OVERLAY_CURSEFORGE_RE.finditer(ov_text):
            fname, pid, fid = m.group(1), int(m.group(2)), int(m.group(3))
            # Don't clobber a Modrinth match for the same filename; first
            # match wins. (No overlap in practice but defensive.)
            state.setdefault(fname, {
                "source": "curseforge",
                "dest_file": "overlays.nix",
                "project_id": pid,
                "file_id": fid,
            })

    return state


# ---------------------------------------------------------------------------
# HTTP + cache. cfwidget's WAF blocks default urllib UA; pretending to be
# curl gets through. Modrinth API has no such friction but we use the same
# wrapper for parity.
# ---------------------------------------------------------------------------

CACHE_DIR = Path(os.environ.get("FIND_BUMPS_CACHE", "/tmp/find-mod-bumps-cache"))


def http_get(url: str, retries: int = 3, sleep: float = 1.0) -> bytes:
    last = None
    req = urllib.request.Request(url, headers={"User-Agent": "curl/8"})
    for _ in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.read()
        except (urllib.error.URLError, urllib.error.HTTPError) as e:
            last = e
            time.sleep(sleep)
    raise RuntimeError(f"GET {url}: {last}")


def cfwidget_files(project_id: int):
    """Return list of {id, name, type, versions} for one CF project,
    sorted newest-first, filtered to 1.21.1 + NeoForge release/beta."""
    cache = CACHE_DIR / f"cfwidget-{project_id}.json"
    if cache.exists() and (time.time() - cache.stat().st_mtime) < 3600:
        d = json.loads(cache.read_text())
    else:
        try:
            raw = http_get(f"https://api.cfwidget.com/{project_id}")
            d = json.loads(raw)
        except Exception:
            return []
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        cache.write_text(json.dumps(d))
    files = []
    for f in d.get("files", []):
        v = f.get("versions", [])
        if "1.21.1" in v and "NeoForge" in v and f.get("type") in ("release", "beta"):
            files.append(f)
    files.sort(key=lambda x: x["id"], reverse=True)
    return files


def modrinth_versions(project_id: str):
    """Return list of Modrinth version dicts for the project, sorted
    newest-first, filtered to 1.21.1 + neoforge. Each has at least:
        id            (Modrinth version_id)
        version_number
        files[0].url, files[0].filename, files[0].hashes.sha1
        date_published
    """
    cache = CACHE_DIR / f"modrinth-{project_id}.json"
    if cache.exists() and (time.time() - cache.stat().st_mtime) < 3600:
        d = json.loads(cache.read_text())
    else:
        # API supports JSON-array filter params; URL-encode them so the
        # square brackets and quotes don't get mangled.
        gv = urllib.parse.quote('["1.21.1"]')
        ld = urllib.parse.quote('["neoforge"]')
        url = f"https://api.modrinth.com/v2/project/{project_id}/version?game_versions={gv}&loaders={ld}"
        try:
            raw = http_get(url)
            d = json.loads(raw)
        except Exception:
            return []
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        cache.write_text(json.dumps(d))
    # API returns newest-first when sorted by date_published, but not
    # guaranteed; sort defensively.
    d.sort(key=lambda v: v.get("date_published", ""), reverse=True)
    return d


def fetch_jar_curseforge(file_id: int, name: str) -> Path:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    out = CACHE_DIR / f"cf-{file_id}-{name}"
    if out.exists() and out.stat().st_size > 0:
        return out
    pre, suf = file_id // 1000, file_id % 1000
    url = f"https://mediafilez.forgecdn.net/files/{pre}/{suf}/{name}"
    try:
        out.write_bytes(http_get(url))
    except Exception:
        pass
    return out


def fetch_jar_modrinth(version_id: str, file_url: str, name: str) -> Path:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    out = CACHE_DIR / f"mr-{version_id}-{name}"
    if out.exists() and out.stat().st_size > 0:
        return out
    try:
        out.write_bytes(http_get(file_url))
    except Exception:
        pass
    return out


# ---------------------------------------------------------------------------
# Toposort — leaves (no dependents) first. Cycles fall through in arbitrary
# order with a note; we don't need strict ordering, just a hint.
# ---------------------------------------------------------------------------

def toposort_leaves_first(modids, dependents):
    remaining = set(modids)
    ordered = []
    while remaining:
        leaves = [m for m in remaining if not (dependents.get(m, set()) & remaining)]
        if not leaves:
            ordered.extend(sorted(remaining))
            break
        leaves.sort()
        ordered.extend(leaves)
        for m in leaves:
            remaining.discard(m)
    return ordered


# ---------------------------------------------------------------------------
# Per-source candidate enumeration. Returns a list of dicts with the
# uniform shape:
#   {
#     "source":     "curseforge"|"modrinth",
#     "id":         <opaque id used by fetch + dedupe>,
#     "name":       jar filename,
#     "version":    semver-ish version string (filled lazily),
#     "fetch":      callable -> Path returning local jar
#   }
# Newest-first.
# ---------------------------------------------------------------------------

def enumerate_candidates(entry: dict):
    if entry["source"] == "curseforge":
        files = cfwidget_files(entry["project_id"])
        out = []
        for f in files:
            out.append({
                "source": "curseforge",
                "id": f["id"],
                "name": f["name"],
                "version": None,  # parsed from jar later
                "fetch": (lambda fid=f["id"], nm=f["name"]: fetch_jar_curseforge(fid, nm)),
            })
        return out
    if entry["source"] == "modrinth":
        versions = modrinth_versions(entry["project_id"])
        out = []
        for v in versions:
            files = v.get("files", [])
            if not files:
                continue
            f0 = files[0]
            out.append({
                "source": "modrinth",
                "id": v["id"],
                "name": f0.get("filename", ""),
                "version": v.get("version_number"),
                "fetch": (lambda vid=v["id"], url=f0["url"], nm=f0.get("filename", ""):
                          fetch_jar_modrinth(vid, url, nm)),
            })
        return out
    return []


def current_id_of(entry: dict):
    """Return the source-appropriate identifier for the currently-pinned
    version, used to short-circuit when the candidate list's newest entry
    matches what we already ship."""
    return entry.get("file_id") if entry["source"] == "curseforge" else entry.get("version_id")


# ---------------------------------------------------------------------------
# Output formatters per dest_file. Sha256 left as a $(nix hash file ...)
# shell substitution so the user pastes the entry into a here-doc / shell
# pipeline that materializes the literal hash. Avoids embedding `nix`
# shell-outs in the script itself.
# ---------------------------------------------------------------------------

def format_extras_replacement(b: dict) -> str:
    cached = CACHE_DIR / f"cf-{b['file_id']}-{b['name']}"
    pre, suf = b["file_id"] // 1000, b["file_id"] % 1000
    return (
        f"    {{\n"
        f"      origProjectID = {b['project_id']};\n"
        f"      origFileID    = {b['current_file_id']};\n"
        f"      projectID     = {b['project_id']};\n"
        f"      fileID        = {b['file_id']};\n"
        f"      required      = true;\n"
        f"      filename      = \"{b['name']}\";\n"
        f"      jar = fetchurl {{\n"
        f"        url    = \"https://mediafilez.forgecdn.net/files/{pre}/{suf}/{b['name']}\";\n"
        f"        name   = \"{b['name']}\";\n"
        f"        sha256 = \"$(nix hash file --base32 --type sha256 {cached})\";\n"
        f"      }};\n"
        f"    }}"
    )


def format_overlays_curseforge(b: dict) -> str:
    cached = CACHE_DIR / f"cf-{b['file_id']}-{b['name']}"
    return (
        f"  # In overlays.nix, replace the matching curseforge entry with:\n"
        f"  {{\n"
        f"    filename       = \"{b['name']}\";\n"
        f"    dropAsOverride = false;\n"
        f"    projectID      = {b['project_id']};\n"
        f"    fileID         = {b['file_id']};\n"
        f"    jar = curseforge {b['file_id']} \"{b['name']}\"\n"
        f"      \"$(nix hash file --base32 --type sha256 {cached})\";\n"
        f"  }}"
    )


def format_overlays_modrinth(b: dict) -> str:
    cached = CACHE_DIR / f"mr-{b['version_id']}-{b['name']}"
    return (
        f"  # In overlays.nix, replace the matching modrinth entry with:\n"
        f"  {{\n"
        f"    filename       = \"{b['name']}\";\n"
        f"    dropAsOverride = true;\n"
        f"    jar = modrinth \"{b['project_id']}\" \"{b['version_id']}\"\n"
        f"      \"{b['name']}\"\n"
        f"      \"$(nix hash file --base32 --type sha256 {cached})\";\n"
        f"  }}"
    )


# ---------------------------------------------------------------------------
# Orchestrator.
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("server_tree", help="Path to built server tree (mods/ inside)")
    ap.add_argument("--mods-nix", default="pkgs/create-arkana-aeronautics-server/arkana-mods.nix")
    ap.add_argument("--extras-nix", default="pkgs/create-arkana-aeronautics-server/arkana-mods-extras.nix")
    ap.add_argument("--overlays-nix", default="pkgs/create-arkana-aeronautics-server/overlays.nix")
    ap.add_argument("--only", help="Comma-separated modIds — process these only")
    ap.add_argument("--skip", help="Comma-separated modIds to skip (e.g. known-incompat bumps)")
    ap.add_argument("--report-json", help="Also write machine-readable bumps to this file")
    args = ap.parse_args()

    only = set(s.strip() for s in (args.only or "").split(",") if s.strip())
    skip = set(s.strip() for s in (args.skip or "").split(",") if s.strip())

    server_tree = Path(args.server_tree)
    mods_dir = server_tree / "mods"
    if not mods_dir.is_dir():
        print(f"no mods/ in {server_tree}", file=sys.stderr)
        sys.exit(2)

    # Parse all three source files into the merged state.
    overlays_path = Path(args.overlays_nix)
    state = load_pack_state(
        Path(args.mods_nix),
        Path(args.extras_nix),
        overlays_path if overlays_path.exists() else None,
    )

    # Walk the built server tree to extract modId -> (filename, version,
    # deps) and bind to source-tagged state entries by filename.
    print(f"Scanning {mods_dir}…", file=sys.stderr)
    modid_to_entry = {}    # modId -> state entry (with source + ids)
    modid_to_filename = {}
    current_version = {}
    deps = {}              # modId -> [(dep_modId, range, type)]
    for jar in sorted(mods_dir.iterdir()):
        if not jar.name.endswith(".jar"):
            continue
        info = parse_jar_mods(jar)
        for mid, meta in info.items():
            current_version[mid] = meta["version"]
            deps[mid] = meta["deps"]
            modid_to_filename[mid] = jar.name
            if jar.name in state:
                modid_to_entry[mid] = state[jar.name]

    # Reverse map (dependents).
    dependents = defaultdict(set)
    for mid, dlist in deps.items():
        for dep_mid, _, dep_type in dlist:
            if dep_type == "required":
                dependents[dep_mid].add(mid)

    # Bumpable = all mods we have a known source for. Dropping --only/--skip.
    bumpable = set(modid_to_entry.keys())
    if only:
        bumpable &= only
    bumpable -= skip
    order = toposort_leaves_first(bumpable, dependents)
    by_source = defaultdict(int)
    for m in bumpable:
        by_source[modid_to_entry[m]["source"]] += 1
    print(f"Bumpable mod count: {len(bumpable)} "
          f"(curseforge={by_source['curseforge']}, modrinth={by_source['modrinth']}); "
          f"processing leaves first.", file=sys.stderr)

    bumps = {}
    skipped_reasons = {}

    def planned_version(mid: str) -> str:
        if mid in bumps:
            return bumps[mid]["version"]
        return current_version.get(mid, "")

    for i, mid in enumerate(order):
        entry = modid_to_entry[mid]
        cur_ver = current_version.get(mid, "?")
        candidates = enumerate_candidates(entry)
        if not candidates:
            skipped_reasons[mid] = (
                f"no {entry['source']} versions returned (project deleted? "
                f"or rate-limited)"
            )
            continue

        cur_id = current_id_of(entry)
        if cur_id is not None and candidates[0]["id"] == cur_id:
            skipped_reasons[mid] = f"already at latest ({cur_ver})"
            continue

        chose = None
        chose_meta = None
        for cand in candidates:
            if cur_id is not None and cand["id"] == cur_id:
                # Reached current — newer didn't satisfy; nothing left.
                break
            jar = cand["fetch"]()
            if not jar.exists() or jar.stat().st_size == 0:
                continue
            cand_info = parse_jar_mods(jar)
            cand_meta = cand_info.get(mid)
            if cand_meta is None:
                continue
            cand_version = cand_meta["version"] or cand.get("version") or ""

            # Semver guard. CurseForge sometimes lists a file whose upload-id
            # is higher than the current pack pin but whose semantic version
            # is older (re-upload of a "fix" against an older version line —
            # e.g. JustEnoughResources 1.6.0.17 currently pinned, .12 later
            # re-uploaded with a higher fileID). enumerate_candidates sorts
            # by fileID so those slip through as "newer". Reject any
            # candidate whose parsed version isn't strictly greater than
            # current, regardless of upload time.
            if cur_ver and version_key(cand_version) <= version_key(cur_ver):
                continue

            # Forward-check: candidate's required deps satisfied?
            fwd_ok = True
            for dep_mid, drange, dtype in cand_meta["deps"]:
                if dtype != "required":
                    continue
                if dep_mid in ("minecraft", "neoforge", "forge", "java"):
                    continue
                planned = planned_version(dep_mid)
                if not planned:
                    fwd_ok = False
                    break
                if not in_range(planned, drange):
                    fwd_ok = False
                    break
            if not fwd_ok:
                continue

            # Reverse-check: existing dependents still accept this candidate?
            rev_ok = True
            for dep_user in dependents.get(mid, set()):
                user_deps = deps.get(dep_user, [])
                for d_mid, d_range, d_type in user_deps:
                    if d_mid != mid or d_type != "required":
                        continue
                    if not in_range(cand_version, d_range):
                        rev_ok = False
                        break
                if not rev_ok:
                    break
            if not rev_ok:
                continue

            chose = cand
            chose_meta = cand_meta
            break

        if chose is None or chose_meta is None:
            skipped_reasons[mid] = "no compatible newer version found"
            continue

        # Build bump record. Shape varies by source so the formatter can
        # emit the right replacement entry.
        record = {
            "source": entry["source"],
            "dest_file": entry["dest_file"],
            "name": chose["name"],
            "version": chose_meta["version"] or chose.get("version") or "",
            "current_version": cur_ver,
            "project_id": entry["project_id"],
        }
        if entry["source"] == "curseforge":
            record["file_id"] = chose["id"]
            record["current_file_id"] = entry.get("file_id", 0)
        else:
            record["version_id"] = chose["id"]
            record["current_version_id"] = entry.get("version_id", "")
        bumps[mid] = record
        print(f"  [{i+1}/{len(order)}] {mid}: {cur_ver} -> {record['version']} "
              f"({entry['source']} {cur_id} -> {chose['id']})", file=sys.stderr)

    # Report.
    print()
    print(f"=== {len(bumps)} bumps available ===")
    for mid, b in sorted(bumps.items()):
        tag = "[mr]" if b["source"] == "modrinth" else "[cf]"
        print(f"  {tag} {mid:30s}  {b['current_version']:20s} -> {b['version']}")
    print()
    print(f"=== Skipped: {len(skipped_reasons)} ===")
    for mid, reason in sorted(skipped_reasons.items()):
        print(f"  {mid:30s}  {reason}")

    # Replacement entries grouped by destination file.
    extras_bumps = [b for b in bumps.values() if b["dest_file"] == "extras.nix"]
    overlays_cf  = [b for b in bumps.values()
                    if b["dest_file"] == "overlays.nix" and b["source"] == "curseforge"]
    overlays_mr  = [b for b in bumps.values()
                    if b["dest_file"] == "overlays.nix" and b["source"] == "modrinth"]

    if extras_bumps:
        print()
        print("=== extras.nix replacement entries (paste into `replacements = [ ... ]`) ===")
        for b in sorted(extras_bumps, key=lambda x: x["name"]):
            print(format_extras_replacement(b))

    if overlays_cf:
        print()
        print("=== overlays.nix CurseForge entries (replace in-place) ===")
        for b in sorted(overlays_cf, key=lambda x: x["name"]):
            print(format_overlays_curseforge(b))

    if overlays_mr:
        print()
        print("=== overlays.nix Modrinth entries (replace in-place) ===")
        for b in sorted(overlays_mr, key=lambda x: x["name"]):
            print(format_overlays_modrinth(b))

    if args.report_json:
        Path(args.report_json).write_text(json.dumps(
            {"bumps": bumps, "skipped": skipped_reasons}, indent=2))


if __name__ == "__main__":
    main()
