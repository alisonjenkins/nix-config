---
name: 3d-printing
description: >-
  Use when designing, slicing or printing a 3D-printed part on this PC: writing
  or fixing an OpenSCAD model or STL, checking a printed part is strong enough for its material,
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
| Never start a print unless the user asked for it in this conversation | It moves hardware, heats it, and uses filament. Asking to slice is not asking to print. |
| `scripts/printer.sh status` first; start only when it reports an idle state | A second job on a busy printer ruins both. |
| Never read, print or log the printer's API key or password from the Qidi Studio config | Only the host field is needed. |
| Never commit or push model or slicing files unless asked | Same as every repo. |
| Report an unchecked claim as unchecked | "Sliced" is not "printed well". Say what was and was not verified. |

## Scripts

- `scripts/slice.sh MODEL.stl PROCESS.json [OUTDIR]`: slices, checks the settings
  that landed in the 3mf, writes `MODEL.3mf` and `MODEL.gcode`.
- `scripts/printer.sh status | start FILE.gcode | cancel`: Moonraker control.
