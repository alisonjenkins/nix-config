# Implementation Plan: Virtual Output Projection

**Branch**: `001-virtual-output-projection` | **Date**: 2026-09-28 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-virtual-output-projection/spec.md`

## Summary

Physical monitors show virtual outputs in two ways:
- as extra columns in the overview, one per enabled virtual output, each being that output's
  real, interactive overview;
- in a letterboxed "view mode" entered with `view-output`.

The mechanism is a **projection**, which maps a rectangle of a virtual output onto a region of
a physical monitor. Rendering wraps the source's own render elements (rescale, relocate,
crop). Input resolves through one projection-aware `Niri::output_under`, so niri's existing
hit-testing, overview clicks, drag and drop, and new-workspace drops work across outputs with
no changes to layout code. The work lands in the niri fork and reaches ali-desktop through the
regenerated `patches/niri-virtual-outputs.patch`.

## Technical Context

**Language/Version**: Rust (edition 2021; toolchain from the fork's `nix develop`)

**Primary Dependencies**: smithay (git rev `4cf0b62`), niri-ipc, niri-config (KDL), pango/cairo for the label

**Storage**: N/A (runtime state only)

**Testing**: `cargo test` with inline unit tests, headless `src/tests` fixture tests and the existing layout proptests; `cargo clippy -D warnings`; `cargo fmt --check`

**Target Platform**: Linux, niri TTY backend (ali-desktop, AMD RDNA4) and the headless backend for tests

**Project Type**: Desktop compositor feature, carried as a fork patch

**Performance Goals**: The overview and view mode keep the viewer at its refresh rate (120 Hz on DP-2) with one virtual output projected. The source's own frame pacing is unchanged.

**Constraints**:
- A stream from the source must not change (FR-016), so the source's own render path is untouched.
- No recursion (FR-018).
- The cursor stays on the viewer (FR-017).

**Scale/Scope**:
- 1 viewer (DP-2, 5120x1440).
- 1 to 3 virtual outputs, typically `steam` at 1280x800 to 2880x1800.
- About 900 lines of Rust across roughly 12 files, plus tests.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | How |
|---|---|---|
| I. Atomic, revertable history | Pass | Tasks map to commits that each build and test green: pure maths, classification helper, state, input chokepoint, rendering, overview click, IPC, label. |
| II. Test first, evidence | Pass | Every behaviour has a failing test first (unit or fixture). Rendering glue that cannot be unit-tested is named in the quickstart's manual steps. |
| III. IaC, live changes by consent | Pass | Delivered by patch plus `just switch`. The live checks (quickstart manual steps) are run only after the user switches. |
| IV. Errors carry context | Pass | New `VirtualOutputError` variants name the output. No `unwrap` outside tests. clippy and fmt gates. |
| V. Right altitude, single source | Pass | One chokepoint rather than about 25 per-call edits. It reuses the existing overview wrappers, DnD and interactive move. No layout changes. |
| VI. Record the why | Pass | An ADR in nix-config `docs/adr/` records the projection design and the rejected alternatives (native multi-output rendering, mirror client). |
| VII. Fork patches are generated | Pass | Code only in `/home/ali/git/niri`. The patch is regenerated with `git diff e9b215fe HEAD`. `.specify/` stays in nix-config. |

Re-check after Phase 1: still passing. The only design bend is the drag-delta caveat (R3), which is accepted and documented, not a principle violation.

## Project Structure

### Documentation (this feature)

```text
specs/001-virtual-output-projection/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── view-output.md
├── checklists/
│   └── requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (niri fork, `/home/ali/git/niri`)

```text
src/
├── projection.rs                 # NEW: Projection, ProjectionKind, overview_columns (pure) + unit tests
├── niri.rs                       # ProjectionState field; rebuild(); output_under chokepoint;
│                                 #   output_under_cursor via chokepoint; render_inner projection
│                                 #   push; redraw cascade; OutputRenderElements::Projected variant
├── lib.rs                        # mod projection
├── backend/virtual_output.rs     # is_virtual_output(); new VirtualOutputError variants
├── input/mod.rs                  # do_action ViewOutput; overview click → view mode for virtual ws
├── input/move_grab.rs            # overview click-through path (line ~98) → view mode for virtual ws
├── input/touch_overview_grab.rs  # same for touch (line ~209)
├── ipc/server.rs                 # Request::ViewOutput handler
├── ipc/client.rs                 # `niri msg view-output [NAME]` + response printing
├── ui/view_output_label.rs       # NEW: 2 s "Viewing: <name>" / error label
├── ui/mod.rs                     # mod view_output_label
└── tests/projection.rs           # NEW: headless fixture tests
niri-ipc/src/lib.rs               # Request/Response/Action ViewOutput, ViewOutputState
niri-config/src/binds.rs          # Action::ViewOutput parse
docs/Virtual-Outputs.md           # (fork doc from the patch) document view-output + overview columns
```

In nix-config: `patches/niri-virtual-outputs.patch` (regenerated), `docs/adr/0019-virtual-output-projection.md`, and `docs/steam-remote-play-streaming.md` (a link).

**Structure Decision**: This is a single Rust workspace (the niri fork). New logic goes in one new pure module (`projection.rs`) and one new UI widget. Existing files change only at the named integration points.

## Complexity Tracking

No constitution violations to justify.
