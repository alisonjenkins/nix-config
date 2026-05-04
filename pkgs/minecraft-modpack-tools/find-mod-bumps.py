#!/usr/bin/env python3
"""Find newer compatible mod versions for a NeoForge modpack.

Algorithm (per the dep-graph leaf-first walk the user requested):
  1. Read the existing mod set from `arkana-mods.nix` + `extras.nix`
     (extras `replacements` override arkana entries by origProjectID).
  2. Walk the built server tree's mods/ to map filename -> modId via
     each jar's META-INF/neoforge.mods.toml, and build:
       - current_version[modId]
       - deps[modId] = [(dep_modId, versionRange, type), ...]
       - projectID[modId] (CurseForge ID, from arkana-mods.nix)
  3. Reverse-edge the graph -> dependents[modId].
  4. Topo-sort leaves first (no dependents -> first).
  5. For each modId in that order, query cfwidget for all 1.21.1+NeoForge
     files; walk newest-first; for each candidate:
       a. download jar, parse its mods.toml to get its declared deps
       b. for each dep: planned version = bumped[dep] or current[dep];
          fail if dep version not in candidate's required range
       c. for each existing dependent of this mod: fail if candidate
          version not in dependent's existing required range
       d. first candidate that passes both = winner; record bump.
  6. Print the bump table + ready-to-paste replacement entries for
     extras.nix.

Generic — no Arkana-specific assumptions beyond the parse paths (which
default to the Arkana files but accept --mods-nix / --extras-nix /
--server-tree overrides). Use from any modpack derivation that follows
the same arkana-mods.nix layout.

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
import urllib.request
import zipfile
from collections import defaultdict
from pathlib import Path

try:
    import tomllib  # Python 3.11+
except ImportError:
    import tomli as tomllib  # type: ignore


# ---------------------------------------------------------------------------
# mods.toml parsing — deliberately the same shape as dep-tree.py so a future
# refactor can extract a shared helper module.
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
                for m in mods:
                    mid = m.get("modId")
                    if not mid:
                        continue
                    ver = m.get("version", "")
                    deplist = []
                    raw = deps.get(mid, [])
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
# Version-range checks (lifted in spirit from dep-tree.py — same Maven
# range syntax: `[lo,hi]` `[lo,)` `(lo,hi)` etc.).
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
# Parse arkana-mods.nix + extras.nix to extract (filename, projectID, fileID).
# Two passes: arkana entries first, then extras `replacements` override
# any arkana entry whose (origProjectID, origFileID) match. Skipped/disabled
# entries from extras are dropped entirely so we don't waste API calls
# trying to bump them.
# ---------------------------------------------------------------------------

ENTRY_RE = re.compile(
    r"projectID\s*=\s*(\d+)\s*;\s*"
    r"fileID\s*=\s*(\d+)\s*;\s*"
    r"required\s*=\s*\w+\s*;\s*"
    r"filename\s*=\s*\"([^\"]+)\"",
    re.S,
)
REPLACE_RE = re.compile(
    r"origProjectID\s*=\s*(\d+)\s*;\s*"
    r"origFileID\s*=\s*(\d+)\s*;\s*"
    r"projectID\s*=\s*(\d+)\s*;\s*"
    r"fileID\s*=\s*(\d+)\s*;\s*"
    r"required\s*=\s*\w+\s*;\s*"
    r"filename\s*=\s*\"([^\"]+)\"",
    re.S,
)
SKIPDIS_RE = re.compile(r"projectID\s*=\s*(\d+)\s*;\s*fileID\s*=\s*(?:(\d+)|null)")


def load_pack_state(mods_nix: Path, extras_nix: Path):
    """Returns dict: filename -> (projectID, fileID).
    Effective state: extras `replacements` win over arkana entries by
    (origProjectID, origFileID) match. extras `skipped`/`disabled`
    blocks remove arkana entries (so we don't bump dropped mods)."""
    arkana_text = mods_nix.read_text()
    extras_text = extras_nix.read_text()

    # Step 1: arkana base set, keyed by (projectID, fileID) so we can
    # apply the (origProjectID, origFileID) overrides directly.
    by_orig = {}
    for m in ENTRY_RE.finditer(arkana_text):
        pid, fid, fname = int(m.group(1)), int(m.group(2)), m.group(3)
        by_orig[(pid, fid)] = fname

    # Step 2: replacements section — string-search to bound the match
    # range. The two list bodies are syntactically identical so without
    # bounding we'd pull `skipped`/`disabled` entries (which use a
    # different schema) into the replacements pass.
    repl_start = extras_text.find("replacements = [")
    repl_end = extras_text.find("];", repl_start)
    repl_text = extras_text[repl_start:repl_end]
    for m in REPLACE_RE.finditer(repl_text):
        opid, ofid = int(m.group(1)), int(m.group(2))
        npid, nfid, fname = int(m.group(3)), int(m.group(4)), m.group(5)
        # Drop the orig entry, install the replacement.
        by_orig.pop((opid, ofid), None)
        by_orig[(npid, nfid)] = fname

    # Step 3: skipped + disabled — remove from working set so we don't
    # try to bump a mod we deliberately exclude.
    for section in ("skipped = [", "disabled = ["):
        s = extras_text.find(section)
        if s == -1:
            continue
        e = extras_text.find("];", s)
        for m in SKIPDIS_RE.finditer(extras_text[s:e]):
            pid = int(m.group(1))
            fid = int(m.group(2)) if m.group(2) else None
            if fid is None:
                # nuke every entry for that projectID
                for k in list(by_orig.keys()):
                    if k[0] == pid:
                        del by_orig[k]
            else:
                by_orig.pop((pid, fid), None)

    # Re-key by filename for the server-tree match step downstream.
    return {fname: (pid, fid) for (pid, fid), fname in by_orig.items()}


# ---------------------------------------------------------------------------
# CurseForge query + jar fetch (cached). cfwidget gives us all files for
# a project in one call so we can pick the newest 1.21.1+NeoForge candidate
# without paginating. Mediafilez is the actual download — sometimes 403s
# from non-residential IPs, but our local mac usually succeeds.
# ---------------------------------------------------------------------------

CACHE_DIR = Path(os.environ.get("FIND_BUMPS_CACHE", "/tmp/find-mod-bumps-cache"))


def http_get(url: str, retries: int = 3, sleep: float = 1.0) -> bytes:
    last = None
    for _ in range(retries):
        try:
            with urllib.request.urlopen(url, timeout=30) as r:
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


def fetch_jar(file_id: int, name: str) -> Path:
    """Download a CF file to cache and return the local path."""
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    out = CACHE_DIR / f"{file_id}-{name}"
    if out.exists() and out.stat().st_size > 0:
        return out
    pre, suf = file_id // 1000, file_id % 1000
    url = f"https://mediafilez.forgecdn.net/files/{pre}/{suf}/{name}"
    try:
        data = http_get(url)
        out.write_bytes(data)
        return out
    except Exception:
        return out  # may be empty; caller handles


# ---------------------------------------------------------------------------
# Toposort — leaves (no dependents) first. Falls back to Kahn-style on
# cycles (logs a note); we don't need a strict ordering, just a hint.
# ---------------------------------------------------------------------------

def toposort_leaves_first(modids, dependents):
    remaining = set(modids)
    ordered = []
    while remaining:
        # Pick mods with no remaining dependents.
        leaves = [m for m in remaining if not (dependents.get(m, set()) & remaining)]
        if not leaves:
            # Cycle. Just emit whatever's left in arbitrary order.
            ordered.extend(sorted(remaining))
            break
        leaves.sort()
        ordered.extend(leaves)
        for m in leaves:
            remaining.discard(m)
    return ordered


# ---------------------------------------------------------------------------
# Orchestrator.
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("server_tree", help="Path to built server tree (mods/ inside)")
    ap.add_argument("--mods-nix", default="pkgs/create-arkana-aeronautics-server/arkana-mods.nix")
    ap.add_argument("--extras-nix", default="pkgs/create-arkana-aeronautics-server/arkana-mods-extras.nix")
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

    # Step 1: parse arkana-mods.nix + extras for filename -> (pid, fid).
    state = load_pack_state(Path(args.mods_nix), Path(args.extras_nix))

    # Step 2: walk built server tree to extract modId -> (filename, version,
    # deps). For each jar in mods/, parse its mods.toml.
    #
    # A modid may be served by a jar without a CurseForge projectID (Modrinth-
    # only mods like Aeronautics, Sable, spark, c2me). Those skip the bump
    # search but still count toward dep graph.
    print(f"Scanning {mods_dir}…", file=sys.stderr)
    modid_to_pid = {}      # modId -> CF projectID (only for CF-managed)
    modid_to_filename = {} # modId -> jar filename
    current_version = {}   # modId -> version string
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
                modid_to_pid[mid] = state[jar.name][0]

    # Step 3: reverse map (dependents).
    dependents = defaultdict(set)
    for mid, dlist in deps.items():
        for dep_mid, _range, dep_type in dlist:
            if dep_type == "required":
                dependents[dep_mid].add(mid)

    # Step 4: leaf-first toposort over the bumpable set (those with CF
    # projectIDs). Mods without projectIDs still appear as deps but are
    # never themselves promoted to a candidate.
    bumpable = set(modid_to_pid.keys())
    if only:
        bumpable &= only
    bumpable -= skip
    order = toposort_leaves_first(bumpable, dependents)
    print(f"Bumpable mod count: {len(bumpable)}; processing leaves first.", file=sys.stderr)

    # Step 5: walk in that order. For each mod, find newest CF candidate
    # whose declared deps are satisfied by current/already-planned bumps,
    # AND whose new version still satisfies all existing dependents'
    # ranges.
    bumps = {}   # modId -> {file_id, name, version}
    skipped_reasons = {}

    def planned_version(mid: str) -> str:
        if mid in bumps:
            return bumps[mid]["version"]
        return current_version.get(mid, "")

    for i, mid in enumerate(order):
        pid = modid_to_pid[mid]
        cur_ver = current_version.get(mid, "?")
        candidates = cfwidget_files(pid)
        if not candidates:
            skipped_reasons[mid] = "no cfwidget files (project deleted? or rate-limited)"
            continue
        # Skip if current is already the newest known (cur fileID == latest).
        cur_fid = state.get(modid_to_filename[mid], (0, 0))[1]
        if candidates[0]["id"] == cur_fid:
            skipped_reasons[mid] = f"already at latest ({cur_ver})"
            continue

        chose = None
        chose_meta = None
        for cand in candidates:
            if cand["id"] == cur_fid:
                # Reached current — no improvement available.
                break
            jar = fetch_jar(cand["id"], cand["name"])
            if not jar.exists() or jar.stat().st_size == 0:
                continue
            cand_info = parse_jar_mods(jar)
            cand_meta = cand_info.get(mid)
            if cand_meta is None:
                # Multi-mod jar or modId mismatch — try the next candidate.
                continue
            cand_version = cand_meta["version"]

            # Forward-check: candidate's required deps satisfied?
            fwd_ok = True
            fwd_failure = ""
            for dep_mid, drange, dtype in cand_meta["deps"]:
                if dtype != "required":
                    continue
                if dep_mid in ("minecraft", "neoforge", "forge", "java"):
                    continue
                planned = planned_version(dep_mid)
                if not planned:
                    # Dep modId not in our pack at all — can't satisfy.
                    fwd_ok = False
                    fwd_failure = f"missing dep {dep_mid} (range {drange})"
                    break
                if not in_range(planned, drange):
                    fwd_ok = False
                    fwd_failure = f"{dep_mid} {planned} ∉ {drange}"
                    break
            if not fwd_ok:
                continue

            # Reverse-check: existing dependents still accept this candidate?
            rev_ok = True
            rev_failure = ""
            for dep_user in dependents.get(mid, set()):
                user_deps = deps.get(dep_user, [])
                for d_mid, d_range, d_type in user_deps:
                    if d_mid != mid or d_type != "required":
                        continue
                    if not in_range(cand_version, d_range):
                        rev_ok = False
                        rev_failure = f"{dep_user} requires {mid} {d_range}"
                        break
                if not rev_ok:
                    break
            if not rev_ok:
                continue

            chose = cand
            chose_meta = cand_meta
            break

        if chose is None:
            skipped_reasons[mid] = "no compatible newer version found"
            continue
        bumps[mid] = {
            "file_id": chose["id"],
            "name": chose["name"],
            "version": chose_meta["version"],
            "project_id": pid,
            "current_file_id": cur_fid,
            "current_version": cur_ver,
        }
        print(f"  [{i+1}/{len(order)}] {mid}: {cur_ver} -> {chose_meta['version']} "
              f"(fileID {cur_fid} -> {chose['id']})", file=sys.stderr)

    # Step 6: print human-readable report + ready-to-paste extras entries.
    print()
    print(f"=== {len(bumps)} bumps available ===")
    for mid, b in sorted(bumps.items()):
        print(f"  {mid:35s}  {b['current_version']:20s} -> {b['version']}")
    print()
    print(f"=== Skipped: {len(skipped_reasons)} ===")
    for mid, reason in sorted(skipped_reasons.items()):
        print(f"  {mid:35s}  {reason}")

    # Replacement entries — paste into extras.nix `replacements = [ ... ]`.
    # sha256 deliberately left as a placeholder; user runs `nix hash file`
    # locally on the cached jar (we already downloaded it). Keeping the
    # script free of `nix` shell-outs makes it portable.
    if bumps:
        print()
        print("=== extras.nix replacement entries (compute sha256 locally) ===")
        for mid, b in sorted(bumps.items()):
            cached = CACHE_DIR / f"{b['file_id']}-{b['name']}"
            pre, suf = b["file_id"] // 1000, b["file_id"] % 1000
            print(f"""    {{
      origProjectID = {b['project_id']};
      origFileID    = {b['current_file_id']};
      projectID     = {b['project_id']};
      fileID        = {b['file_id']};
      required      = true;
      filename      = "{b['name']}";
      jar = fetchurl {{
        url    = "https://mediafilez.forgecdn.net/files/{pre}/{suf}/{b['name']}";
        name   = "{b['name']}";
        sha256 = "$(nix hash file --base32 --type sha256 {cached})";
      }};
    }}""")

    if args.report_json:
        Path(args.report_json).write_text(json.dumps(
            {"bumps": bumps, "skipped": skipped_reasons}, indent=2))


if __name__ == "__main__":
    main()
