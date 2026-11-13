# Slicing with the qidi-studio CLI

`qidi-studio` (Qidi Studio, a Bambu Studio fork) slices headless. Check it is
there with `command -v qidi-studio` and the profiles with
`ls ~/.config/QIDIStudio/system`. `scripts/slice.sh` wraps everything below.
Give it a 3mf where possible (`openscad -o part.3mf part.scad`); STL also works.

## Base the slice on the user's own settings

The user already prints successfully from Qidi Studio. Match that, do not
invent settings. Ask which process, filament and plate they normally use, or
read them from a project they point at: its `Metadata/project_settings.config`
(inside the 3mf zip) lists `print_settings_id`, `filament_settings_id` and
`curr_bed_type`. Saved user presets live in
`~/.config/QIDIStudio/user/default/{process,filament}`.

`slice.sh` defaults to `0.20mm Standard @X-Max 4` and
`Generic PLA @Qidi X-Max 4 0.4 nozzle`; set `QIDI_PROCESS` and
`QIDI_FILAMENT_NAME` for anything else. List the choices with
`ls "$HOME/.config/QIDIStudio/system/X 4 Series/"{process,filament}`.

## Presets must be flattened

The CLI does not follow `inherits` for file-path presets. An override JSON that
inherits a system preset silently loses temperatures, fan, flow, speeds and
brim, and the print fails (a real failed print: shifting part, spider webbing).
`scripts/flatten.py` resolves the chain into self-contained JSONs and sets
`from: system` and `instantiation: true`; without those the CLI stops with
`return_code -17` (printer not compatible with process preset).

Overrides are a flat JSON of only the settings that differ, for example:

```json
{ "wall_loops": "5", "sparse_infill_density": "40%", "sparse_infill_pattern": "gyroid",
  "enable_support": "0", "curr_bed_type": "Textured PEI Plate" }
```

## Verify against a known-good project

Always run with `QIDI_REFERENCE` pointing at a `project_settings.config` from a
print that worked (extract it with `unzip -p proj.3mf Metadata/project_settings.config`).
The script prints every setting that differs. Only the overrides you meant
should show. Anything else (temperatures, fan, flow, brim) means the slice is
wrong; fix it before printing. Do not trust the setting names alone.

## Filament slots (Qidi box)

Slots 1A to 1D are box slots 0 to 3, gcode `T0` to `T3`. The CLI only slices
reliably for the first filament (a part assigned to filament 2 or 3 fails with
"Levitating objects cannot be printed without supports"), so `slice.sh`
slices for slot 0 and then rewrites the three slot references in the gcode
(`BOX_PRINT_START EXTRUDER=n`, `Tn` and the end-of-print `UNLOAD_FILAMENT T=n`) when `QIDI_SLOT=n`. This matches how the
user's own multi-colour gcode numbers tools. Confirm the colour and slot with
the user (a screenshot of the box panel works); the filament profile is the same
for any slot of the same material.

## Gotchas

- `--outputdir` is where the 3mf goes. A temporary directory there loses it.
  `slice.sh` names its output `MODEL.sliced.3mf` so a 3mf input is never overwritten.
- The sliced gcode is inside the 3mf as `Metadata/plate_1.gcode`.
- The filament weight can read 0 g for generic profiles. Use the volume (cm3)
  times the material's density (PLA about 1.24 g/cm3) for an estimate, and say
  it is an estimate.
- `max_z_height` in the gcode header should equal the model width when the part
  lies on its side. If it equals the height, the part is standing up.
- The bed type must match the plate fitted. The user's
  `curr_bed_type` is in `~/.config/QIDIStudio/QIDIStudio.conf`; confirm the
  plate with them.
- Report time, layers and volume from the gcode header lines
  `; estimated printing time`, `; total layer number` and `; filament used [cm3]`.
