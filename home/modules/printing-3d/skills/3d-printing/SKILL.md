---
name: 3d-printing
description: >-
  Use when designing, slicing or printing a 3D-printed part on this PC: writing
  or fixing an OpenSCAD model, 3mf or STL, checking a printed part is strong enough for its material,
  slicing for the Qidi X-Max 4 with the qidi-studio CLI (a 3mf or gcode that
  opens in Qidi Studio), and starting, watching or cancelling a print over
  Moonraker. Not for non-printed CAD or for other printers.
---

# 3D printing: design, slice, print

One part goes through five steps (0 to 4). A standalone status or cancel
request skips them: run `scripts/printer.sh` at once. Starting a print runs all
of them. Do them in order and state progress each turn
("step 2 of 4 done: ..."). Each step has a leaf file; read it before doing the step.

| Step | Do | Read |
|---|---|---|
| 0 | Ask which materials are available and pick one for the job | [design.md](design.md#choose-the-material) |
| 1 | Pin down what is unknown, then model it parametrically in OpenSCAD | [design.md](design.md) |
| 2 | Hand-check strength and fit for the material before printing | [design.md](design.md#strength-check) |
| 3 | Slice with the `qidi-studio` CLI into a 3mf Qidi Studio opens | [slicing.md](slicing.md) |
| 4 | Upload, start, watch or cancel over Moonraker | [printing.md](printing.md) |

## This machine

- Printer: Qidi X-Max 4, 0.4 mm nozzle. Its address is read from
  the Qidi Studio config at run time, never written down here.
- Qidi Studio's own CLI does the slicing, so the result matches what the user
  sees in the GUI. Do not slice with another slicer and hand over its file.
- Materials are not fixed. The printer has a Qidi filament box and can print
  other materials than the ones loaded today. Ask the user which materials they
  have before designing (step 0 in design.md); do not assume one. If the best
  material for the job is one they lack, say so and let them decide whether to buy it.

## Rules

| Rule | Why |
|---|---|
| Prefer 3mf over STL for model files, in and out | 3mf keeps units and is what Qidi Studio uses; STL is the legacy format |
| Never start a print unless the user asked for it in this conversation | It moves hardware, heats it, and uses filament. Asking to slice is not asking to print. |
| `scripts/printer.sh status` first; the printer must report an idle state | A second job on a busy printer ruins both. |
| Idle is not permission: get the user's confirmation that the bed is clear and ready for this print, then pass `--bed-clear` | The printer cannot see the bed. The user may not have removed the last part, or may be partway through doing it. A "print it" request does not confirm this. |
| Never read, print or log the printer's API key or password from the Qidi Studio config | Only the host field is needed. |
| Never commit or push model or slicing files unless asked | Same as every repo. |
| Report an unchecked claim as unchecked | "Sliced" is not "printed well". Say what was and was not verified. |

## Scripts

- `scripts/slice.sh MODEL.3mf|MODEL.stl OVERRIDES.json [OUTDIR]`: flattens the
  presets, slices, prints the settings that landed (and the diff against a
  known-good project with `QIDI_REFERENCE`), writes `MODEL.sliced.3mf` and
  `MODEL.gcode`. `QIDI_SLOT=0-3` picks the filament box slot.
- `scripts/check-model.py MODEL.3mf|STL [--parts N]`: fails when the model is not
  the expected number of solid pieces. `slice.sh` runs it first.
- `scripts/flatten.py`: resolves preset `inherits` chains; used by `slice.sh`.
- `scripts/printer.sh status | start FILE.gcode --bed-clear | cancel | off`:
  Moonraker control. `start` refuses without `--bed-clear`, which you pass only
  after the user confirms the bed. `off` switches the case light and all heaters
  (box, nozzle, bed, chamber) off on an idle printer.
