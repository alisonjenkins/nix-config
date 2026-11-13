# Slicing with the qidi-studio CLI

`qidi-studio` (Qidi Studio, a Bambu Studio fork) slices headless. Check it is
there with `command -v qidi-studio` and the profiles with
`ls ~/.config/QIDIStudio/system`. `scripts/slice.sh` wraps everything below.

## Profiles

Read-only system profiles are under
`~/.config/QIDIStudio/system/X 4 Series/` (override with `QIDI_SYSTEM_DIR`):

| Kind | File |
|---|---|
| Machine | `machine/Qidi X-Max 4 0.4 nozzle.json` |
| Filament | `filament/Generic PLA @Qidi X-Max 4 0.4 nozzle.json` |
| Process (base) | `process/0.20mm Balanced Strength @X-Max 4.json` |

Never edit these. Write a small process override that inherits one:

```json
{ "type": "process", "name": "My part @X-Max 4", "from": "User",
  "inherits": "0.20mm Balanced Strength @X-Max 4",
  "wall_loops": "5", "sparse_infill_density": "40%",
  "curr_bed_type": "Textured PEI Plate", "enable_support": "0",
  "compatible_printers": ["X-Max 4 0.4 nozzle"] }
```

Strong-part defaults: 5 wall loops, 40 percent gyroid, 0.2 mm layers, no
supports for a part drawn as in design.md. Plain PLA: raise `nozzle_temperature`
a little for layer bonding only if the user wants more strength.

## The command

```bash
qidi-studio --slice 1 --arrange 1 \
  --load-settings "MACHINE.json;PROCESS.json" \
  --load-filaments "FILAMENT.json" \
  --export-3mf part.3mf --outputdir OUTDIR part.stl
```

Gotchas:

- `--outputdir` is where the 3mf goes. A temporary directory there loses it.
- Settings in `--load-settings` apply to the 3mf; always confirm they landed by
  reading `Metadata/project_settings.config` from the 3mf (it is a zip):
  `unzip -p part.3mf Metadata/project_settings.config`. Check `wall_loops`,
  `sparse_infill_density`, `curr_bed_type` and the bed and nozzle temperatures.
- The sliced gcode is inside the 3mf as `Metadata/plate_1.gcode`.
- The filament weight reads 0 g for Generic PLA. Use the volume (cm3) and the
  PLA density of about 1.24 g/cm3 for an estimate, and say it is an estimate.
- The `max_z_height` in the gcode header should equal the model width when the
  part lies on its side. If it equals the height, the part is standing up.
- The bed type must match the plate the user has. Their Qidi Studio setting
  `curr_bed_type` is in `~/.config/QIDIStudio/QIDIStudio.conf`. The value 4 is
  textured PEI in Bambu Studio's enum; that mapping is assumed to hold for Qidi
  Studio, so confirm the plate with the user.
- Slicing is quiet and fast (under a second). Report time, layers and volume
  from the gcode header lines `; estimated printing time`, `; total layer number`
  and `; filament used [cm3]`.
