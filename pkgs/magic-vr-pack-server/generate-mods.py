#!/usr/bin/env python3
"""Resolve modlist.toml into a pinned mods.nix for the magic-vr-pack.

Run on the host (needs network), never inside a Nix build:

    python3 -I pkgs/magic-vr-pack-server/generate-mods.py \
        pkgs/magic-vr-pack-server/modlist.toml pkgs/magic-vr-pack-server/mods.nix

Each [[mod]] in modlist.toml names exactly one source:
    modrinth   = "<slug>"        Modrinth project, NeoForge + 1.21.1 builds
    curseforge = <project id>    CurseForge project via cfwidget + mediafilez
plus `group` (see groups.nix) and optional:
    kind    = "mod" | "shaderpack"           shaderpacks resolve Iris builds
    side    = "both" | "client" | "server"   overrides the detected side
    version = "<modrinth version id>" or <cf file id>   pins a build

Required Modrinth dependencies are resolved transitively and emitted in the
separate `libs` list (group "core-libs") unless already listed as a mod.
CurseForge exposes no dependency metadata through cfwidget, so CF mods'
libraries surface in the build-time dep-tree check and get added to
modlist.toml by hand.

Modrinth publishes sha512 per file, so those pins need no download. CF
files are hashed with nix-prefetch-url.
"""
import json
import os
import subprocess
import sys
import time
import tomllib
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

GAME_VERSION = "1.21.1"
LOADER = "neoforge"
USER_AGENT = "nix-config-modpack-generator (personal use)"
MODRINTH_API = "https://api.modrinth.com/v2"
CFWIDGET_API = "https://api.cfwidget.com"
# Modrinth allows 300 req/min; 6 workers stay well under it.
WORKERS = 6
RETRIES = 4
# Prefer stable builds; fall back to beta, then alpha, when a mod has none.
VERSION_TYPE_RANK = {"release": 0, "beta": 1, "alpha": 2}


def http_json(url):
    last = None
    for attempt in range(RETRIES):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                raise LookupError(f"404 for {url}") from e
            last = e
        except (urllib.error.URLError, TimeoutError) as e:
            last = e
        time.sleep(2 ** attempt)
    raise RuntimeError(f"GET {url} failed after {RETRIES} attempts: {last}")


def best_version(versions):
    """Newest build of the most stable type available."""
    if not versions:
        return None
    best_rank = min(VERSION_TYPE_RANK.get(v["version_type"], 9) for v in versions)
    candidates = [v for v in versions if VERSION_TYPE_RANK.get(v["version_type"], 9) == best_rank]
    return max(candidates, key=lambda v: v["date_published"])


def modrinth_resolve(slug_or_id, pinned_version=None, loader=LOADER):
    project = http_json(f"{MODRINTH_API}/project/{urllib.parse.quote(slug_or_id)}")
    if pinned_version:
        version = http_json(f"{MODRINTH_API}/version/{pinned_version}")
    else:
        query = urllib.parse.urlencode({
            "loaders": json.dumps([loader]),
            "game_versions": json.dumps([GAME_VERSION]),
        })
        version = best_version(http_json(f"{MODRINTH_API}/project/{project['id']}/version?{query}"))
    if version is None:
        raise LookupError(f"modrinth {slug_or_id}: no {loader} {GAME_VERSION} build")
    files = [f for f in version["files"] if f.get("primary")] or version["files"][:1]
    f = files[0]
    # Only "client" is auto-detected: many worldgen mods flag client_side
    # "unsupported" yet must still ship in the client for registry sync.
    # Server-only mods are marked with an explicit `side` in modlist.toml.
    side = "client" if project.get("server_side") == "unsupported" else "both"
    deps = [d["project_id"] for d in version.get("dependencies", [])
            if d.get("dependency_type") == "required" and d.get("project_id")]
    return {
        "source": "modrinth",
        "projectID": project["id"],
        "slug": project["slug"],
        "title": project["title"],
        "versionID": version["id"],
        "versionNumber": version["version_number"],
        "versionType": version["version_type"],
        "filename": f["filename"],
        "url": f["url"],
        "hashAlgo": "sha512",
        "hash": f["hashes"]["sha512"],
        "side": side,
        "deps": deps,
    }


def mediafilez_url(file_id, filename):
    encoded = (filename.replace(" ", "%20").replace("+", "%2B")
               .replace("[", "%5B").replace("]", "%5D"))
    return f"https://mediafilez.forgecdn.net/files/{file_id // 1000}/{file_id % 1000}/{encoded}"


def store_name(filename):
    return "".join(c if c.isalnum() or c in "._+-" else "_" for c in filename.replace("'", ""))


def curseforge_resolve(project_id, pinned_file=None):
    meta = http_json(f"{CFWIDGET_API}/{project_id}")
    files = meta.get("files", [])
    if pinned_file:
        files = [f for f in files if f["id"] == pinned_file]
    else:
        files = [f for f in files
                 if GAME_VERSION in f.get("versions", []) and "NeoForge" in f.get("versions", [])]
    if not files:
        raise LookupError(f"curseforge {project_id}: no NeoForge {GAME_VERSION} file")
    best_rank = min(VERSION_TYPE_RANK.get(f["type"], 9) for f in files)
    f = max((f for f in files if VERSION_TYPE_RANK.get(f["type"], 9) == best_rank),
            key=lambda f: f["uploaded_at"])
    url = mediafilez_url(f["id"], f["name"])
    proc = subprocess.run(
        ["nix-prefetch-url", "--type", "sha256", "--name", store_name(f["name"]), url],
        capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"curseforge {project_id}: prefetch {url} failed: {proc.stderr.strip()}")
    versions = f.get("versions", [])
    side = "both"
    if "Client" in versions and "Server" not in versions:
        side = "client"
    return {
        "source": "curseforge",
        "projectID": project_id,
        "slug": meta.get("urls", {}).get("curseforge", "").rstrip("/").rsplit("/", 1)[-1],
        "title": meta.get("title", str(project_id)),
        "fileID": f["id"],
        "versionNumber": f["display"],
        "versionType": f["type"],
        "filename": f["name"],
        "url": url,
        "hashAlgo": "sha256",
        "hash": proc.stdout.strip(),
        "side": side,
        "deps": [],
    }


def resolve_entry(entry):
    if "modrinth" in entry:
        loader = "iris" if entry.get("kind") == "shaderpack" else LOADER
        r = modrinth_resolve(entry["modrinth"], entry.get("version"), loader)
    elif "curseforge" in entry:
        r = curseforge_resolve(int(entry["curseforge"]), entry.get("version"))
    else:
        raise ValueError(f"modlist entry has no source: {entry}")
    r["group"] = entry["group"]
    r["kind"] = entry.get("kind", "mod")
    if "side" in entry:
        r["side"] = entry["side"]
    return r


def nix_str(s):
    return json.dumps(s).replace("${", "\\${")


def render(r):
    ident = (f"versionID = {nix_str(r['versionID'])};" if r["source"] == "modrinth"
             else f"fileID    = {r['fileID']};")
    pid = nix_str(r["projectID"]) if r["source"] == "modrinth" else str(r["projectID"])
    return f"""  {{
    slug      = {nix_str(r['slug'])};
    title     = {nix_str(r['title'])};
    source    = "{r['source']}";
    projectID = {pid};
    {ident}
    version   = {nix_str(r['versionNumber'])};  # {r['versionType']}
    group     = "{r['group']}";
    kind      = "{r['kind']}";
    side      = "{r['side']}";
    filename  = {nix_str(r['filename'])};
    jar = fetchurl {{
      url    = {nix_str(r['url'])};
      name   = {nix_str(store_name(r['filename']))};
      {r['hashAlgo']} = "{r['hash']}";
    }};
  }}
"""


def main(argv):
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    with open(argv[1], "rb") as fh:
        entries = tomllib.load(fh)["mod"]

    errors = []

    def safe(entry):
        try:
            return resolve_entry(entry)
        except Exception as e:  # report every failure, not just the first
            errors.append(f"{entry}: {e}")
            return None

    with ThreadPoolExecutor(WORKERS) as pool:
        mods = [m for m in pool.map(safe, entries) if m]

    known = {m["projectID"] for m in mods}
    libs = []
    pending = sorted({d for m in mods for d in m["deps"]} - known)
    while pending:
        with ThreadPoolExecutor(WORKERS) as pool:
            found = [m for m in pool.map(
                lambda pid: safe({"modrinth": pid, "group": "core-libs"}), pending) if m]
        libs.extend(found)
        known |= set(pending)
        pending = sorted({d for m in found for d in m["deps"]} - known)

    if errors:
        print(f"{len(errors)} unresolved entries; {argv[2]} left unchanged:", file=sys.stderr)
        for e in errors:
            print(f"  {e}", file=sys.stderr)
        return 1

    mods.sort(key=lambda m: (m["group"], m["slug"]))
    libs.sort(key=lambda m: m["slug"])
    # Write beside the target and rename, so an interrupted run never leaves
    # a half-written mods.nix.
    tmp = f"{argv[2]}.tmp"
    with open(tmp, "w", encoding="utf-8") as out:
        out.write("# AUTO-GENERATED by pkgs/magic-vr-pack-server/generate-mods.py from modlist.toml.\n")
        out.write("# Do not hand-edit: change modlist.toml (or extras.nix) and regenerate.\n")
        out.write("{ fetchurl }:\n{\n  mods = [\n")
        out.write("".join(render(m) for m in mods))
        out.write("  ];\n\n  # Required dependencies pulled in by the mods above (Modrinth metadata).\n  libs = [\n")
        out.write("".join(render(m) for m in libs))
        out.write("  ];\n}\n")
    os.replace(tmp, argv[2])
    print(f"wrote {argv[2]}: {len(mods)} mods, {len(libs)} libs", file=sys.stderr)
    for m in mods + libs:
        if m["versionType"] != "release":
            print(f"  note: {m['slug']} pinned to {m['versionType']} {m['versionNumber']}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
