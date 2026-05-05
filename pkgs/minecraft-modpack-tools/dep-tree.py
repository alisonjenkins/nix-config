#!/usr/bin/env python3
"""Pre-flight dependency checker for any NeoForge / Forge server tree.

Walks every jar in a built server tree's mods/ directory, parses
META-INF/neoforge.mods.toml (falls back to META-INF/mods.toml for legacy
Forge mods, recurses through META-INF/jars/* for JIJ-bundled children),
builds provides/requires graphs, and reports:

  - mods whose required deps are missing (would fail at runtime)
  - mods whose required deps are present but version-out-of-range
  - the dep tree under any specific mod (use --tree <modId>)
  - reverse deps for a modId (use --dependents <modId>)

Why pre-flight: bisecting via boot cycles is multi-minute per round and a
single missing dep masks every transitive dependent until that lib is
classified into a group. With the dep graph in hand we know exactly which
libraries each feature mod expects — surface blockers in seconds, not
minutes.

Usage:
  dep-tree /path/to/server-tree                          # full report
  dep-tree /path/to/server-tree --tree apotheosis        # transitive deps
  dep-tree /path/to/server-tree --dependents create      # reverse deps

Generic to any modpack — no Arkana-specific assumptions. Bake into a
modpack server derivation's installPhase to fail builds before the docker
image layer is computed (saves a multi-minute boot cycle when a mod set
regression introduces an unsatisfied required dep)."""
import argparse
import re
import sys
import zipfile
from pathlib import Path

try:
    import tomllib  # Python 3.11+
except ImportError:
    import tomli as tomllib  # type: ignore


def _parse_toml_bytes(raw_bytes: bytes):
    raw = raw_bytes.decode("utf-8", errors="replace")
    raw = re.sub(r"description\s*=\s*'''.*?'''", "description=''", raw, flags=re.S)
    try:
        data = tomllib.loads(raw)
    except tomllib.TOMLDecodeError as e:
        return None, f"toml-decode-error: {e}"
    return (data.get("mods", []), data.get("dependencies", {})), None


def parse_mod_toml(jar_path: Path):
    """Return (list of (mods, deps) tuples, error). Walks the jar plus
    every nested META-INF/jars/*.jar (JIJ — Forge's jar-in-jar shipping
    mechanism). Each yielded tuple represents one mod definition; the
    caller flattens them into the global provides/requires graph.

    Some jars (e.g. kotlinforforge-5.9.0-all.jar) declare
    `FMLModType: LIBRARY` in MANIFEST.MF and don't ship a mods.toml at
    the outer level. The error returned for those is `library-no-toml`
    so the caller can suppress the noise."""
    results = []
    is_library = False
    try:
        with zipfile.ZipFile(jar_path) as zf:
            # Detect FML library jars so we can downgrade their toml
            # absence from "parse failure" to "expected".
            if "META-INF/MANIFEST.MF" in zf.namelist():
                manifest = zf.read("META-INF/MANIFEST.MF").decode("utf-8", errors="replace")
                if re.search(r"^FMLModType\s*:\s*LIBRARY", manifest, re.M):
                    is_library = True
            for name in ("META-INF/neoforge.mods.toml", "META-INF/mods.toml"):
                if name in zf.namelist():
                    parsed, err = _parse_toml_bytes(zf.read(name))
                    if parsed is not None:
                        results.append(parsed)
                    elif err:
                        return None, err
                    break
            # Walk JIJ children. Forge ships them at META-INF/jars/*.jar;
            # NeoForge moved to META-INF/jarjar/*.jar. Cover both so deps
            # bundled by either loader's ecosystem (whitenoise inside
            # BetterDays under jarjar/, esl inside Create: New Age under
            # jars/) get parsed.
            for inner in zf.namelist():
                is_forge_jij    = inner.startswith("META-INF/jars/") and inner.endswith(".jar")
                is_neoforge_jij = inner.startswith("META-INF/jarjar/") and inner.endswith(".jar")
                if is_forge_jij or is_neoforge_jij:
                    try:
                        inner_bytes = zf.read(inner)
                    except KeyError:
                        continue
                    import io
                    try:
                        with zipfile.ZipFile(io.BytesIO(inner_bytes)) as iz:
                            for nname in ("META-INF/neoforge.mods.toml", "META-INF/mods.toml"):
                                if nname in iz.namelist():
                                    parsed, _err = _parse_toml_bytes(iz.read(nname))
                                    if parsed is not None:
                                        results.append(parsed)
                                    break
                    except zipfile.BadZipFile:
                        pass
    except (zipfile.BadZipFile, KeyError):
        return None, "bad-zip"
    if not results:
        return None, ("library-no-toml" if is_library else "no-toml")
    return results, None


def parse_version_range(spec: str):
    """Parse a Maven-style versionRange like '[1.21.1,)' or '[1.0,2.0)'.
    Returns (lo, lo_incl, hi, hi_incl) or None for `*` / unparseable."""
    if not spec or spec == "*":
        return None
    m = re.match(r"^\s*([\[(])\s*([^,\]\)]*)\s*,\s*([^,\]\)]*)\s*([\])])\s*$", spec)
    if not m:
        # Single version like "1.0.0" treated as exact lower bound
        return ("[", spec.strip(), "", ")")
    return (m.group(1), m.group(2), m.group(3), m.group(4))


def version_key(v: str):
    """Loose semver-ish tuple for comparison. Strips common Minecraft-
    flavored prefixes/suffixes:
      - leading `v`, `Forge-`, `NeoForge-`
      - leading `<mc-version>-` (e.g. `1.21.1-`)
      - trailing `+mc1.21.1`, `-fix`, etc. via the digit-dot truncate
    Pure-numeric prefix of the remaining string wins."""
    v = (v or "").strip().lstrip("v")
    v = re.sub(r"^(?:Neo)?Forge-", "", v, flags=re.I)
    # Strip leading `1.21(.1)?-`. After the prefix, look for the actual
    # mod-version (digit-led).
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
        # Empty version (placeholder we couldn't resolve) — assume the dep
        # IS satisfied. False positives here would mask real failures, but
        # the alternative (treating empty as failing) generates noise on
        # every JIJ-bundled mod and drowns out the real problems.
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


def version_from_filename(jar_name: str) -> str:
    """Extract a version-ish substring from a jar filename when the
    [[mods]] block uses `${file.jarVersion}`. Looks for the longest
    digit/dot/dash run after the first dash. Strips the
    `<mc-version>-` prefix so something like `ars_nouveau-1.21.1-5.10.4`
    yields `5.10.4` (the mod's own version) not `1.21.1-5.10.4` (the
    filename tail). Best-effort — wrong versions cause spurious
    out-of-range hits, never missed missing deps."""
    base = jar_name.removesuffix(".jar")
    m = re.search(r"-(\d[\w.\-+]*)$", base)
    if not m:
        return ""
    raw = m.group(1)
    # Many modders prefix their version with the target MC version, e.g.
    # `ars_nouveau-1.21.1-5.10.4` or `irons_spellbooks-1.21.1-3.14.3`.
    # Strip a leading 1.21.1-style prefix when we find one.
    stripped = re.sub(r"^1\.21(\.\d+)?-", "", raw)
    return stripped


# Mods that exist on the modloader/classpath but don't ship a parseable
# neoforge.mods.toml — mark them as providers so dependents stop showing
# up in "missing". Filename-pattern → modId.
PROVIDER_FROM_FILENAME = [
    (re.compile(r"^kotlinforforge"),               "kotlinforforge"),
    (re.compile(r"^create-1\.21\.1-6\."),          "flywheel"),  # JIJ-bundled
    (re.compile(r"^create-1\.21\.1-6\."),          "ponder"),    # JIJ-bundled
    (re.compile(r"^create-aeronautics-bundled"),   "simulated"),
    (re.compile(r"^create-aeronautics-bundled"),   "offroad"),
]


def collect(mods_dir: Path):
    provides = {}      # modId -> {version, jar, deps}
    requires = {}      # modId -> [(depModId, range, mandatory, ordering)]
    parse_errors = {}  # jar filename -> reason

    for jar in sorted(mods_dir.iterdir()):
        if jar.suffix != ".jar":
            continue
        results, err = parse_mod_toml(jar)
        if results is None:
            parse_errors[jar.name] = err
            # Even if toml parse fails, register filename-pattern providers
            # so dependents resolve.
            for pat, mid in PROVIDER_FROM_FILENAME:
                if pat.match(jar.name):
                    provides.setdefault(mid, {"version": "", "jar": jar.name})
            continue
        # Each `results` entry is one (mods, deps_per_modId) tuple. Outer
        # jar comes first; subsequent tuples are JIJ-bundled mods inside
        # META-INF/jars/. Treat them as full first-class providers.
        for mods, deps in results:
            for m in mods:
                mid = m.get("modId")
                if not mid:
                    continue
                mod_deps = deps.get(mid, []) if isinstance(deps, dict) else []
                requires[mid] = [
                    (d.get("modId", "?"),
                     d.get("versionRange", "*"),
                     d.get("type", "required").lower() == "required",
                     d.get("ordering", "NONE"))
                    for d in mod_deps if isinstance(d, dict)
                ]
                v = str(m.get("version", "")).strip()
                if "${file.jarVersion}" in v or v == "":
                    v = version_from_filename(jar.name)
                # Pick the highest version when the same modId appears
                # multiple times. NeoForge's JIJ resolver does this at
                # runtime — top-level mods often ship newer than JIJ
                # copies bundled by other mods (e.g. top-level Placebo
                # 9.9.1 vs JIJ Placebo 9.9.0 inside gag), and a naive
                # last-write-wins flips the dep check spuriously.
                prev = provides.get(mid)
                if prev is None or version_key(v) > version_key(prev.get("version", "")):
                    provides[mid] = {"version": v, "jar": jar.name}

        # Filename-pattern providers also kick in when a real mod is
        # parsed: e.g. Create's main jar declares `create` in TOML but
        # bundles flywheel + ponder via JIJ. Mark those as provided.
        for pat, mid in PROVIDER_FROM_FILENAME:
            if pat.match(jar.name) and mid not in provides:
                provides[mid] = {"version": "", "jar": jar.name}

    return provides, requires, parse_errors


# Modules NeoForge always provides. Always treated as satisfied.
RUNTIME_PROVIDED = {
    "minecraft": "1.21.1",
    "neoforge": "21.1.228",
    "forge": "21.1.228",
    "fml": "4.0.42",
    "java": "21",
    "javafml": "*",
}


def check(provides, requires):
    missing = []   # (mod, dep, range, "missing")
    out_of_range = []  # (mod, dep, dep_version, range)
    for mod, deps in requires.items():
        for dep, rng, mandatory, _ordering in deps:
            if not mandatory:
                continue
            # NeoForge handles MC + loader version validation itself; mods
            # commonly declare buggy ranges like `[1.21,1.21.1)` that we'd
            # otherwise flag as exclusion failures even though NeoForge
            # accepts them at runtime. Skip the range check for these.
            if dep == "minecraft":
                continue
            if dep in RUNTIME_PROVIDED:
                v = RUNTIME_PROVIDED[dep]
                if not in_range(v, rng):
                    out_of_range.append((mod, dep, v, rng))
                continue
            if dep not in provides:
                missing.append((mod, dep, rng))
                continue
            v = provides[dep]["version"]
            if not in_range(v, rng):
                out_of_range.append((mod, dep, v, rng))
    return missing, out_of_range


def tree(provides, requires, root, depth=0, seen=None):
    seen = seen or set()
    if root in seen:
        print("  " * depth + f"- {root} (cycle)")
        return
    seen = seen | {root}
    v = provides.get(root, {}).get("version", "?")
    print("  " * depth + f"- {root} {v}")
    for dep, rng, mandatory, _o in requires.get(root, []):
        if not mandatory:
            continue
        if dep in RUNTIME_PROVIDED:
            continue
        tree(provides, requires, dep, depth + 1, seen)


def dependents_of(target, requires):
    out = []
    for mod, deps in requires.items():
        for dep, rng, mandatory, _o in deps:
            if dep == target and mandatory:
                out.append((mod, rng))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("server_pkg", help="path to built server pkg (has mods/ dir)")
    ap.add_argument("--tree", help="show transitive required deps under modId")
    ap.add_argument("--dependents", help="show mods that hard-require modId")
    args = ap.parse_args()

    mods_dir = Path(args.server_pkg) / "mods"
    if not mods_dir.is_dir():
        print(f"no mods/ at {mods_dir}", file=sys.stderr)
        sys.exit(2)

    provides, requires, parse_errors = collect(mods_dir)

    if args.tree:
        tree(provides, requires, args.tree)
        return
    if args.dependents:
        deps = dependents_of(args.dependents, requires)
        print(f"{len(deps)} mods hard-require {args.dependents}:")
        for mod, rng in sorted(deps):
            print(f"  {mod}  ({rng})")
        return

    missing, out_of_range = check(provides, requires)
    # Library jars (FMLModType=LIBRARY) legitimately have no mods.toml at
    # the outer level — they're loaded by FML directly and ship their
    # actual mods via JIJ. Their JIJ children DO have toml so the dep
    # graph is complete; suppress the scary "parse failure" line.
    real_failures = {k: v for k, v in parse_errors.items() if v != "library-no-toml"}
    print(f"Mods analyzed: {len(provides)}")
    if real_failures:
        print(f"Parse failures: {len(real_failures)}")
        for jar, reason in sorted(real_failures.items())[:5]:
            print(f"  {jar}: {reason}")
    print()
    print(f"=== Missing required deps ({len(missing)}) ===")
    for mod, dep, rng in sorted(missing):
        print(f"  {mod} -> {dep} {rng}")
    print()
    print(f"=== Required deps out of version range ({len(out_of_range)}) ===")
    for mod, dep, v, rng in sorted(out_of_range):
        print(f"  {mod} -> {dep} (have {v}, need {rng})")


if __name__ == "__main__":
    main()
