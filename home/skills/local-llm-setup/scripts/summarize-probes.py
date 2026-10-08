import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
for run in sorted(p for p in root.iterdir() if p.is_dir()):
    load = run / "load.json"
    speed = run / "probe" / "speed.json"
    safety = run / "probe" / "safety.json"
    row = {"run": run.name}
    if load.exists():
        d = json.loads(load.read_text())
        row["load_s"] = d["load_seconds"]
        row["vram_gib"] = round((d["vram_loaded"] - d["vram_idle"]) / 2**30, 2)
    if speed.exists():
        s = json.loads(speed.read_text())
        row["speed"] = {k: s[k] for k in s if k not in ("runs", "samples")}
    if safety.exists():
        s = json.loads(safety.read_text())
        items = s if isinstance(s, list) else s.get("results", s)
        if isinstance(items, list):
            row["safety"] = {i.get("id", i.get("name")): ("PASS" if i.get("pass") else "FAIL") for i in items}
        else:
            row["safety_raw_keys"] = list(items)[:8]
    print(json.dumps(row))
