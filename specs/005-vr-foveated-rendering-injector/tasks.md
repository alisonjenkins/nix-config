---

description: "Task list for foveated rendering for VR games that lack it"
---

# Tasks: Foveated rendering for VR games that lack it

**Input**: Design documents from `/specs/005-vr-foveated-rendering-injector/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/interfaces.md, quickstart.md

**Tests**: Included. The constitution requires a failing test first wherever the behaviour is testable (Principle II). GPU behaviour cannot run in the Nix sandbox, so those tasks verify with the probe or a per-game run and record the output.

**Organization**: Grouped by user story. Each story phase ends at a state that can be tried on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: US1 to US6, matching the spec
- Paths starting `fork:` are in the DXVK fork repository; all others are in this repository
- **(owner)**: needs the owner's go-ahead or action at that moment (launching a game, creating a repository, root access)
- One commit per task unless a task says otherwise; the commit is atomic and leaves the tree building
- Every phase that changes the fork ends with an "update the fork input" task (constitution VII): fork commits land first, then this repository updates the `dxvk-foveation` input and rebuilds `.#proton-foveated`

## Phase 1: Setup and spikes (answer the unverified facts first)

**Purpose**: settle the five facts the design depends on. No product code ships from this phase.

- [ ] T001 [P] Extend the probe with a layered, non-multiview case (two-layer target, no view mask, one-layer rate image) in `specs/005-vr-foveated-rendering-injector/research/vrs-probe/vrs_probe.c` (and `vrs.frag` or `vrs.vert` if the case needs it), and record the new line in `research/vrs-probe/results.txt` (spike S1)
- [ ] T002 (owner) Start Fallout 4 VR once from Steam to create its prefix, then record its graphics API, and the large colour targets (size, layers, format, samples) from DXVK's log, in `specs/005-vr-foveated-rendering-injector/research.md` (spike S2)
- [ ] T003 [P] Confirm in DXVK's source and with a one-line config test whether a per-executable config can carry `dxvk.foveation.*` keys; if not, adopt the per-game config file fallback in `research.md` D6 and note the consequence for T056; record the finding in `research.md` D6 (spike S2)
- [ ] T004 (owner) Try SteamVR's null driver with Fallout 4 VR for 60 s using the existing SteamVR settings module in `home/modules/vr/steamvr-settings.nix`; if no frames, try the Quest over Steam Link with a fixed pose; record the route chosen and why in `research.md` D8 (spike S4)
- [ ] T005 [P] Find which DXVK version the user's Proton runner ships and choose the fork's base tag; record in `research.md` D5 (spike S5)
- [ ] T006 Prototype the compat tool layering on a throwaway derivation (the user's Proton with only its DXVK directory replaced by an unmodified build) and show a game using it and the runner updater leaving it alone; record in `research.md` D5 (spike S3; depends on T005)

**Checkpoint**: if T001 fails, mark layered passes as per-draw-rate only in `plan.md`; if T004 finds neither headless route works, the measurement phase uses a worn headset and says so.

---

## Phase 2: Foundational (blocks every user story)

**Purpose**: the fork, the package wiring and the test scaffolding.

- [ ] T007 (owner) Create the DXVK fork repository at the base tag from T005 and add it as an input in `flake.nix` (follows `nixpkgs`)
- [ ] T008 Build the unmodified fork through Nix as a package and show its version line matches the base, in `pkgs/proton-foveated/default.nix`
- [ ] T009 Build the compat tool (the user's Proton plus the fork's DXVK) in `pkgs/proton-foveated/default.nix` and install it through the steam module, without touching the runner updater's directory
- [ ] T010 [P] Register both packages in `pkgs/default.nix` and expose them in `flake-modules/packages.nix` so PR checks build them
- [ ] T011 [P] Create the empty bench package in `pkgs/vr-foveation-bench/default.nix` (Python, standard library, flake8-clean), exposed in `flake-modules/packages.nix`
- [ ] T012 [P] Add the bench package's source files to the flake8 hook's `files` pattern in `.pre-commit-config.yaml`
- [ ] T013 [P] Create the C++ test directory and Meson test target in `fork:tests/foveation/meson.build`, running with the fork's normal build
- [ ] T014 [P] Add the rate limits and the verified GPU and driver list as one source of truth in `fork:src/dxvk/dxvk_foveation.h` (rate limits read from the device; verified list holds GPU name and driver; no copies elsewhere)
- [ ] T015 [P] Expose the Python and home-module tests as flake checks in `flake-modules/vr-foveation-tests.nix`, and run `meson test` in the fork package's check phase in `pkgs/proton-foveated/default.nix`, so `just check` runs them with no headset or game (SC-007)

**Checkpoint**: `nix build .#proton-foveated` and `just check` build and pass with no behaviour change; a game launched with the tool behaves like stock.

---

## Phase 3: User Story 1 - Know whether a game can benefit (Priority: P1)

**Goal**: a report with GPU frame time, power, eye-pass share and a go/no-go verdict.

**Independent Test**: run the measurement on Fallout 4 VR with foveation off and read the report (quickstart, Phase 1).

### Tests for User Story 1

- [ ] T016 [P] [US1] Failing tests for the statistics rule (per-run median and p99, noise as spread of medians, gain beyond twice the larger noise with the same sign in every pair, fewer than 3 runs returns exit status 2) in `pkgs/vr-foveation-bench/tests/test_stats.py`
- [ ] T017 [P] [US1] Failing tests for the report schema (including `headsetOrDisplay`, `build` and `eyePassShare`) and the verdict states (`go`, `no-go`, `inconclusive`) in `pkgs/vr-foveation-bench/tests/test_report.py`
- [ ] T018 [P] [US1] Failing test for selecting the discrete GPU by PCI device and never by hwmon index, using a fake sysfs tree, in `pkgs/vr-foveation-bench/tests/test_sampler.py`

### Implementation for User Story 1

- [ ] T019 [US1] Implement the statistics module in `pkgs/vr-foveation-bench/vr_foveation_bench/stats.py` until T016 passes
- [ ] T020 [US1] Implement the report and verdict logic in `pkgs/vr-foveation-bench/vr_foveation_bench/report.py` until T017 passes
- [ ] T021 [US1] Implement the sampler (power from the power-average sensor at about 20 Hz and integrated to energy, core clock, busy percent, start and end temperature) in `pkgs/vr-foveation-bench/vr_foveation_bench/sampler.py` until T018 passes
- [ ] T022 [US1] Add the command line (`sample`, `report`) with exit codes and ISO 8601 UTC times in `pkgs/vr-foveation-bench/vr_foveation_bench/cli.py`
- [ ] T023 [US1] Failing C++ test for the measurement log writer (header, one row per frame, `gpu_ms` and `eye_pass_ms` columns) in `fork:tests/foveation/test_measure_log.cpp`
- [ ] T024 [US1] Implement timestamp queries around frames and matched passes behind `DXVK_FOVEATION_MEASURE` in `fork:src/dxvk/dxvk_foveation_measure.{h,cpp}` until T023 passes; off path creates no queries
- [ ] T025 [US1] Update the `dxvk-foveation` input in `flake.nix` to the fork commit from T024 and rebuild `.#proton-foveated`
- [ ] T026 [US1] (owner) Run the baseline on Fallout 4 VR with stock Proton (warm-up 60 s, 5 interleaved runs of 60 s or 3,000 frames), record the environment including the undervolt and the headset or display settings, and save the report under `docs/vr-foveation/baselines/fallout4vr-stock.json` (pinning clocks is optional and only offered, never run)
- [ ] T027 [US1] (owner) Run the same baseline with the patched tool and `DXVK_FOVEATION` unset, save it under `docs/vr-foveation/baselines/fallout4vr-patched-off.json`, and record whether it matches stock within noise (SC-005)

**Checkpoint**: both baseline reports exist with their noise levels, and the patched tool with the option off matches stock within noise.

---

## Phase 4: User Story 2 - Fixed centre foveation in a D3D11 game (Priority: P1)

**Goal**: one launch option turns on full quality in the centre and reduced shading at the edges.

**Independent Test**: Fallout 4 VR with and without `DXVK_FOVEATION=1` over the same scene (quickstart, Phase 2).

### Tests for User Story 2

- [ ] T028 [P] [US2] Failing tests for rate-map generation (tile size from the device, centre, inner radius, bands, rate codes capped at the device maximum, one layer) in `fork:tests/foveation/test_ratemap.cpp`
- [ ] T029 [P] [US2] Failing tests for pass recognition against a profile (size, layers, format, samples; non-matching passes ignored; 8x samples never match; two passes of similar size resolved by the profile) in `fork:tests/foveation/test_recognise.cpp`
- [ ] T030 [P] [US2] Failing tests for profile parsing from `dxvk.foveation.*` keys (valid profile, unknown key, out-of-range value, invalid band order) in `fork:tests/foveation/test_profile.cpp`
- [ ] T031 [P] [US2] Failing test that the generated rate codes match the values recorded in `specs/005-vr-foveated-rendering-injector/research/vrs-probe/results.txt` (1x1, 2x1, 1x2, 2x2 codes and the 8x8 tile size) in `fork:tests/foveation/test_ratemap_probe.cpp` (FR-015)
- [ ] T032 [P] [US2] Failing test that the rate map is regenerated when the target size changes while running (render-scale or resolution change) in `fork:tests/foveation/test_resize.cpp`

### Implementation for User Story 2

- [ ] T033 [US2] Implement profile parsing in `fork:src/dxvk/dxvk_foveation.{h,cpp}` until T030 passes
- [ ] T034 [US2] Implement rate-map generation in `fork:src/dxvk/dxvk_foveation.{h,cpp}` until T028 and T031 pass
- [ ] T035 [US2] Implement pass recognition in `fork:src/dxvk/dxvk_foveation.{h,cpp}` until T029 passes
- [ ] T036 [US2] Request the shading-rate extension and feature at device creation only when `DXVK_FOVEATION` is on, in `fork:src/dxvk/dxvk_adapter.cpp` and `fork:src/dxvk/dxvk_device_info.h`
- [ ] T037 [US2] Add the shading-rate dynamic state and OR the rendering-attachment creation flag into pipeline flags only when foveation is on, in `fork:src/dxvk/dxvk_graphics.cpp`; confirm the off path builds identical pipelines
- [ ] T038 [US2] Create and upload the rate image (8x8 tiles from the device, `R8_UINT`, one layer) and chain it into the render pass begin for matched passes, with base rate 1x1 and combiners `{KEEP, REPLACE}`, in `fork:src/dxvk/dxvk_context.cpp`
- [ ] T039 [US2] Regenerate the rate map when the matched target's size changes, in `fork:src/dxvk/dxvk_context.cpp`, until T032 passes
- [ ] T040 [US2] Make `DXVK_FOVEATION` the only opt-in; with it unset, no foveation code path runs, in `fork:src/dxvk/dxvk_foveation.cpp`
- [ ] T041 [US2] Update the `dxvk-foveation` input to the fork commit from T040 and rebuild `.#proton-foveated`
- [ ] T042 [US2] (owner) Run the on/off comparison on Fallout 4 VR (5 interleaved runs per condition), save the report under `docs/vr-foveation/results/fallout4vr-on-off.json`, and take screenshots with foveation off and on at the same fixed positions in the same scene (centre, mid-periphery, edge) saved next to it; record the owner's accept or reject decision on the periphery (SC-002)

**Checkpoint**: a measured on/off difference with its noise, and screenshots with the owner's decision, exist for one game.

---

## Phase 5: User Story 3 - A failure never breaks the game (Priority: P1)

**Goal**: every failure leaves the game running at normal quality and logs a stable reason.

**Independent Test**: force each failure from the quickstart and see the matching `reason`.

### Tests for User Story 3

- [ ] T043 [P] [US3] Failing tests for each fallback reason (`no_profile`, `invalid_profile`, `no_pass_matched`, `unverified_gpu`, `extension_missing`, `samples_unsupported`, `game_sets_own_rates`) asserting the game-facing result is "no foveation" and the log line has the expected keys, in `fork:tests/foveation/test_fallbacks.cpp`
- [ ] T044 [P] [US3] Failing test for the `DXVK_FOVEATION_OVERRIDE_GPU` escape hatch and the verified-GPU check, in `fork:tests/foveation/test_gpu_gate.cpp`

### Implementation for User Story 3

- [ ] T045 [US3] Implement the log lines (`key=value`, ISO 8601 UTC, `dxvk-foveation` prefix, stable reasons) in `fork:src/dxvk/dxvk_foveation.cpp` until T043 passes
- [ ] T046 [US3] Implement the verified-GPU gate and the override in `fork:src/dxvk/dxvk_foveation.cpp` until T044 passes
- [ ] T047 [US3] Detect a game that sets its own shading rates and leave them in place (log `game_sets_own_rates`) in `fork:src/dxvk/dxvk_context.cpp`
- [ ] T048 [US3] Update the `dxvk-foveation` input to the fork commit from T047 and rebuild `.#proton-foveated`
- [ ] T049 [US3] (owner) Force each failure on Fallout 4 VR (no profile, no match, 8x samples, extension missing; the unverified-GPU case is covered by T044 on this machine) and record that the game starts and plays normally each time, with the log lines, under `docs/vr-foveation/results/fallout4vr-failures.md`
- [ ] T050 [US3] State in `docs/vr-foveation.md` that games with anti-cheat are unsupported and that the owner decides at their own risk; the feature cannot detect anti-cheat, so this is documentation only

**Checkpoint**: all forced failures leave the game running normally (SC-004).

---

## Phase 6: User Story 4 - Profiles and a verdict per game (Priority: P2)

**Goal**: profiles the owner can edit without recompiling, a discovery mode, and a verdicts record.

**Independent Test**: change a profile's inner radius in a scratch config, launch once with `DXVK_CONFIG_FILE` pointing at it and see the region change; read the verdicts file.

### Tests for User Story 4

- [ ] T051 [P] [US4] Failing test for the home module's generated DXVK config (one section per game, keys match the contract, `DXVK_CONFIG_FILE` default set) in `home/modules/vr-foveation/tests/default.nix` as a Nix check wired by T015
- [ ] T052 [P] [US4] Failing test for the verdicts file round-trip (a report produces a row; invalid verdicts rejected) in `pkgs/vr-foveation-bench/tests/test_verdicts.py`
- [ ] T053 [P] [US4] Failing test for discovery mode (candidate targets logged once per second with a hit count; nothing applied) in `fork:tests/foveation/test_discover.cpp`

### Implementation for User Story 4

- [ ] T054 [US4] Implement discovery mode behind `DXVK_FOVEATION_DISCOVER` in `fork:src/dxvk/dxvk_foveation.cpp` until T053 passes
- [ ] T055 [US4] Update the `dxvk-foveation` input to the fork commit from T054 and rebuild `.#proton-foveated`
- [ ] T056 [US4] Implement the home module (profiles per game, DXVK config file path, the compat tool, no Steam launch option edited) in `home/modules/vr-foveation/default.nix` until T051 passes, and import it in `flake-modules/home-modules.nix`
- [ ] T057 [US4] Implement the verdicts writer in `pkgs/vr-foveation-bench/vr_foveation_bench/verdicts.py` until T052 passes
- [ ] T058 [US4] Write the Fallout 4 VR profile from discovery output and the first verdict row in `docs/vr-foveation/verdicts.md`
- [ ] T059 [US4] Write the topic doc in `docs/vr-foveation.md`: enabling a game (compat tool plus launch option, since Nix does not manage launch options), measuring, reading verdicts, tuning a profile with a single-launch `DXVK_CONFIG_FILE`, the eye-placement consequence of the shared rate map, known conflicts with frame generation and upscaler overlays, and the screenshot procedure for the accept or reject decision
- [ ] T060 [US4] Write the ADR for the DXVK fork, the compat tool and the env gate, and add its row to the table in `docs/adr/README.md`, in `docs/adr/0027-fork-dxvk-for-foveated-rendering.md`

**Checkpoint**: a new game goes from discovery to a working profile in one sitting (SC-006).

---

## Phase 7: User Story 5 - Vulkan-native and D3D12 titles (Priority: P3)

**Goal**: the same fixed foveation for Vulkan-native games, starting after a go verdict from Phase 4.

**Independent Test**: Half-Life: Alyx with the option on shows lower GPU time and tolerable artefacts.

- [ ] T061 [US5] Decide, with evidence from Phase 4, whether a Vulkan implicit layer or a game-specific route is worth building; record the decision in a new ADR `docs/adr/0028-vulkan-layer-for-native-games.md` before any code
- [ ] T062 [P] [US5] Failing tests for the layer's pipeline rewrite (adds shading-rate state and the creation flag to create infos) in `pkgs/vr-foveation-layer/tests/test_pipeline_rewrite.cpp`, once T061 approves the layer
- [ ] T063 [US5] Implement the layer reusing the profile and rate-map code in `pkgs/vr-foveation-layer/src/`, package it in `pkgs/vr-foveation-layer/default.nix`, and expose it in `flake-modules/packages.nix`
- [ ] T064 [US5] (owner) Install Half-Life: Alyx, run discovery, measure on and off, and add its verdict row to `docs/vr-foveation/verdicts.md`

---

## Phase 8: User Story 6 - Gaze interface (Priority: P4)

**Goal**: the region can follow a gaze source; only fixed and synthetic exist.

**Independent Test**: the synthetic source moves the region along a known path and times out back to the centre.

- [ ] T065 [P] [US6] Failing tests for the gaze sample reader (sequence counter retry on a torn read, stale sample returns the fixed centre after the timeout, invalid flag) and for the region following a synthetic path within one frame of each update, in `fork:tests/foveation/test_gaze.cpp`
- [ ] T066 [P] [US6] Failing test that swapping the source changes nothing in recognition or rate-map code (a source-interface test with a fake source) in `fork:tests/foveation/test_gaze_swap.cpp`
- [ ] T067 [US6] Implement the source interface and the fixed and synthetic sources in `fork:src/dxvk/dxvk_foveation_gaze.{h,cpp}` until T065 and T066 pass
- [ ] T068 [US6] Update the `dxvk-foveation` input to the fork commit from T067 and rebuild `.#proton-foveated`
- [ ] T069 [US6] Document the gaze sample format and how a real source plugs in (OSC or shared memory) in `docs/vr-foveation.md`; no real source is built until a Steam Frame is in hand

---

## Final phase: Polish and cross-cutting

- [ ] T070 [P] Run `just check` and `prek run --all-files`, and fix what they report, in the commit that causes it
- [ ] T071 [P] Add a one-line pointer to `docs/vr-foveation.md` in `CLAUDE.md`, as other modding topics have
- [ ] T072 Autosquash any `fixup!` commits in the PR before merge and confirm `check-no-fixups.sh` passes
- [ ] T073 Run the whole quickstart from a clean state and record the output under `docs/vr-foveation/results/quickstart-run.md`

---

## Dependencies and order

- Phase 1 spikes first. T006 needs T005. T001, T003 and T005 are independent.
- Phase 2 needs T005 and T006 (and the owner's go-ahead for T007). T008 to T015 follow T007, with T010 to T015 parallel.
- Phase 3 (US1) needs Phase 2. The Python tasks T016 to T022 do not need the fork and can start right after T011 and T012. T026 and T027 need T024 and T025.
- Phase 4 (US2) needs Phase 2, and T042 needs the measurement code from T024.
- Phase 5 (US3) needs the code from Phase 4; its tests can be written alongside Phase 4.
- Phase 6 (US4) needs Phase 4 for discovery and the verdicts; T051 to T053 can start earlier.
- Phase 7 (US5) needs a `go` verdict from T042. Phase 8 (US6) needs only Phase 2 and can run in parallel with Phases 5 to 7.
- Polish last.

## Parallel examples

- After T007: T010, T011, T012, T013, T014 and T015 together.
- US1: T016, T017 and T018 together, then T019, T020 and T021 together.
- US2: T028 to T032 together.

## Implementation strategy

- **MVP**: Phases 1 to 5 (US1, US2, US3). That yields one measured on/off comparison on one game with safe fallback. Stop there and read the verdict before going further.
- Each phase ends at a checkpoint that can be shown on its own.
- If Fallout 4 VR gets a `no-go`, pick another heavy D3D11 title for T042 before concluding; a `no-go` for every tried game is a valid and recorded result (SC-003).
