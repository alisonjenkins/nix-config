#!/usr/bin/env bash
# Slice MODEL.stl with the qidi-studio CLI for a Qidi X-Max 4 (0.4 nozzle,
# Generic PLA unless QIDI_FILAMENT names another profile) using a process override JSON. Writes MODEL.3mf and MODEL.gcode
# into OUTDIR (default: the model's directory) and prints a summary.
set -euo pipefail

usage() { echo "usage: slice.sh MODEL.stl PROCESS.json [OUTDIR]" >&2; exit 2; }
[[ $# -ge 2 && $# -le 3 ]] || usage

model="$(realpath "$1")"
process="$(realpath "$2")"
outdir="$(realpath "${3:-$(dirname "$model")}")"
name="$(basename "${model%.*}")"

for tool in qidi-studio unzip python3; do
  command -v "$tool" >/dev/null || { echo "$tool not found on PATH" >&2; exit 1; }
done

sys="${QIDI_SYSTEM_DIR:-$HOME/.config/QIDIStudio/system/X 4 Series}"
machine="${QIDI_MACHINE:-$sys/machine/Qidi X-Max 4 0.4 nozzle.json}"
filament="${QIDI_FILAMENT:-$sys/filament/Generic PLA @Qidi X-Max 4 0.4 nozzle.json}"
for f in "$model" "$process" "$machine" "$filament"; do
  [[ -f "$f" ]] || { echo "missing file: $f" >&2; exit 1; }
done

mkdir -p "$outdir"
qidi-studio --slice 1 --arrange 1 \
  --load-settings "$machine;$process" \
  --load-filaments "$filament" \
  --export-3mf "$name.3mf" --outputdir "$outdir" "$model" >/dev/null

[[ -f "$outdir/$name.3mf" ]] || { echo "slice produced no 3mf in $outdir" >&2; exit 1; }
unzip -p "$outdir/$name.3mf" Metadata/plate_1.gcode >"$outdir/$name.gcode"

echo "wrote $outdir/$name.3mf and $outdir/$name.gcode"
echo "settings in the 3mf:"
unzip -p "$outdir/$name.3mf" Metadata/project_settings.config |
  python3 -I -c '
import json, sys
d = json.load(sys.stdin)
for k in ("print_settings_id", "filament_settings_id", "layer_height", "wall_loops",
          "sparse_infill_density", "enable_support", "curr_bed_type",
          "nozzle_temperature_initial_layer", "textured_plate_temp_initial_layer"):
    print(f"  {k}: {d.get(k)}")
'
echo "gcode summary:"
grep -m5 -E '^; (estimated printing time|total layer number|max_z_height|filament used \[cm3\])' "$outdir/$name.gcode" | sed 's/^/  /'
