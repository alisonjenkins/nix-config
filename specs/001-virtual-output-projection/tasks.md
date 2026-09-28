# Tasks: Virtual Output Projection

**Input**: Design documents from `/specs/001-virtual-output-projection/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/view-output.md, quickstart.md

**Tests**: Required. Constitution Principle II makes test-first mandatory. Every test task must be
written, run and seen **failing** before its implementation task.

**Organization**: Tasks are grouped by user story so that each story can be built and tested on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on unfinished tasks)
- **[Story]**: The user story the task belongs to (US1, US2, US3)

## Path Conventions

- Code paths are relative to the niri fork root: `/home/ali/git/niri` (branch `rebase-feat-virtual`).
- Paths prefixed `nix-config:` are relative to this repository.
- Every command runs inside the fork's dev shell: `nix develop -c <cmd>`.
- Commit after each task or tightly related group: one atomic, building commit (Principle I).
  Never add `.specify/` or `.claude/` to the fork (Principle VII).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Module scaffolding and a green baseline.

- [ ] T001 Record the baseline: run `cargo test --lib` and `cargo clippy --lib --tests` on `rebase-feat-virtual` and note the pass counts and any existing warnings in the first commit's body, so later regressions can be told apart from existing ones
- [ ] T002 Create empty module `src/projection.rs` with a `//!` doc line and register `pub mod projection;` in `src/lib.rs`; create empty `src/tests/projection.rs` and register it in `src/tests/mod.rs`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Pure maths, output classification, the state container and the input chokepoint. Every story depends on these.

**⚠️ CRITICAL**: No user story work can start until this phase is complete.

- [ ] T003 [P] Write failing unit tests in `src/projection.rs` (`#[cfg(test)] mod tests`) for `Projection`:
  - `to_source`/`to_viewer` round-trip;
  - a point outside `region` returns `None`;
  - `scale()` with 1728x1080 → 5120x1440 letterboxed and 1280x800 → a 1440x2560 portrait viewer;
  - viewer scale 1.25 against source scale 1;
  - the constructor rejects mismatched aspect ratios, empty rects, and `viewer == source`.
- [ ] T004 Implement `Projection`, `ProjectionKind { Overview, View }`, `ProjectionError` and `Projection::new(..) -> Result<Projection, ProjectionError>` with `to_source`, `to_viewer` and `scale` in `src/projection.rs`, per data-model.md. No `unwrap`.
- [ ] T005 [P] Write failing unit tests in `src/projection.rs` for:
  - `letterbox(source_size, viewer_size) -> Rectangle`: aspect ratio kept and content centred, for wide and tall cases;
  - `overview_columns(viewer_strip, viewer_size, source_sizes) -> Vec<Rectangle>` with 0, 1 and 3 sources: the row is centred, the gap is `0.05 × viewer height`, only sources shrink when the row exceeds 95% of the viewer width, each region is centred vertically, and at viewer-strip width = viewer width (zoom 1) the sources lie fully off-screen.
- [ ] T006 Implement `letterbox` and `overview_columns` in `src/projection.rs` to make T005 pass.
- [ ] T007 [P] Write a failing unit test for `is_virtual_output` in `src/backend/virtual_output.rs`: true for an `Output` whose `OutputName` has make `niri` and model `virtual`; false for another make or model, and when there is no `OutputName`.
- [ ] T008 Implement `pub fn is_virtual_output(output: &Output) -> bool` in `src/backend/virtual_output.rs`.
- [ ] T009 Add `ProjectionState { projections: Vec<Projection>, viewing: Option<Viewing> }` and `Viewing { viewer: String, source: String }` to `src/projection.rs`. Add a `projection_state: ProjectionState` field to `Niri` in `src/niri.rs`, initialised empty.
- [ ] T010 Write a failing fixture test in `src/tests/projection.rs`. Set up one physical output (`Fixture::add_output(1, (1920, 1080))`) and one virtual output (`state.backend.headless().create_virtual_output(niri, 1280, 800, 60, Some("steam".into()))`). With no projections, `niri.output_under(p)` for a point on the physical output returns that output and the same local position. This pins the pass-through behaviour.
- [ ] T011 Implement `Niri::rebuild_projections(&mut self)` in `src/niri.rs`. It recomputes `projection_state.projections` from the output list, `layout.is_overview_open()`, `layout.overview_zoom()`, each monitor's `workspaces_render_geo`, and `projection_state.viewing`. Sources are virtual outputs in the layout (`is_virtual_output`), viewers are the others. If `viewing` names a viewer or source that no longer exists or is disabled, it clears `viewing`.
- [ ] T012 Call `rebuild_projections` from every trigger:
  - overview toggle and overview progress/animation advance (where `advance_animations` runs for monitors);
  - `add_output`, `remove_output` and `output_resized` in `src/niri.rs`;
  - output scale or config reload (`reload_output_config`).
- [ ] T013 Make `Niri::output_under(pos)` in `src/niri.rs` projection-aware. After finding the global output and local position, if a projection with `viewer` equal to that output contains the position, return `(source Output, projection.to_source(local))`. A position inside a `View` projection's letterbox bars (inside the viewer but outside `region`) returns `None`. Route `output_under_cursor` through `output_under`. T010 must still pass.
- [ ] T014 Write a guard test in `src/tests/projection.rs` that reads `src/**/*.rs` with `include_str!`/`std::fs` and asserts that `global_space.output_under` appears only in `Niri::output_under` and the pointer-motion clamp in `src/input/mod.rs`. Name both allowed sites in the assertion message.

**Checkpoint**: The maths is tested, classification works, and every pointer-to-output lookup goes through one projection-aware function. User stories can start.

---

## Phase 3: User Story 1 - See and rescue windows from the overview (Priority: P1) 🎯 MVP

**Goal**: The overview on a physical monitor shows one real, interactive column per enabled virtual output. Windows drag between columns and workspaces in both directions, and drops into gaps create workspaces.

**Independent Test**: A window on `steam`. Open the overview on the viewer and check that the column and window are hit-testable at the column's position. Move the window to a viewer workspace through interactive move, and check that it lives there (quickstart rows 1-4).

### Tests for User Story 1 ⚠️ (write first, see them fail)

- [ ] T015 [P] [US1] Fixture test in `src/tests/projection.rs`: with a client window mapped on `steam` and the overview opened (`layout.toggle_overview()` then `niri_complete_animations()`), `niri.contents_under(p)` at the centre of `steam`'s column returns that window's surface. The surface-local position must match the window centre within 1 logical px.
- [ ] T016 [P] [US1] Fixture test: begin an interactive move of the `steam` window with the position from `niri.output_under` inside the column, update to a point over the viewer's first workspace, and end. Assert the window is now on the viewer's workspace. Add the reverse case, viewer → `steam` column, as a second test.
- [ ] T017 [P] [US1] Fixture test: an interactive move ending in the gap between two `steam` workspaces in its column creates a new workspace on `steam` containing the window. Assert through `layout.workspaces()` for `steam`.
- [ ] T018 [P] [US1] Fixture test: turning `steam` off while the overview is open (headless `remove_virtual_output`, or a disable path if headless supports it) removes its projection without closing the overview. Re-creating it adds a column again.

### Implementation for User Story 1

- [ ] T019 [US1] In `rebuild_projections` (`src/niri.rs`), when the overview is open or animating, build one `ProjectionKind::Overview` projection per (viewer, enabled source):
  - `source_rect` is the x-extent of the source monitor's `workspaces_render_geo` over the full source height;
  - `region` comes from `overview_columns` with the viewer's own strip taken from its `workspaces_render_geo`.
- [ ] T020 [US1] Add a `Projected` variant to the `OutputRenderElements` `niri_render_elements!` list in `src/niri.rs`, wrapping `CropRenderElement<RelocateRenderElement<RescaleRenderElement<RelocateRenderElement<OutputRenderElements<R>>>>>`. If the recursive type is rejected, render the source's elements into a boxed intermediate: wrap `MonitorRenderElement` and layer elements separately, and record the choice in the commit body.
- [ ] T021 [US1] In `Niri::render_inner` (`src/niri.rs`), for a viewer that has `Overview` projections, collect `self.render(ctx, &source, false, ..)` elements for each source. Wrap each element as follows, then push it where the viewer's own workspaces are pushed:
  - relocate by `-source_rect.loc`;
  - rescale by `projection.scale() * viewer_scale / source_scale`;
  - relocate to `region.loc`;
  - crop to `region`.

  Never add projections while rendering a virtual output (FR-018).
- [ ] T022 [US1] Draw the source's name above each column in `src/niri.rs`, using the same text-texture helper as the label in T033, or a simple pango texture. Cache the texture per name.
- [ ] T023 [US1] Redraw cascade in `src/niri.rs`: when `redraw` runs for an output that is the source of any projection, call `queue_redraw` on each of that projection's viewers.
- [ ] T024 [US1] Run T015–T018 and the full `cargo test --lib`. Fix until everything is green. The layout proptests must pass unchanged.

**Checkpoint**: The MVP. Stray windows on virtual outputs are visible in the overview and can be dragged off.

---

## Phase 4: User Story 2 - Work on a virtual output in place (Priority: P2)

**Goal**: `view-output` (IPC, CLI and bind) shows a virtual output letterboxed on the focused physical monitor, with input resolved into it, a 2 s label and automatic exit. Clicking a virtual workspace in the overview enters it.

**Independent Test**: `view-output steam`. A click at the viewer centre focuses the `steam` window, a click in a bar hits nothing, `view-output` with no name returns, and turning `steam` off ends view mode (quickstart rows 5-10).

### Tests for User Story 2 ⚠️

- [ ] T025 [P] [US2] Fixture test in `src/tests/projection.rs`: after `start_viewing("steam")`, `niri.contents_under(viewer centre)` returns the `steam` window, and a point in the letterbox bar returns no surface. `layout.active_output()` is `steam`.
- [ ] T026 [P] [US2] Fixture tests for the transitions in data-model.md:
  - stop returns `Stopped` and the viewer becomes active;
  - stop when not viewing returns `NotViewing`;
  - removing `steam` while viewing clears `viewing` and makes the viewer active;
  - removing the viewer clears `viewing` while `steam` still exists.
- [ ] T027 [P] [US2] Fixture tests for the errors: an unknown name → `NotFound`, the physical output's name → `NotVirtual`, a disabled virtual output → `Disabled`. `viewing` is unchanged after each.
- [ ] T028 [P] [US2] Unit test in `niri-config/src/binds.rs` tests: KDL `view-output "steam"` and `view-output` parse to `Action::ViewOutput { name: Some("steam") }` and `{ name: None }`.

### Implementation for User Story 2

- [ ] T029 [US2] Add `NotVirtual(String)`, `Disabled(String)` and `NoViewer` to `VirtualOutputError` in `src/backend/virtual_output.rs`, with messages that name the output, per contracts/view-output.md.
- [ ] T030 [US2] Implement `Niri::start_viewing(&mut self, name: &str) -> Result<ViewOutputState, VirtualOutputError>` and `Niri::stop_viewing(&mut self) -> ViewOutputState` in `src/niri.rs`. They validate the name, pick the viewer (the active monitor if physical, else the physical output under the pointer, else the first physical output), set `viewing`, call `rebuild_projections`, and focus the source monitor on start or the viewer on stop.
- [ ] T031 [US2] In `rebuild_projections`, when `viewing` is set and the overview is closed, build one `ProjectionKind::View` projection with `source_rect` = the full source and `region` = `letterbox(..)`. In `render_inner`, for a viewer in view mode, push the projected source elements plus a black `SolidColor` backdrop instead of the viewer's own monitor content.
- [ ] T032 [US2] Automatic exit (FR-015): in `rebuild_projections`, if `viewing` gets cleared because the source or viewer is gone, focus the remaining output and trigger the label from T033 with "Stopped viewing <name>: <reason>".
- [ ] T033 [P] [US2] Create `src/ui/view_output_label.rs`, copying the Hidden/Showing/Shown(deadline)/Hiding state machine from `src/ui/config_error_notification.rs` with a 2 s duration and one line of pango text. Register it in `src/ui/mod.rs`, advance and render it for the viewer in `src/niri.rs`, and show "Viewing: <name>" on start.
- [ ] T034 [US2] niri-ipc (`niri-ipc/src/lib.rs`):
  - add `Request::ViewOutput { name: Option<String> }`, `Response::ViewOutput(ViewOutputState)` and `ViewOutputState { Viewing{viewer,source}, Stopped{viewer,source}, NotViewing }`;
  - add `Action::ViewOutput { name: Option<String> }` with its clap attributes.
- [ ] T035 [US2] Server handler in `src/ipc/server.rs`: mirror the `CreateVirtualOutput` idle/channel pattern. Call `start_viewing` or `stop_viewing` and map errors to `Err(err.to_string())`.
- [ ] T036 [US2] CLI in `src/ipc/client.rs`: add `niri msg view-output [NAME]`, print the one-line messages from contracts/view-output.md, and print JSON with `--json`.
- [ ] T037 [US2] Bind action: add `Action::ViewOutput` parsing in `niri-config/src/binds.rs` and handle it in `State::do_action` in `src/input/mod.rs`. On error, `warn!` and show the message through the label.
- [ ] T038 [US2] Overview click into view mode. At `src/input/mod.rs:3047-3057`, `src/input/touch_overview_grab.rs:~209` and `src/input/move_grab.rs:~98`: if the resolved workspace's output is virtual, focus that output, call `toggle_overview_to_workspace(idx)`, then `start_viewing(output name)` for the viewer the click came from.
- [ ] T039 [US2] Opening the overview during view mode (FR-014): `rebuild_projections` builds Overview projections while the overview is open and keeps `viewing`; closing the overview rebuilds the View projection. Add a fixture test for this in `src/tests/projection.rs`.
- [ ] T040 [US2] Run T025–T028, T039 and the full suite. Fix until everything is green.

**Checkpoint**: US1 and US2 both work independently.

---

## Phase 5: User Story 3 - Streams stay undisturbed (Priority: P3)

**Goal**: The source's own rendering and frame pacing are unchanged by being projected.

**Independent Test**: The source's frame clock and its screencast render stay identical with and without projections (quickstart manual step 9 covers the live stream).

### Tests for User Story 3 ⚠️

- [ ] T041 [P] [US3] Fixture test in `src/tests/projection.rs`: collect `niri.render(ctx, &steam, ..)` elements with no projections, then again with an Overview projection and with a View projection. The element count and geometry are identical, so no projection or viewer content leaks into the source (FR-016, FR-018).
- [ ] T042 [P] [US3] Fixture test: pointer rendering. With `include_pointer = true`, rendering `steam` while viewing it produces no pointer element, because the cursor stays on the viewer (FR-017).

### Implementation for User Story 3

- [ ] T043 [US3] Fix any leak that T041 or T042 expose, so the source path in `render_inner` never consults `projection_state`. Otherwise record in the commit body that no change was needed.

**Checkpoint**: All three stories are done and independently tested.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T044 [P] Document `view-output`, the overview columns and the limitations (pointer contention, softer scaling) in `docs/Virtual-Outputs.md` in the fork.
- [ ] T045 Run the quality gates: `cargo fmt --check`, `cargo clippy --lib --tests -- -D warnings` (no new warnings compared with T001), and the full `cargo test --lib`.
- [ ] T046 In nix-config, regenerate `nix-config:patches/niri-virtual-outputs.patch` with `git -c diff.external= diff --no-ext-diff e9b215fe HEAD` in the fork. Then build `.#nixosConfigurations.ali-desktop.config.programs.niri.package`.
- [ ] T047 [P] Write the ADR `nix-config:docs/adr/0019-virtual-output-projection.md` covering the projection design, the single input chokepoint, and the rejected alternatives (native multi-output rendering, mirror client, Esc to exit). Add it to `nix-config:docs/adr/README.md` and link it from `nix-config:docs/steam-remote-play-streaming.md`.
- [ ] T048 Add default binds, for example `Mod+V` → `view-output "steam"` and `Mod+Shift+V` → `view-output`, to the generated niri config in `nix-config:home/programs/linux-only/niri/module.nix`, next to the virtual-output blocks.
- [ ] T049 After the user switches and logs in again, run the quickstart manual steps 1–10 on ali-desktop and record the outcome, including SC-005's 10 toggles during a stream, in the PR description.

---

## Dependencies & Execution Order

### Phase Dependencies

- Setup (T001–T002) → Foundational (T003–T014) → the user stories → Polish.
- US1 (T015–T024) needs Foundational only.
- US2 (T025–T040) needs Foundational. It reuses T020/T021 rendering from US1, so do US1 first, or pull T020–T021 forward if US2 is built alone.
- US3 (T041–T043) needs US1 and US2 so that both projection kinds exist to test against.
- Polish needs every story it documents or ships.

### Within Each Story

- The tests come first and must fail before implementation.
- Order: state and rebuild → rendering → input and UI → IPC and binds.
- Commit per task or tight group; each commit builds and passes the tests (Principle I).

### Parallel Opportunities

- T003, T005 and T007 are independent pure tests (different functions and files).
- T015–T018 are test-only additions to the same file, so they can be written together, but land in one commit.
- T025–T028 are test writing; T033 (label widget) is independent of T029–T032.
- T041 and T042 go together. T044 and T047 are docs, in parallel.

## Parallel Example: User Story 1

```text
Write together: T015, T016, T017, T018   (src/tests/projection.rs — one commit)
Then sequential: T019 → T020 → T021 → T022 → T023 → T024
```

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1 and Phase 2: the chokepoint is in, and nothing changes visibly.
2. Phase 3 (US1): the overview columns plus drag and drop.
3. **Stop and validate**: regenerate the patch, build, switch, and run quickstart manual steps 1–5.
4. This alone fixes the "invisible window" problem.

### Incremental Delivery

1. Foundational, then US1: ship (MVP).
2. US2 (view mode, IPC, binds): ship.
3. US3 guards, then polish: ship.

Each increment is a set of commits on `rebase-feat-virtual`, plus one nix-config PR carrying the regenerated patch, the ADR and the binds.

## Notes

- If a fixture test cannot reach something without libinput events, drive the same `Niri`/`Layout` method the input handler calls. Never widen production APIs only for tests.
- The drag-delta caveat in R3 (`interactive_move_update` divides by the viewer's zoom inside a shrunk column) is accepted. Only fix it if T016 or T017 show a wrong drop target.
