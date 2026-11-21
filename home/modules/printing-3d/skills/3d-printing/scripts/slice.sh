#!/usr/bin/env bash
# Slice MODEL.3mf|MODEL.stl with the qidi-studio CLI for a Qidi X-Max 4 (0.4 nozzle) from
# flattened system presets plus a small overrides JSON. Writes MODEL.sliced.3mf and
# MODEL.gcode into OUTDIR (default: the model's directory) and prints a summary.
#   slice.sh MODEL.3mf|MODEL.stl OVERRIDES.json [OUTDIR]
# env: QIDI_PROCESS (default "0.20mm Standard @X-Max 4")
#      QIDI_FILAMENT_NAME (default "Generic PLA @Qidi X-Max 4 0.4 nozzle")
#      QIDI_SLOT (box slot 0-3 to print from; default 0)
#      QIDI_REFERENCE (a known-good project_settings.config JSON to diff against)
#      QIDI_PARTS (separate pieces the model should have; default 1; 0 skips the check)
set -euo pipefail

usage() { echo "usage: slice.sh MODEL.3mf|MODEL.stl OVERRIDES.json [OUTDIR]" >&2; exit 2; }
[[ $# -ge 2 && $# -le 3 ]] || usage

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
model="$(realpath "$1")"
overrides="$(realpath "$2")"
outdir="$(realpath -m "${3:-$(dirname "$model")}")"
name="$(basename "${model%.*}")"
slot="${QIDI_SLOT:-0}"
[[ "$slot" =~ ^[0-3]$ ]] || { echo "QIDI_SLOT must be 0-3, got '$slot'" >&2; exit 2; }

for tool in qidi-studio unzip python3; do
  command -v "$tool" >/dev/null || { echo "$tool not found on PATH" >&2; exit 1; }
done
for f in "$model" "$overrides"; do
  [[ -f "$f" ]] || { echo "missing file: $f" >&2; exit 1; }
done

# Refuse a model whose parts do not touch: it would print as loose pieces.
# QIDI_PARTS=0 skips the check (a model the checker cannot read).
parts="${QIDI_PARTS:-1}"
if [[ "$parts" != 0 ]]; then
  rc=0
  python3 -I "$here/check-model.py" "$model" --parts "$parts" || rc=$?
  case "$rc" in
    0) ;;
    1) exit 1 ;;
    *) echo "could not check $model (see above); fix the file, or set QIDI_PARTS=0 to skip the check" >&2; exit 1 ;;
  esac
fi

mkdir -p "$outdir"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
python3 -I "$here/flatten.py" "$work" \
  "${QIDI_PROCESS:-0.20mm Standard @X-Max 4}" \
  "${QIDI_FILAMENT_NAME:-Generic PLA @Qidi X-Max 4 0.4 nozzle}" "$overrides"

qidi-studio --slice 1 --arrange 1 \
  --load-settings "$work/machine.json;$work/process.json" \
  --load-filaments "$work/filament.json" \
  --export-3mf "$name.sliced.3mf" --outputdir "$outdir" "$model" >"$work/log" 2>&1 || true
rc="$(python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1]))["return_code"])' "$outdir/result.json" 2>/dev/null || echo "?")"
[[ "$rc" == 0 && -f "$outdir/$name.sliced.3mf" ]] || {
  echo "slice failed, return_code=$rc: $(grep -vE '\[(debug|info)\]' "$work/log" | tail -3)" >&2
  exit 1
}
rm -f "$outdir/result.json" "$outdir/plate_1.gcode"
unzip -p "$outdir/$name.sliced.3mf" Metadata/plate_1.gcode >"$outdir/$name.gcode"

# The CLI can only slice for the first filament. The gcode names the box slot in
# three places; point all at the wanted slot. A missed UNLOAD_FILAMENT makes the
# end of the print unload the wrong slot, fail, and pause the printer at 99%.
if [[ "$slot" != 0 ]]; then
  sed -i -e "s/^BOX_PRINT_START EXTRUDER=0 /BOX_PRINT_START EXTRUDER=$slot /" \
         -e "s/^T0\$/T$slot/" \
         -e "s/^UNLOAD_FILAMENT T=0\$/UNLOAD_FILAMENT T=$slot/" "$outdir/$name.gcode"
fi
if ! grep -q "^BOX_PRINT_START EXTRUDER=$slot " "$outdir/$name.gcode" ||
  ! grep -q "^UNLOAD_FILAMENT T=$slot\$" "$outdir/$name.gcode"; then
  echo "gcode does not use box slot $slot for start and unload" >&2
  exit 1
fi

echo "wrote $outdir/$name.sliced.3mf (slot unpatched) and $outdir/$name.gcode (slot $slot)"
unzip -p "$outdir/$name.sliced.3mf" Metadata/project_settings.config >"$work/ps.json"
python3 -I - "$work/ps.json" "${QIDI_REFERENCE:-}" <<'PY'
import json, sys
new = json.load(open(sys.argv[1]))
first = lambda v: v[0] if isinstance(v, list) and v else v
print("key settings in the 3mf:")
for k in ("print_settings_id", "filament_settings_id", "layer_height", "wall_loops",
          "sparse_infill_density", "enable_support", "curr_bed_type",
          "nozzle_temperature_initial_layer", "textured_plate_temp_initial_layer"):
    print("  %s: %s" % (k, first(new.get(k))))
if sys.argv[2]:
    ref = json.load(open(sys.argv[2]))
    skip = ("gcode", "colour", "filament_ids", "flush", "wipe_tower", "filament_map", "settings_id",
            "nozzle_map", "volume_map", "notes", "inherits", "host", "printhost", "thumbnails", "compatible")
    print("differences from the reference project (REF | NEW):")
    for k in sorted(set(ref) | set(new)):
        if any(s in k for s in skip):
            continue
        if first(ref.get(k)) != first(new.get(k)):
            print("  %s | %s | %s" % (k, str(first(ref.get(k)))[:40], str(first(new.get(k)))[:40]))
PY
echo "gcode summary:"
grep -m5 -E '^; (estimated printing time|total layer number|max_z_height|filament used \[cm3\])' "$outdir/$name.gcode" | sed 's/^/  /'
