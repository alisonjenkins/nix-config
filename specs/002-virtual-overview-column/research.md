# Research: Virtual Output Overview Column

All paths are in the niri fork (`/home/ali/git/niri`, branch `rebase-feat-virtual`) unless stated.
Line numbers are as of commit `be7da3af`.

## R1. Reserving the band in the viewer's overview

- **Decision**: Add a per-monitor overview right inset to `Monitor`, set by `Niri` through a
  setter, following the `Monitor::update_layout_config` pattern (`src/layout/monitor.rs:1211`).
  `Layout`/`Monitor` stay unaware of virtual outputs. The inset is multiplied by the overview
  progress inside `Monitor`, so the strip slides with the zoom animation. Apply it at every place
  that derives overview geometry from `view_size`:
  - `workspaces_render_geo` (`monitor.rs:1475`): centre the strip in `view_size.w − inset`
    (`static_offset` x).
  - `workspaces_with_render_geo_cull` / `_idx` / `_mut` (`monitor.rs:1503-1538`): the cull
    rectangle `output_geo` loses the inset width.
  - `workspace_under` (`monitor.rs:1540-1552`): the extended hit width stops at
    `view_size.w − inset` instead of `view_size.w`.
  - `dnd_scroll_gesture_scroll` (`monitor.rs:1968-1969`): it duplicates the centring maths; use
    the same inset-aware centre. `insert_position` (`monitor.rs:1602`) and the render and shadow
    passes follow from the geometry functions and need no separate change.
- **Rationale**: One small, generic hook ("the overview has a reserved right edge") that could be
  upstreamed on its own. Every hit-test, insert-hint and scroll path already reads geometry from
  these functions, so the band can never be reached through DP-2's own layout.
- **Alternatives considered**: Clipping DP-2's rendering at the band: finite horizontal crops cut
  pixel shaders and hit a damage bug (`monitor.rs:1738-1753`), and it would not change
  hit-testing. Shrinking `view_size`: changes window sizes and the working area, not just the
  overview.

## R2. What draws on top, and horizontal overflow

- **Decision**: Draw the band (labels, highlight, tiles, opaque fill) before DP-2's workspaces in
  the element list, so it sits on top, as the last fix already does for columns.
- **Rationale**: `render_workspaces` crops workspaces only vertically in the overview
  (`monitor.rs:1743-1750`, the "infinite bounds horizontally" hack), so a scrolled workspace's
  columns still render past the strip. The inset stops them being hit-testable; the opaque band on
  top stops them being visible there. Picture and input then agree (001 lesson).
- **Alternatives considered**: Cropping DP-2's workspaces horizontally: rejected for the shader
  and damage reasons in R1.

## R3. What a tile projects, and why it maps into the source's overview coordinates

- **Decision**: A tile is a `Projection` whose `source_rect` is that workspace's rectangle from
  the **source monitor's own overview geometry** (`Monitor::workspaces_render_geo` on the virtual
  output while the overview is open), not its normal non-overview geometry.
- **Rationale**: This changes the approved design's detail ("normal coordinates") for a large
  reuse win. `resolve_output_under` (`src/niri.rs:3784`) already maps any projection hit to
  `(source output, position within it)`, and everything downstream consumes exactly that:
  `workspace_under`, `window_under`, `contents_under` focus synthesis (`niri.rs:4274-4310`),
  overview clicks (`niri.rs:2965-3087` → `activate_overview_workspace`), and drag and drop,
  whose targets come from `Monitor::insert_position` (`monitor.rs:1602`), including
  `InsertWorkspace::NewAt` for the empty last workspace. `src/tests/projection.rs:774-785`
  already drives an interactive move through a projection. So **no explicit-target
  drag-and-drop hook is needed** in `Layout`; insert hints, reordering and new-workspace drops
  behave exactly as between DP-2's own workspaces.
- **Consequence**: A virtual monitor's overview only places a few workspaces on its own screen,
  and `workspaces_with_render_geo_cull` culls the rest from rendering and hit-testing. Add a
  per-monitor "overview offscreen workspaces reachable" flag (same setter pattern as R1), set by
  `Niri` for every virtual output that is a tile source. With it set, culling uses no bounds for
  that monitor, so every workspace has elements and hit-test geometry. `workspaces_render_geo`
  already returns geometry for every index, plus one past the last.
- **Alternatives considered**: Normal geometry plus a new `Layout::interactive_move_update_to`
  entry point (the approved design's detail): more new layout code and a second drop-target
  path to keep in sync. Scrolling each source's own overview to reveal tiles: nested scrolling,
  and it moves what the stream shows.

## R4. Rendering one workspace per tile

- **Decision**: Add `Monitor::render_workspace_overview(ws_idx, renderer, focus_ring, push)`,
  which renders one workspace exactly as `render_workspaces` does (background, scrolling and
  floating layers, shadow, insert hint when it targets that workspace, at the overview zoom and
  position) but for that workspace only and without culling. `Niri` wraps each element in
  `ProjectedElement::new(elem, source_scale, tile.source_rect, viewer_scale, tile.region)`
  (`src/render_helpers/projected.rs:37`) and `CropRenderElement` to the tile, as
  `render_projected_source` does today (`niri.rs:5663-5690`).
- **Rationale**: `render_projected_source` renders the source's whole frame via `render_with`
  (`niri.rs:5254`), which includes its layer-shell surfaces and only its on-screen workspaces;
  the spec excludes bars and needs every workspace. Per-workspace rendering also lets offscreen
  tiles be skipped before any element is built. Crop at the tile edge is acceptable: it is where
  the workspace visibly ends.
- **Alternatives considered**: Render the source frame once and crop it per tile: includes bars,
  misses culled workspaces, and multiplies element wrapping by the tile count.

## R5. Active-workspace highlight

- **Decision**: Draw a new border around each virtual output's active tile using the configured
  focus ring's active colour and width (`options.focus_ring`), via a `FocusRing`-style border
  element in a small new UI module alongside the labels.
- **Rationale**: niri has no workspace-level overview highlight to reuse; workspace shadows apply
  to all workspaces and the focus ring is per window (`workspace.rs:1658-1703`). Reusing the
  focus ring's colours keeps it on-theme.
- **Alternatives considered**: No highlight: the user cannot tell which virtual workspace is
  showing on the stream.

## R6. Column scrolling and input routing

- **Decision**: Wheel and touchpad swipes: branch before `should_handle_in_overview`
  (`src/input/mod.rs:3149-3163`) and before the overview gesture calls in
  `on_gesture_swipe_begin/update/end` (`input/mod.rs:3950-4160`). If the pointer's physical
  position is inside a viewer's band, apply the delta to that viewer's column scroll offset and
  consume it. Drag edge-scroll: in the move grab's motion (`src/input/move_grab.rs:232`), when the
  pointer is within an edge zone of a band, advance that column's offset per frame, the same way
  `dnd_scroll_gesture_*` scroll DP-2.
- **Rationale**: These handlers ignore pointer position today, so scrolling over the band would
  switch DP-2's workspaces. Routing by the physical output keeps the cursor-teleport rule.
- **Alternatives considered**: Resolving scrolls through projections into the source's overview:
  would scroll the source's own overview, which the stream shows.

## R7. Band hit-testing without fall-through

- **Decision**: In `resolve_output_under`, a position inside a viewer's band that hits no tile
  resolves to the viewer with a new `OutputUnder::band` marker, so clicks there are no-ops. The
  `shows_columns`/`top_layer_above` special case (`niri.rs:3798-3813`), which lets the viewer's top
  layer take input over columns, carries over to the band.
- **Rationale**: FR-012/FR-015: band input must never reach DP-2 or close the overview.

## R8. The two events

- **Decision**: Follow the `OverviewOpenedOrClosed` pattern exactly: an `Event` variant
  (`niri-ipc/src/lib.rs:1697`), a state part with `replicate`/`apply` registered in
  `EventStreamState` (`niri-ipc/src/state.rs:33-48`, `264-280`), an `ipc_refresh_*` hook on
  `State` in `src/ipc/server.rs` (pattern at `server.rs:865-882`), and a print arm in
  `src/ipc/client.rs:507-512`. New subscribers get state through `replicate()`
  (`server.rs:243-260`).
  - `ViewOutputChanged { state: ViewOutputState }`: `ipc_refresh_view_output` compares
    `projection_state.viewing` with the stream state and sends on change. Called from
    `State::refresh` after `stop_viewing_if_viewer_active`, so every start and stop path
    (`start_viewing_on`, `stop_viewing(reason)`, `on_viewing_lost`) is covered by one hook.
  - `OutputsChanged { outputs: HashMap<String, Output> }`: hung off `State::refresh_ipc_outputs`
    (`niri.rs:2169`), the single choke point already gated by `ipc_outputs_changed`, which
    every backend sets on any output change (`tty.rs:2456`, `winit.rs:140`, `niri.rs:1988`,
    `niri.rs:3070`). Keyed by connector name like `Response::Outputs`. Sent only when the set of
    outputs or any output's on/off state (`current_mode`/`logical` presence) differs from the
    stream state (spec assumption: mode/scale-only changes are not reported).
- **Rationale**: One central hook per event means no start/stop or connect path can be missed.
  No upstream prior art exists for an outputs event (searched niri-wm/niri issues, PRs and
  discussions); event additions are treated as protocol changes there (niri-wm/niri#4044), so
  the variant reuses the existing `Output` type rather than inventing a new shape.
- **Alternatives considered**: Separate `OutputConnected`/`OutputDisconnected`/`OutputEnabled`
  events: more variants to keep consistent, and a client would still need the full list after
  reconnecting. Reporting every `ipc_outputs_changed`: would fire on every mode or logical
  position change, which the spec leaves out.

## R9. Testing the events

- **Decision**: Test the `EventStreamStatePart` logic (`apply`/`replicate`) in the niri-ipc crate,
  and the compositor side through a small test helper that runs the `ipc_refresh_*` hooks on the
  fixture's `State` and records emitted events, instead of a live socket.
- **Rationale**: The test `Fixture` has no `IpcServer` today (`src/tests/fixture.rs`), and no
  event-stream tests exist. A recorder at the `send_event` boundary tests exactly the logic this
  feature adds.

## R10. Code removed

- **Decision**: Remove `overview_columns()` and its constants (`src/projection.rs:158-206`),
  `workspace_strip()` (`niri.rs:8273`), `overview_projections()` (`niri.rs:3704-3763`) in its
  per-output form, `render_overview_projections()` (`niri.rs:5585-5644`), `overview_column_backings`
  (`niri.rs:471`, `3390-3408`), and `src/ui/overview_column_label.rs` (replaced by the new band
  UI). Column-specific tests in `src/tests/projection.rs` are rewritten for tiles (drag, drop,
  new workspace, reorder, click-to-view, source removal) or removed where they only assert the
  shrink maths. View mode (`view_projection`, `view_projection_on`, `ProjectionKind::View`) is
  untouched.
