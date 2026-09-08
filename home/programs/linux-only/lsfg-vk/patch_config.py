"""Patch Nix-declared profiles into a live lsfg-vk v2 conf.toml.

The file stays writable so lsfg-vk-ui keeps working: managed profiles are
matched by name and replaced, everything else in the file is left alone.

usage: patch_config.py MANAGED_JSON CONFIG_PATH
"""

import copy
import json
import os
import sys
import tempfile
import tomllib
from pathlib import Path

import tomli_w

CONFIG_VERSION = 2


class UnsupportedConfig(Exception):
    pass


def parse(text: str) -> dict:
    return tomllib.loads(text)


def merge(existing: dict, managed: dict) -> dict:
    version = existing.get("version", CONFIG_VERSION)
    if version != CONFIG_VERSION:
        raise UnsupportedConfig(
            f"conf.toml is version {version}, only version {CONFIG_VERSION} is supported; "
            "migrate or remove it by hand"
        )
    merged = copy.deepcopy(existing)
    merged["version"] = CONFIG_VERSION
    merged.setdefault("global", {}).update(managed["global"])

    profiles = merged.setdefault("profile", [])
    by_name = {p.get("name"): i for i, p in enumerate(profiles)}
    for profile in managed["profiles"]:
        index = by_name.get(profile["name"])
        if index is None:
            profiles.append(dict(profile))
        else:
            profiles[index] = dict(profile)
    return merged


def apply(managed: dict, path: Path) -> bool:
    existing = parse(path.read_text()) if path.exists() else {}
    merged = merge(existing, managed)
    if merged == existing:
        return False

    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".conf.toml.")
    try:
        with os.fdopen(fd, "wb") as f:
            tomli_w.dump(merged, f)
        os.replace(tmp, path)
    except BaseException:
        os.unlink(tmp)
        raise
    return True


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    managed = json.loads(Path(argv[1]).read_text())
    path = Path(argv[2]).expanduser()
    try:
        changed = apply(managed, path)
    except UnsupportedConfig as e:
        print(f"lsfg-vk: {e} ({path})", file=sys.stderr)
        return 1
    if changed:
        print(f"lsfg-vk: patched {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
