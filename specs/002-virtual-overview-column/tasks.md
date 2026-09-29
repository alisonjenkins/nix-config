# Tasks: Virtual Output Overview Column

**Input**: Design documents from `/specs/002-virtual-overview-column/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/events.md, quickstart.md

**Tests**: Required. Constitution Principle II makes test-first mandatory. Every test task must be
written, run and seen **failing** before its implementation task. Tests drive real input through
`src/tests/input.rs`; any test needing a renderer is named `egl_*`.

**Organization**: Tasks are grouped by user story. US1 and US2 are both P1 and share one
replacement commit (the band cannot exist without its column, and 001's columns cannot stay
alongside it), so US1 lands first as the band plus a static column, and US2 adds its interaction.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on unfinished tasks)
- **[Story]**: The user story the task belongs to (US1–US4)

## Path Conventions

- Code paths are relative to the niri fork root: `/home/ali/git/niri` (branch `rebase-feat-virtual`).
- Paths prefixed `nix-config:` are relative to this repository.
- Every command runs inside the fork's dev shell: `nix develop -c <cmd>`.
- Commit after each task or tightly related group: one atomic commit that builds and passes tests
  (Principle I). No `unwrap`/`expect` outside tests (Principle IV). Never add `.specify/` or
  `.claude/` to the fork. No AI attribution in commit messages.
- Line numbers refer to commit `be7da3af` (research.md).

---

## Phase 1: Setup

- [ ] T001 Record the baseline on `rebase-feat-virtual`: `cargo test --workspace`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo fmt --check`; note pass counts and the known `niri-ipc/src/lib.rs:367` fmt issue for later comparison. Changes no files.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Inert layout hooks, pure geometry, state types and event-state parts. Every story depends on these; each is a no-op until used.

- [ ] T002 [P] Tests for the overview right inset in `src/layout/monitor.rs` (unit tests module) and `src/layout/tests.rs`: with inset 0 geometry equals today's; with inset `w`, `workspaces_render_geo` centres the strip in `view_size.w − w·progress`, `workspace_under` never returns a workspace for x ≥ `view_size.w − w·progress`, the cull rectangle shrinks, and `dnd_scroll_gesture_scroll` uses the same centre; non-finite or negative inset is treated as 0. Add an `Op::SetOverviewRightInset` to the proptest ops.
- [ ] T003 Implement `Monitor::set_overview_right_inset(f64)` (field `overview_right_inset`, sanitised, debug log on invalid) and apply it in `workspaces_render_geo` (`monitor.rs:1475`), `workspaces_with_render_geo_cull`/`_idx`/`_mut` (`:1503-1538`), `workspace_under` (`:1540`) and `dnd_scroll_gesture_scroll` (`:1968`); forward via `Layout::set_overview_right_inset(output, f64)` in `src/layout/mod.rs`. Makes T002 pass.
- [ ] T004 [P] Tests for the offscreen-reachable flag in `src/layout/monitor.rs` tests: with the flag set and the overview open, `workspaces_with_render_geo` yields every workspace (no culling), `workspace_under`/`insert_position` resolve positions of workspaces outside the output, including `InsertWorkspace::NewAt` past the last; flag unset = today's behaviour.
- [ ] T005 Implement `Monitor::set_overview_offscreen_reachable(bool)` and `Layout::set_overview_offscreen_reachable(output, bool)`; culling in the `_cull` family uses unbounded bounds when set. Makes T004 pass.
- [ ] T006 [P] Tests for `Monitor::render_workspace_overview(ws_idx, …)` in `src/tests/projection.rs` (`egl_render_workspace_overview_*`): yields elements only for that workspace, at the same positions `render_workspaces` gives it, including when it is offscreen, and nothing for an invalid index.
- [ ] T007 Implement `Monitor::render_workspace_overview` in `src/layout/monitor.rs`, sharing the per-workspace body of `render_workspaces` (`:1685-1811`) through an extracted helper rather than duplicating it (Principle V). Makes T006 pass.
- [ ] T008 [P] Pure-geometry tests in `src/projection.rs` tests: `band_rect(viewer_size, progress)` (15%, scales with progress, zero at progress 0); `column_layout(band, sources, scroll)` gives groups in input order, a label row then equal-width tiles with height by aspect, niri gap ratio, larger inter-group gap; 1, 3 and 12 sources give identical tile sizes; scroll clamps to `[0, content_h − band_h]`, NaN → 0, short content is centred; zero/non-finite source sizes are skipped; `scroll_to_show(tile)` returns an offset that puts a tile in view.
- [ ] T009 Implement `BAND_FRACTION`, `band_rect`, `column_layout`, `ColumnLayout`/`GroupLayout`/`TileLayout` and `scroll_to_show` in `src/projection.rs`; add `ProjectionKind::Tile { workspace: WorkspaceId }`. Makes T008 pass. `overview_columns` stays until T014.
- [ ] T010 [P] Event-state tests in `niri-ipc/src/state.rs`: `ViewOutputEventState` and `OutputsState` `replicate()` return one event with current state (initial `NotViewing` / empty map); `apply()` updates state and consumes only its own event; serde round-trip of both new `Event` variants in `niri-ipc/src/lib.rs` tests matches the JSON in `nix-config:specs/002-virtual-overview-column/contracts/events.md`.
- [ ] T011 Add `Event::ViewOutputChanged { state: ViewOutputState }` and `Event::OutputsChanged { outputs: HashMap<String, Output> }` with the doc comments from the contract to `niri-ipc/src/lib.rs`; add both state parts to `EventStreamState` in `niri-ipc/src/state.rs`. Add print arms in `src/ipc/client.rs` (formats per contract). Makes T010 pass.

**Checkpoint**: All hooks inert; `cargo test --workspace` green; no behaviour change.

---

## Phase 3: User Story 1 – The physical monitor's overview is never in the way (P1) 🎯 MVP

**Goal**: The band replaces 001's columns; DP-2's overview lives in the remaining width; the band is opaque, on top, and never passes input to DP-2.

**Independent Test**: quickstart manual steps 3–4; the clash tests below.

- [ ] T012 [P] [US1] Rewrite the column tests in `src/tests/projection.rs` for the band: with `steam` on, opening the overview sets DP-2's inset to the band width and `steam`'s offscreen-reachable flag; with no virtual output on, inset 0 and geometry identical to upstream; band width follows overview progress while opening and closing; a DP-2 window scrolled towards the band is hit (real click) outside the band and a real click inside the band never reaches DP-2 (the clash regression); a click on band background or a label changes nothing and keeps the overview open; locked session: no band, no tiles, clicks reach the lock surface only. Delete the tests that only assert `overview_columns` shrink maths (list in research.md R10).
- [ ] T013 [P] [US1] `egl_` render tests in `src/tests/projection.rs`: band fill, labels and tiles are ahead of DP-2's workspace elements in the element list; a DP-2 window overflowing into the band is not visible there; tile elements are cropped to the tile; tiles outside the band's visible part produce no elements.
- [ ] T014 [US1] Replace columns with the band in `src/niri.rs` and `src/projection.rs` (one commit): `rebuild_projections` builds `ProjectionState.bands` and one `Tile` projection per visible tile from `column_layout` (source rect = the source monitor's `workspaces_render_geo` rect for that workspace), sets each physical monitor's inset and each source's offscreen-reachable flag (cleared when the overview closes, the session locks or no virtual output is on); `resolve_output_under` returns `OutputUnder { band: true }` for band positions that hit no tile and carries over the top-layer special case (`niri.rs:3798-3813`); render the band ahead of the viewer's workspaces using `render_workspace_overview` + `ProjectedElement` + `CropRenderElement`; remove `overview_columns` and its constants, `workspace_strip`, the per-output `overview_projections`, `render_overview_projections`, `overview_column_backings` and `src/ui/overview_column_label.rs`. Debug log on column structure change (viewer, groups, tiles, scroll range), never per frame. Makes T012–T013 pass.
- [ ] T015 [US1] Add `src/ui/overview_band.rs` (registered in `src/ui/mod.rs`): name labels (text texture as the old column label), the opaque band fill, and per-source active-tile highlight using `options.focus_ring` active colour and width. Used by T014's render path. If T014 needs labels to compile, fold T015 into T014's commit.
- [ ] T016 [US1] Rerun the full suite; fix any existing projection, view-mode, lock, hot-corner and cursor-teleport test that referenced columns so it asserts the same behaviour against tiles (FR-021/022).

**Checkpoint**: US1 complete; the MVP can ship.

---

## Phase 4: User Story 2 – Any number of virtual outputs in one column (P1)

**Goal**: Column interaction: clicks into view mode, scrolling, scroll on open, highlight, live add/remove.

**Independent Test**: quickstart manual steps 5, 7, 8.

- [ ] T017 [P] [US2] Tests in `src/tests/projection.rs`: with three virtual outputs, groups follow config order and all tiles are equal width; a real click on a window in a tile closes the overview, starts view mode on its output (`ViewOrigin::Overview`), activates that workspace and focuses that window, and Escape returns; a click on empty tile space does the same without focusing a window; turning an output on/off during the overview adds/removes its group and clamps scroll; opening the overview scrolls the column to the first output's active workspace; 12 outputs: the last tile is reachable by scrolling.
- [ ] T018 [US2] Make T017 pass in `src/niri.rs` (scroll reset on overview open via `scroll_to_show`; per-viewer scroll kept across rebuilds while open; clamp after rebuild). Clicks should already work through `resolve_output_under` → existing overview click paths (`niri.rs:2965-3087`); fix only what the tests show.
- [ ] T019 [P] [US2] Tests in `src/tests/projection.rs`: wheel (real axis events) over the band scrolls only the column and not DP-2's or the source's workspaces; wheel over DP-2 behaves as upstream; a vertical touchpad swipe over the band scrolls the column and does not start the overview workspace gesture; NaN/huge deltas stay clamped.
- [ ] T020 [US2] Route wheel and swipe over a band to the column in `src/input/mod.rs` (before `should_handle_in_overview` at `:3149` and before the `overview_gesture_*` calls at `:3962`, `:4079`, `:4123`), deciding by the pointer's physical output. Makes T019 pass.

**Checkpoint**: US1 + US2 complete.

---

## Phase 5: User Story 3 – Move windows between any workspaces (P2)

**Goal**: Drag and drop through tiles, new workspace on the empty last tile, edge scroll.

**Independent Test**: quickstart manual step 6.

- [ ] T021 [P] [US3] Tests in `src/tests/projection.rs` (real pointer drags through the move grab): DP-2 → tile, tile → DP-2, tile → tile on the same and on a different virtual output; drop on an empty last tile creates a workspace on that output; insert hint appears on the hovered tile; reorder within a tile; source turned off mid-drag leaves the drag running with no target and the window intact; info log line per drop onto a tile (window, output, workspace).
- [ ] T022 [US3] Make T021 pass; expected to need only the info log and any fixes the tests expose, since targets come from `insert_position` via the projection (research.md R3). Do not add a separate drop-target path.
- [ ] T023 [P] [US3] Tests: holding a drag within the edge zone at the band's bottom (top) scrolls the column down (up) per frame until its end; moving out stops it; DP-2's own DnD edge scroll is unchanged.
- [ ] T024 [US3] Implement column edge-scroll during drags in `src/input/move_grab.rs` (motion at `:232`) and the frame callback that advances it in `src/niri.rs`. Makes T023 pass.

**Checkpoint**: US1–US3 complete.

---

## Phase 6: User Story 4 – Other programs can follow view mode and outputs (P3)

**Goal**: `ViewOutputChanged` and `OutputsChanged` on the event stream.

**Independent Test**: quickstart manual steps 2 and 7.

- [ ] T025 [P] [US4] Add a test-only event recorder at the `send_event` boundary (or an `IpcServer`-free hook the fixture can read) in `src/ipc/server.rs` / `src/tests/fixture.rs`, then tests in `src/tests/projection.rs`: exactly one `ViewOutputChanged` per cause (IPC `view-output`, bind action, overview tile click, `view-output` with no name, Escape, viewer becoming active, source turned off, viewer removed), none for `view-output` with no name while not viewing; one `OutputsChanged` on virtual output create, remove, on and off, and none on a mode change alone; a new subscriber's replicate includes both with current state.
- [ ] T026 [US4] Implement `State::ipc_refresh_view_output` in `src/ipc/server.rs` (compare `projection_state.viewing` with stream state, apply, send) and call it from `State::refresh` after `stop_viewing_if_viewer_active` in `src/niri.rs`. Makes the view-mode half of T025 pass.
- [ ] T027 [US4] Implement the outputs event: in `State::refresh_ipc_outputs` (`src/niri.rs:2169`) build the name-keyed map, compare names and on/off state with `event_stream_state.outputs`, and send `OutputsChanged` only on a difference. Makes the rest of T025 pass.

**Checkpoint**: All stories complete.

---

## Phase 7: Polish & Cross-Cutting

- [ ] T028 [P] Update the fork's `docs/Virtual-Outputs.md`: the overview band and column (replacing the per-output column text), scrolling and drag behaviour, and both events with examples.
- [ ] T029 Full verification: `cargo test --workspace`, clippy `-D warnings`, `fmt --check` on touched files, attribution grep = 0 over the new commits, grep that no `unwrap()`/`expect(` was added outside tests. Compare with T001.
- [ ] T030 Integration: extend the scratch harness (`scratchpad/integration/run.sh`) with event-stream checks (create/remove a virtual output and view/unview while running `niri msg --json event-stream`, assert one event each). Run it against the built binary.
- [ ] T031 Push the fork (fast-forward), then in nix-config `nix flake update niri-virtual` and build `.#nixosConfigurations.ali-desktop.config.programs.niri.package` and the toplevel.
- [ ] T032 [P] nix-config docs: amend `nix-config:docs/adr/0019-virtual-output-projection.md` (band replaces per-output columns; tiles map into the source's overview coordinates; why the outputs event carries the full map) or add a new ADR and index it; mark 001's superseded FRs in `nix-config:specs/001-virtual-output-projection/spec.md`; one line in `nix-config:docs/steam-remote-play-streaming.md`.
- [ ] T033 Live check after the user switches and re-logs in: quickstart manual steps 1–10, including a Remote Play stream from ali-mba (SC-006).

---

## Dependencies & Execution Order

- **Setup (T001)** → **Foundational (T002–T011)** → **US1 (T012–T016)** → **US2 (T017–T020)** → **US3 (T021–T024)**. **US4 (T025–T027)** depends only on Foundational (T010–T011) and can run in parallel with US1–US3.
- Within Foundational, the pairs T002→T003, T004→T005, T006→T007, T008→T009, T010→T011 are independent of each other; T006/T007 need T005 (offscreen elements).
- T014 depends on T003, T005, T007, T009. T015 can be written in parallel with T014 (separate file) but lands with or before it.
- Polish follows all stories; T033 needs the user.

## Parallel Opportunities

- Foundational: T002, T004, T008, T010 (tests, different files) in parallel; then T003, T009, T011 in parallel (different files); T005 after T003 (same file); T007 after T005.
- US4 (events) runs in its own worktree alongside US1–US3.
- Within US1: T012 and T013 in parallel; T015 in parallel with T014's drafting.

## Implementation Strategy

1. Foundational hooks and pure geometry first; all inert, suite green.
2. MVP = US1: one commit swaps 001's columns for the band. Stop, run the suite, deploy for a look if wanted.
3. US2 (clicks, scrolling), then US3 (drag polish, edge scroll).
4. US4 in parallel, merged when its tests pass.
5. Polish, push, flake update, build; live check with the user.
