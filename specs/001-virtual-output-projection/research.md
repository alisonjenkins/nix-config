# Research: Virtual Output Projection

All paths are in the niri fork (`/home/ali/git/niri`, branch `rebase-feat-virtual`) unless stated.
Line numbers are as of commit `b99d957a`.

## R1. Where pointer positions become outputs

- **Decision**: Make `Niri::output_under` (`src/niri.rs:3078`) projection-aware and route the two
  other direct `global_space.output_under` users through it. `output_under_cursor`
  (`src/niri.rs:3494`) becomes `self.output_under(pointer.current_location())`. The motion clamp
  in `src/input/mod.rs:2557-2582` keeps using `global_space` on purpose: it clamps the *real*
  cursor to real outputs, which is correct because the cursor stays on the viewer.
- **Rationale**: About 25 input call sites already go through `Niri::output_under`: move grab,
  touch overview grab, DnD, clicks, tablet and pick-color. `contents_under`,
  `workspace_under` and `workspace_under_cursor` build on it. Changing one function covers
  them.
- **Alternatives considered**: Teleporting the cursor into the virtual output's coordinates. That
  was rejected because overview columns need the cursor to move continuously between the
  viewer's own workspaces and the projected columns.

## R2. Overview geometry and hit-testing

- **Decision**: A projection maps a rectangle in the source (`source_rect`) onto a rectangle on
  the viewer (`region`) with one uniform scale.
  - In the overview, `source_rect` is the source monitor's own overview workspace strip. It is
    the horizontal extent of `Monitor::workspaces_render_geo` (`src/layout/monitor.rs:1475`) over
    the full output height, and the source already lays it out at the overview zoom.
  - The strip is shown at scale 1 in logical pixels, so its workspaces appear at the same zoom
    as the viewer's own. Scale drops below 1 only when the row does not fit (FR-009).
  - A pure `overview_columns(viewer_strip, viewer_size, sources)` places the regions to the
    right of the viewer's own strip and leaves the strip where niri draws it (see
    data-model.md, amended during implementation).
  - Everything inside a column is the source's own `Monitor` state, reached through
    `Projection::to_source`.
- **Rationale**: `Monitor::workspace_under` (`monitor.rs:1547`) extends workspace bounds to the
  full output width, so a viewer-local position inside a projected column would hit the
  viewer's workspace unless projection is resolved first. Resolving in `Niri::output_under`
  before any `Monitor` method runs avoids touching `Monitor`.
- The source's `Monitor` is already in overview mode when the viewer is, because overview
  state is global (`Layout::toggle_overview`, `src/layout/mod.rs:4629`). Its own
  `workspace_under`, `window_under` (with the zoom downscale at `monitor.rs:1570-1584`) and
  `insert_position` (`monitor.rs:1595`) therefore give correct answers in *source* coordinates.

## R3. Drag and drop across outputs

- **Decision**: No new drag code. `Layout::interactive_move_update` (`src/layout/mod.rs:3887`)
  and `Layout::dnd_update` (`mod.rs:4388`) take `(output, pointer_pos_within_output)` from
  `Niri::output_under` in `src/input/move_grab.rs:225,270`, `src/input/touch_overview_grab.rs:156`
  and `src/input/mod.rs:2684,2780,4458`.
- **Rationale**: Once `output_under` returns `(source, source_pos)`, moving into a column is
  identical to crossing onto a real second monitor, a path the layout already supports,
  including `InsertWorkspace::NewAt` drop hints (`monitor.rs:1595`, consumed at
  `mod.rs:4064,4201-4249`).
- **Caveat found**: `interactive_move_update` divides the pointer delta by
  `Layout::overview_zoom()`. A column shrunk below the viewer's zoom (FR-009) scales drag
  deltas slightly wrong inside that column. This is accepted, because the drop target comes
  from the absolute position, not the delta.

## R4. Clicking a workspace in the overview

- **Decision**: In the mouse branch at `src/input/mod.rs:3047-3057`, after
  `workspace_under_cursor(false)` resolves `(output, ws)`, check whether `output` is virtual.
  If it is, call `focus_output(source)`, then `toggle_overview_to_workspace(idx)`, then start
  view mode on the viewer. Apply the same check in `TouchOverviewGrab::on_ungrab`
  (`touch_overview_grab.rs:209`) and `move_grab.rs:98`.
- **Rationale**: `toggle_overview_to_workspace` (`mod.rs:4664`) activates on the *active*
  monitor, so focusing the source first makes it activate the right workspace.

## R5. Rendering a source on a viewer

- **Decision**: In `Niri::render_inner` for a viewer, for each projection call
  `self.render(ctx, &source, false, push)` into a local buffer. Wrap each element in
  `RescaleRenderElement` (factor `projection.zoom() * viewer_scale / source_scale`), then
  `RelocateRenderElement` (to the region origin), then `CropRenderElement` (to the region), and
  push them as a new `OutputRenderElements::Projected` variant. The variant is added to the
  `niri_render_elements!` list at `src/niri.rs:6586`.
- In **Overview** projections, push them where the viewer's own workspaces are pushed, so they
  sit under the top layer and over the backdrop.
- In **View** projections, push them instead of the viewer's monitor content, plus a
  `SolidColor` backdrop for the letterbox bars.
- **Recursion**: `render` of a source never adds projections, because only physical outputs
  own projections (R7).
- **Rationale**: This is the same wrapper stack the overview already uses
  (`monitor.rs:1704-1755`, `niri.rs:4159-4170`). Elements are rendered in the source's physical coordinates, so they are first relocated by
  `-source_rect.loc`, then rescaled and relocated to `region.loc`. `RenderCtx`
  (`src/render_helpers/mod.rs:54`)
  carries no scale, so the scale comes from each output's `current_scale()`.

## R6. Redraws

- **Decision**: When `Niri::redraw` runs for an output that is a source of any projection, it
  also calls `queue_redraw(viewer)` for each viewer.
- **Rationale**: `render_virtual_output` (`src/backend/tty.rs:2453`) never renders pixels and no
  existing path cascades redraws (`src/niri.rs:3700-3718`). The source still runs its own frame
  clock, so client frame callbacks don't change.

## R7. Telling virtual outputs apart

- **Decision**: Add `fn is_virtual_output(output: &Output) -> bool` in
  `src/backend/virtual_output.rs`. It reads `OutputName { make: Some("niri"),
  model: Some("virtual") }` from the output's user data. Both backends set it
  (`tty.rs:2511-2542`, `headless.rs:158`). Sources are virtual outputs that are on (in the
  layout). Viewers are outputs for which `is_virtual_output` is false.
- **Rationale**: The only existing check (`tty.rs:2011`, missing `TtyOutputState`) is TTY-only
  and would be wrong under the headless test backend.

## R8. The "Viewing: <name>" label

- **Decision**: A new `src/ui/view_output_label.rs` copies the Showing/Shown(deadline)/Hiding
  state machine from `ConfigErrorNotification` (`src/ui/config_error_notification.rs:38-124`)
  with a 2 s duration and one line of pango text. It renders only on the viewer.
- **Alternatives considered**: `HotkeyOverlay` (not timed) and `ExitConfirmDialog` (modal).

## R9. IPC and bind action

- **Decision**:
  - Add `Request::ViewOutput { name: Option<String> }` with `Response::ViewOutput(ViewOutputState)`,
    handled in `src/ipc/server.rs` the same way as `CreateVirtualOutput` (`server.rs:456-505`),
    so errors reach the CLI as typed messages.
  - Add `Action::ViewOutput { name: Option<String> }` to `niri-ipc` and `niri-config` binds,
    executed in `State::do_action` (`src/input/mod.rs:696`). There, errors go to the log, and to a
    one-line notice through the same label, because binds have no reply channel.
  - Add CLI `niri msg view-output [NAME]` in `src/ipc/client.rs`.
- **Rationale**: A `niri msg action` reply is always "Handled", so FR-019 needs a request.

## R10. Test harness

- **Decision**:
  - Pure unit tests for `Projection` and `overview_columns` (`src/projection.rs`).
  - Fixture tests in `src/tests/projection.rs` use `Fixture::add_output` for the viewer and
    `state.backend.headless().create_virtual_output(..)` for sources. They call
    `Niri::output_under`, `contents_under`, `workspace_under` and the layout's
    `interactive_move_begin/update/end` with the resolved `(output, pos)`, because the fixture
    cannot synthesize libinput events (`src/tests/*.rs` have no pointer-input examples).
  - The existing proptests in `src/layout/tests.rs` stay unchanged. Projection lives in `Niri`,
    not `Layout`.
- **Guard test**: grep-style test asserting `global_space.output_under` appears only in
  `Niri::output_under` and the motion clamp.
