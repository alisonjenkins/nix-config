# Implementation Plan: Virtual Output Overview Column

**Branch**: `feat/virtual-overview-column` | **Date**: 2026-09-29 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/002-virtual-overview-column/spec.md`

## Summary

While the overview is open, each physical monitor reserves a band at its right edge and lays its
own workspaces out in the rest. The band holds one scrollable column listing every enabled
virtual output's workspaces as tiles. Each tile is a projection of one workspace, mapped into
the virtual output's **own overview coordinates**. As a result, the existing projection-aware
input path does the work unchanged: hit-testing, clicks, drag and drop, insert hints and
new-workspace drops. The band reservation is a small generic `Monitor` hook. Two event-stream
events report view mode and outputs turning on and off. 001's per-output columns are removed;
view mode is unchanged.

## Technical Context

**Language/Version**: Rust (edition 2021; toolchain from the fork's `nix develop`)

**Primary Dependencies**: smithay (as pinned by the fork), niri-ipc, niri-config, pango/cairo for labels

**Storage**: N/A (runtime state only)

**Testing**:
- `cargo test --workspace`, which runs the headless `src/tests` fixture tests (real input through
  `src/tests/input.rs`), the niri-ipc unit tests and the layout proptests.
- `egl_*` names for tests that need a renderer, since the Nix build skips `::egl`.
- clippy with `-D warnings`, and `fmt --check`.

**Target Platform**: Linux, the niri TTY backend (ali-desktop, DP-2 5120x1440 at 120 Hz), plus the headless backend for tests.

**Project Type**: Desktop compositor feature in a fork, built by nix-config as the `niri-virtual` flake input.

**Performance Goals**: The overview holds the viewer's refresh rate with 3 virtual outputs and their workspaces shown. Only visible tiles render. Source frame pacing is unchanged.

**Constraints**:
- **Streams unaffected (FR-030):** nothing changes in the source's own frame, apart from its
  overview no longer culling offscreen workspaces, which is invisible on its own screen.
- **Cursor:** stays physical (FR-021).
- **Behaviour with no band:** identical to upstream (FR-003).
- **Errors:** no panics.

**Scale/Scope**:
- 1 physical viewer.
- 1 to 12+ virtual outputs, 1280x800 to 2880x1800.
- About 1000 changed lines across roughly 12 files, plus tests.
- Removes about 400 lines of 001's column code.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | How |
|---|---|---|
| I. Atomic, revertable history | Pass | Ordered commits that each build and pass tests: the `Monitor` inset hook, then the offscreen-reachable hook, band and tile geometry (pure), tile projections replacing columns (render and state), band input, scroll routing, drag edge-scroll, each event, docs. Removing 001's column code is part of the commit that replaces it, so no commit leaves the overview without virtual outputs. |
| II. Test first, evidence | Pass | Every FR has a failing test first (quickstart table). Rendering order, crop and culling are `egl_*` tests. Manual steps cover only visuals and the live stream. |
| III. IaC, live changes by consent | Pass | Delivered by fork push, `nix flake update niri-virtual` and `just switch`, run by the user. Throwaway virtual outputs in the manual steps are created and removed by the user. |
| IV. Errors carry context | Pass | Invalid sizes, vanished workspaces and outputs are handled by skipping and logging with output and workspace names. No `unwrap`/`expect` outside tests. |
| V. Right altitude, single source | Pass | Reuses the projection chokepoint, `insert_position` and the existing drag-and-drop instead of a second drop-target path (R3). Inset and culling are single hooks on `Monitor`. Each event has one refresh hook. |
| VI. Record the why | Pass | ADR 0019 is amended, or a new ADR is added, in nix-config: the band over per-output columns, mapping tiles into the source's overview coordinates, and why the outputs event carries the full map. |
| VII. Fork patches are generated | Pass | Code only in the fork, as commits with tests. nix-config updates the `niri-virtual` input (constitution 1.0.1). |

Re-check after Phase 1: still passing. The one departure from the approved design is that tiles
map into the source's overview coordinates rather than normal coordinates, which removes the
explicit-target drag-and-drop hook (R3). It stays within the design's intent and adds no
complexity.

## Project Structure

### Documentation (this feature)

```text
specs/002-virtual-overview-column/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── events.md
├── checklists/
│   └── requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (niri fork, `/home/ali/git/niri`)

```text
src/
├── layout/monitor.rs             # overview_right_inset + overview_offscreen_reachable (setters,
│                                 #   applied in workspaces_render_geo, *_cull, workspace_under,
│                                 #   dnd_scroll_gesture_scroll); render_workspace_overview(idx)
├── layout/mod.rs                 # Layout setters forwarding to the named monitor
├── layout/tests.rs               # inset/cull invariants in the proptest ops
├── projection.rs                 # BAND_FRACTION, band_rect(), column_layout() (pure: groups,
│                                 #   tiles, scroll clamp/centre); ProjectionKind::Tile; drop
│                                 #   overview_columns + consts
├── niri.rs                       # ProjectionState bands + scroll; rebuild tiles; set monitor
│                                 #   hooks; resolve_output_under band marker; render band
│                                 #   (labels, highlight, tiles, fill) above viewer workspaces;
│                                 #   remove column code; ipc view-output hook call in refresh
├── ui/overview_band.rs           # NEW: labels + active-tile highlight + opaque fill (replaces
│                                 #   ui/overview_column_label.rs)
├── ui/mod.rs                     # module swap
├── input/mod.rs                  # wheel + swipe over band → column scroll
├── input/move_grab.rs            # edge-scroll the column while dragging
├── ipc/server.rs                 # ipc_refresh_view_output, ipc_refresh_outputs_event
├── ipc/client.rs                 # print ViewOutputChanged / OutputsChanged
└── tests/projection.rs           # rewritten column tests → band/tile tests; event recorder tests
niri-ipc/src/lib.rs               # Event::ViewOutputChanged, Event::OutputsChanged
niri-ipc/src/state.rs             # ViewOutputEventState, OutputsState (+ tests)
docs/Virtual-Outputs.md           # overview band, events
```

In nix-config:
- `flake.lock`: `niri-virtual` is bumped.
- `docs/adr/`: 0019 is amended, or a new ADR is added.
- `docs/steam-remote-play-streaming.md`: one line on the band.
- `specs/001-virtual-output-projection/spec.md`: its column FRs get a "superseded by 002" note.
- The scratch integration harness gains event-stream checks.

**Structure Decision**:
- **Layout changes:** only two opt-in `Monitor` hooks and one render helper, each inert when
  unset, which keeps the layout diff small and upstreamable.
- **Virtual-output knowledge:** stays in `niri.rs`, `projection.rs` and the new UI module.
- **Events:** follow the existing event-stream pattern exactly.

## Complexity Tracking

No constitution violations to justify.
