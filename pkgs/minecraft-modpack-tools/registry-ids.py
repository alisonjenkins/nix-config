#!/usr/bin/env python3
"""Extract registry IDs from Minecraft jars, and validate FTB Quests files.

Mods register items, entities and dimensions in code, so a jar has no
registry dump. Each registered thing still leaves a trace in the jar's
resources, and this script collects those traces:

- items:        an item model or blockstate that also has an item./block. key
                in an en_us lang file (or a key under it, such as
                item.apotheosis.gem.chipped for apotheosis:gem). Either trace
                alone is too loose: mods ship GUI-only models, and lang files
                carry tooltip keys.
- entities:     entity.<ns>.<path> lang keys, data/<ns>/loot_table/entities/
- dimensions:   data/<ns>/dimension/<path>.json, plus the three vanilla levels
- advancements: data/<ns>/advancement/<path>.json

Nested jar-in-jar libraries (META-INF/jarjar) are walked too.

Usage:
  registry-ids extract JAR_OR_DIR... > ids.json
  registry-ids check --ids ids.json QUESTS_DIR

`check` exits 1 and lists every item, entity, dimension and advancement
ID in the quest SNBT files that no jar provides.
"""
import argparse
import io
import json
import re
import sys
import zipfile
from pathlib import Path

KINDS = ("items", "entities", "dimensions", "advancements")

# The overworld, nether and end are built into the game, not data files.
VANILLA_LEVELS = ("minecraft:overworld", "minecraft:the_nether", "minecraft:the_end")

DIMENSION = re.compile(r"^data/([a-z0-9_.-]+)/dimension/([a-z0-9_./-]+)\.json$")
ADVANCEMENT = re.compile(r"^data/([a-z0-9_.-]+)/advancements?/([a-z0-9_./-]+)\.json$")
ENTITY_LOOT = re.compile(r"^data/([a-z0-9_.-]+)/loot_tables?/entities/([a-z0-9_./-]+)\.json$")
ITEM_MODEL = re.compile(r"^assets/([a-z0-9_.-]+)/(?:models/item|blockstates)/([a-z0-9_./-]+)\.json$")
LANG = re.compile(r"^assets/[a-z0-9_.-]+/lang/en_us\.json$")
LANG_KEY = re.compile(r"^(item|block|entity)\.([a-z0-9_.-]+?)\.([a-z0-9_/.-]+)$")


def scan_zip(zf, ids, origin):
    for name in zf.namelist():
        if m := ITEM_MODEL.match(name):
            ids["models"].add(f"{m[1]}:{m[2]}")
        elif m := DIMENSION.match(name):
            ids["dimensions"].add(f"{m[1]}:{m[2]}")
        elif m := ADVANCEMENT.match(name):
            ids["advancements"].add(f"{m[1]}:{m[2]}")
        elif m := ENTITY_LOOT.match(name):
            ids["entities"].add(f"{m[1]}:{m[2]}")
        elif LANG.match(name):
            try:
                lang = json.loads(zf.read(name).decode("utf-8-sig"))
            except (ValueError, UnicodeDecodeError) as err:
                print(f"warning: {origin}!{name}: unreadable lang file: {err}", file=sys.stderr)
                continue
            for key in lang:
                if m := LANG_KEY.match(key):
                    kind = "entities" if m[1] == "entity" else "lang_items"
                    ids[kind].add(f"{m[2]}:{m[3]}")
        elif name.endswith(".jar") and name.startswith("META-INF/"):
            with zipfile.ZipFile(io.BytesIO(zf.read(name))) as inner:
                scan_zip(inner, ids, f"{origin}!{name}")


def extract(paths):
    ids = {k: set() for k in (*KINDS, "models", "lang_items")}
    ids["dimensions"].update(VANILLA_LEVELS)
    jars = []
    for p in map(Path, paths):
        jars.extend(sorted(p.rglob("*.jar")) if p.is_dir() else [p])
    for jar in jars:
        with zipfile.ZipFile(jar) as zf:
            scan_zip(zf, ids, jar.name)
    lang_items = ids.pop("lang_items")
    lang_roots = {key.split(".", 1)[0] for key in lang_items}
    ids["items"] = {m for m in ids.pop("models") if m in lang_items or m in lang_roots}
    return {k: sorted(v) for k, v in ids.items()}


# FTB Quests keys whose string value is a registry ID, by registry.
SNBT_REFS = {
    "items": re.compile(r'\bid:\s*"([a-z0-9_.-]+:[a-z0-9_./-]+)"'),
    "entities": re.compile(r'\bentity:\s*"([a-z0-9_.-]+:[a-z0-9_./-]+)"'),
    "dimensions": re.compile(r'\bdimension:\s*"([a-z0-9_.-]+:[a-z0-9_./-]+)"'),
    "advancements": re.compile(r'\badvancement:\s*"([a-z0-9_.-]+:[a-z0-9_./-]+)"'),
}


def check(ids_file, quests_dir):
    known = {k: set(v) for k, v in json.loads(Path(ids_file).read_text()).items()}
    missing = []
    seen = 0
    for snbt in sorted(Path(quests_dir).rglob("*.snbt")):
        text = snbt.read_text(encoding="utf-8")
        for kind, pattern in SNBT_REFS.items():
            for m in pattern.finditer(text):
                seen += 1
                if m[1] not in known[kind]:
                    line = text.count("\n", 0, m.start()) + 1
                    missing.append(f"{snbt.relative_to(quests_dir)}:{line}: unknown {kind[:-1]} {m[1]}")
    for line in missing:
        print(line, file=sys.stderr)
    print(f"[registry-ids] checked {seen} ID references in {quests_dir}: {len(missing)} unknown")
    if seen == 0:
        print("[registry-ids] no ID references found: wrong directory or an SNBT layout this script does not parse", file=sys.stderr)
        return 1
    return 1 if missing else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    ex = sub.add_parser("extract")
    ex.add_argument("paths", nargs="+")
    ck = sub.add_parser("check")
    ck.add_argument("--ids", required=True)
    ck.add_argument("quests_dir")
    args = ap.parse_args()
    if args.cmd == "extract":
        json.dump(extract(args.paths), sys.stdout, indent=1)
        print()
        return 0
    return check(args.ids, args.quests_dir)


if __name__ == "__main__":
    sys.exit(main())
