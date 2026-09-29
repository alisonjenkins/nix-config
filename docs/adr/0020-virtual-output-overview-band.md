# 0020. Show virtual outputs in one overview band column

- Status: Accepted, pending live test
- Date: 2026-09-29
- Supersedes: the "Overview columns" part of [0019](0019-virtual-output-projection.md)

## Context

ADR 0019 showed each enabled virtual output as its own column to the right of DP-2's
workspaces in the overview. Live use showed two problems:

- **It did not scale.** Columns shrank as virtual outputs were added, so several became too
  small to use.
- **It collided with DP-2's overview.** niri crops overview workspaces only vertically, so a
  busy DP-2 workspace's windows ran into the columns. Input checked projections first, so a
  click on a DP-2 window there went to a virtual output instead.

Nothing outside the compositor could tell when view mode started or stopped, or when an
output turned on or off. The design and spec are in `specs/002-virtual-overview-column/`.

## Decision

- **A reserved band.** While the overview is open and a virtual output is on, each physical
  monitor reserves 15% of its width at the right edge. A generic `Monitor` hook (an overview
  right inset, scaled by the overview's open progress) centres DP-2's workspaces in the
  remaining width and stops them being hit-tested in the band. The band is opaque and drawn
  above DP-2's workspaces, so what shows there is what takes the click.
- **One scrolling column.** The band lists each virtual output, in configuration order, as a
  label followed by all its workspaces as tiles of one width. The wheel or a 3-finger swipe
  over the band scrolls it; dragging near its edges scrolls it too.
- **Tiles map into the source's own overview.** Each tile is a projection of one workspace,
  whose source rectangle is that workspace in the virtual output's *overview* geometry, not
  its normal layout. The existing projection-aware input path then does everything: clicks,
  focus, drag-and-drop targets, insert hints and new-workspace drops go through niri's own
  `insert_position`, with no second drop-target path. A second `Monitor` hook stops the
  virtual output culling workspaces outside its own screen while it is shown in a band.
- **Band background is not a drop target.** niri has no "no target" drop, so an interactive
  move now remembers where the window came from and returns it there when dropped on the band
  background.
- **Two events.** `ViewOutputChanged` (reusing the `view-output` response type) fires from one
  hook in the refresh loop, so every start and stop path is covered. `OutputsChanged` carries
  the full name-keyed output map and hangs off `refresh_ipc_outputs`, which every backend
  already goes through; it fires on connect, disconnect, on and off, not on mode changes alone.

## Alternatives rejected

- **Keep per-output columns and shrink them.** Unusable past two or three outputs.
- **A thumbnail grid, or one switchable slot.** Hides workspaces behind an extra step, which
  makes moving a window to a non-active virtual workspace slower.
- **Map tiles into the workspace's normal layout.** Needs a separate drag-and-drop target entry
  point in the layout code, kept in sync with niri's own.
- **Crop DP-2's workspaces at the band.** Finite horizontal crops cut pixel shaders and hit a
  damage bug; they also would not change hit-testing.
- **Separate connect/disconnect/enable/disable events.** More variants to keep consistent, and a
  reconnecting client would still need the whole list.

## Consequences

- DP-2's overview loses 15% of its width while a virtual output is on; with none on it is
  identical to upstream.
- While shown in a band, a virtual output's overview renders all its workspaces, not only the
  on-screen ones; the extra ones fall outside its own screen, so a stream does not change.
- Monitors shown in a band do not run their own drag edge-scroll, so dragging over a lower tile
  does not switch what the stream shows.
- Dropping between two virtual workspaces no longer creates a workspace (the gap is band
  background); the empty last tile does.
- The event stream has two new variants; strict clients must accept them.

## Evidence

- niri fork commits `be7da3af..09c5ef1d` on `rebase-feat-virtual`, from "add view-output and
  outputs events to the event stream" to "keep a virtual output's overview still while
  dragging over its tiles".
- Tests: `overview_band_tests`, `overview_band_render_tests`, `overview_column_tests`,
  `overview_drag_tests`, `src/tests/events.rs`, `src/layout/tests/overview_hooks.rs`; 426 lib
  tests pass.

## Revisit when

- The live check shows the band too narrow for readable tiles on DP-2, or frame drops with
  the overview open.
- niri gains native multi-output overview rendering.
- The virtual-output work goes upstream: the two `Monitor` hooks and the events are candidates
  to propose on their own.
