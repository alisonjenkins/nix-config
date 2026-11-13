"""Flatten Qidi Studio system presets into self-contained JSONs for the CLI.

The CLI does not follow `inherits` for file-path presets, so an unflattened
override silently loses every inherited value (temperatures, fan, flow, speeds,
brim). Usage:
  flatten.py OUTDIR PROCESS_NAME FILAMENT_NAME [OVERRIDES.json]
Writes OUTDIR/{machine,filament,process}.json. Names are preset names, e.g.
"0.20mm Standard @X-Max 4" and "Generic PLA @Qidi X-Max 4 0.4 nozzle".
"""
import glob
import json
import os
import sys

if len(sys.argv) not in (4, 5):
    sys.exit(__doc__)
out, process_name, filament_name = sys.argv[1:4]
overrides = json.load(open(sys.argv[4])) if len(sys.argv) == 5 else {}
machine_name = os.environ.get("QIDI_MACHINE_NAME", "X-Max 4 0.4 nozzle")
sysdir = os.environ.get("QIDI_SYSTEM_DIR", os.path.expanduser("~/.config/QIDIStudio/system/X 4 Series"))

idx = {}
for path in glob.glob(sysdir + "/*/*.json"):
    try:
        d = json.load(open(path))
    except (OSError, ValueError):
        continue
    if isinstance(d, dict) and "name" in d:
        idx[d["name"]] = d


def resolve(name):
    if name not in idx:
        sys.exit("unknown preset %r under %s" % (name, sysdir))
    d = idx[name]
    base = resolve(d["inherits"]) if d.get("inherits") else {}
    merged = dict(base)
    merged.update(d)
    merged.pop("inherits", None)
    return merged


def flat(name, kind, extra=None, new_name=None):
    d = resolve(name)
    d.update(extra or {})
    d["type"] = kind
    d["name"] = new_name or name
    # from=system + instantiation=true is what passes the CLI's printer/process
    # compatibility check (error -17 otherwise).
    d["from"] = "system"
    d["instantiation"] = "true"
    return d


os.makedirs(out, exist_ok=True)
for kind, name, extra, new in (
    ("machine", machine_name, None, None),
    ("filament", filament_name, None, None),
    ("process", process_name, overrides, process_name + " (flattened)"),
):
    with open("%s/%s.json" % (out, kind), "w") as f:
        json.dump(flat(name, kind, extra, new), f, indent=1)
