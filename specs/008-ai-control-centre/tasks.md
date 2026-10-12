---

description: "Task list for the AI Control Centre"
---

# Tasks: AI Control Centre

**Input**: Design documents from `/specs/008-ai-control-centre/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: INCLUDED. The constitution (Principle II) and plan require a failing test before behaviour. Each story phase lists its tests first; they MUST fail before the implementation tasks start.

**Organization**: Grouped by user story. Priorities from spec.md: US1, US2, US3 (P1); US4, US6 (P2); US5 (P3).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: US1 to US6 as in spec.md; Setup, Foundational, Web and Polish phases carry none
- **One task = one commit** doing exactly one granular thing (constitution Principle I): it builds, and reverting it alone leaves the tree building. A task that needs a spike, a test and an implementation is three tasks.

**Test-first commits**: a test task lands as its own commit with the new tests marked `#[ignore = "T0nn"]` (or the equivalent skip), so every commit builds and `nix flake check` stays green. The matching implementation task removes the `ignore` and the tests then pass. No squashing; review fixes go in as fixups against the implementation commit.

## Path conventions

Code lives in the `claude-monitor` repository (default `/home/ali/git/personal/claude-monitor`, on a worktree branch `008-ai-control-centre`, never on its main). Paths are relative to that repo root unless prefixed:

- `cm:` — the claude-monitor repo (omitted for `src/`, `tests/`, `nix/`, `Cargo.toml`)
- `nc:` — this nix-config repo (`specs/`, `docs/`, `home/`, `flake.nix`)

Library modules are under `src/` (lib crate `claude_monitor`); `src/main.rs` stays a thin consumer (plan, Structure Decision). Agent-kind and hook contracts: `contracts/`.

---

## Phase 1: Setup (shared)

**Purpose**: decisions recorded, spikes that gate design, a clean baseline.

- [X] T001 Create the `008-ai-control-centre` worktree in the claude-monitor repo and record the baseline: run `nix flake check` and save the output summary in `nc:specs/008-ai-control-centre/research.md` under a new "Baseline" heading
- [X] T002 [P] Draft ADR 0040 (SQLite store, event log as change feed, liveness = pid+start time+boot id, event-driven sources) with status Proposed in `nc:docs/adr/0040-control-centre-store-liveness-event-feed.md` and add it to `nc:docs/adr/README.md`; set to Accepted by T124
- [X] T003 [P] Draft ADR 0041 (code lives in claude-monitor as library + thin binary; loose coupling to cortexiphan via export; constitution scope deviation) with status Proposed, only after the owner confirms the code home, in `nc:docs/adr/0041-control-centre-code-home-cortexiphan-coupling.md` and add it to `nc:docs/adr/README.md`; set to Accepted by T124
- [X] T004 [P] Spike R2: capture raw Claude Code 2.1.293 hook stdin for SessionStart (all `source` values), UserPromptSubmit, PreToolUse/PostToolUse incl. the todo tool, PermissionRequest, Notification, Stop, SessionEnd (all `reason` values); store redacted payloads in `tests/fixtures/claude/` and write the confirmed shapes into `nc:specs/008-ai-control-centre/contracts/hook-payloads.md`
- [X] T005 [P] Spike R1: run `claude --resume` twice from the recorded cwd and once from another cwd in a scratch dir, and a `--fork-session` run; record whether the session id changes, whether resume works from another cwd, and how a fork appears on disk, in `nc:specs/008-ai-control-centre/research.md` (D4)
- [X] T006 [P] Spike R8: a throwaway test in `tests/spikes/wal_notify.rs` committing in one process and timing the `notify` callback in another over 1000 iterations on Linux; record latency and any missed events in `nc:specs/008-ai-control-centre/research.md` (D12)
- [X] T006a [P] Spike R10: inspect `~/.claude/sessions/<pid>.json` for live interactive sessions (keys, when written/removed, status values, tmux field), record in `nc:specs/008-ai-control-centre/research.md` D2

**Checkpoint**: fixtures and measurements exist; design assumptions confirmed or the docs corrected before code depends on them.

---

## Phase 2: Foundational (blocks all stories)

**Purpose**: library/binary split, store, event feed, command skeleton, Claude hook ingest.

- [X] T007 Refactor only: move `session`, `hook_cmd`, `tmux`, `watcher`, `ui`, `dashboard`, `desktop_notify` into the library (`src/lib.rs`, `src/hook.rs`, `src/tmux.rs`, `src/tui/`, `src/notify.rs`), shrink `src/main.rs` to argument parsing plus `claude_monitor::cli::run`; existing ~35 tests move with the code and still pass
- [X] T008 Add cargo features `tui` and `web` (both default) and gate `ratatui`/`crossterm` and (later) `axum`/`tokio`; add `tests/features.rs` asserting `cargo build --no-default-features` has neither in `cargo tree` and that `src/main.rs` is under 60 lines (quickstart S0) in `Cargo.toml`, `tests/features.rs`
- [X] T009 [P] Add dependencies `rusqlite` (bundled), `thiserror`, `uuid` and make `cargo deny check` pass in `Cargo.toml`, `deny.toml`
- [X] T010 [P] Write state-machine tests (transitions from data-model.md incl. `clear` lineage step and Copilot abnormal end → interrupted), ignored until T011, in `tests/state_machine.rs`
- [X] T011 Implement `State`, `Session`, `Project`, `Step`, `Note`, `Attribution` types and the pure transition function in `src/model.rs` (removes the ignores from T010)
- [X] T012 Write store tests (create schema, migrate from empty and from v1, WAL on, 0600 mode, `--state-dir` override), ignored until T013, in `tests/store.rs`
- [X] T013 Implement SQLite schema and migrations per data-model.md in `src/store/mod.rs`, `src/store/schema.rs`, `src/store/migrations.rs` (removes the ignores from T012)
- [X] T014 Write `events` table tests (append-only, `seq` cursor, author fields, "only record real changes"), ignored until T015, in `tests/events.rs`
- [X] T015 Implement the append-only `events` table and cursor API in `src/store/events.rs` (removes the ignores from T014)
- [X] T016 [P] Define provider traits (`Clock`, `BootId`, `Processes`, `Tmux`, `Notifier`, `Fs`) with real and fake implementations and an `Env` bundle in `src/env.rs`, `src/testing.rs`
- [X] T017 Define the `Command` enum, `Output` (text and `--json`), the `Error` type (thiserror) and its exit-code mapping (0/1/2/3) and the `cli::run(cmd, &Env)` skeleton, with clippy deny rules extended to new modules, in `src/cli/mod.rs`, `src/cli/output.rs`, `src/error.rs`
- [X] T018 Write the CLI conformance test over the `Command` enum: every command has `--json` output that parses, errors are `{"ok":false,"error":...}`, exit codes are 0/1/2/3 as in `contracts/cli.md`, and every interactive TUI action maps to a `Command` (quickstart S0 parity, FR-035), ignored per command until implemented, in `tests/cli_conformance.rs`
- [X] T019 Write legacy-migration tests (import runtime JSON files once, ignore afterwards, run on first start; FR-022), ignored until T020, in `tests/legacy_migrate.rs`
- [X] T020 Implement `migrate` in `src/store/legacy.rs`, `src/cli/migrate.rs` (removes the ignores from T019)
- [X] T021 Define `trait AgentKind` and the `HookEvent` set per `contracts/agent-kind.md` in `src/agents/mod.rs`. Note (spikes R1/R2): `HookEvent` carries `source` and the raw `reason`, `Stop` carries the last assistant message, and `PermissionRequest` has no tool-use id
- [X] T022 Write Claude hook-parser fixture tests against the T004 fixtures, ignored until T023, in `tests/claude_hook.rs`
- [X] T023 Implement the Claude `AgentKind` parser in `src/agents/claude.rs` (removes the ignores from T022)
- [X] T024 Write hook-ingest tests: always exit 0, empty stdout, errors to `<state-dir>/hook.log` with a UTC timestamp, `busy_timeout` ≤ 200 ms, p95 < 50 ms benchmark, `ToolSearch` tool events filtered out (they fire Pre/PostToolUse but are not work), ignored until T025, in `tests/hook_ingest.rs`
- [X] T025 Rewrite `hook` to write the store using the Claude parser in `src/hook.rs` (removes the ignores from T024)
- [X] T026 Write `ChangeFeed`/`EventSource` tests (fs watcher over the state dir with a start-anchored 50 ms throttle window, `events.seq` cursor, replay from a given seq, fake source, no sleeps), ignored until T027, in `tests/feed.rs`
- [X] T027 Implement `ChangeFeed`, `EventSource` and the fs-watcher source with a start-anchored 50 ms throttle window (fire 50 ms after the first event of a group, then re-arm; a trailing debounce starves under continuous writes, R8) and a wake-up-then-requery-by-`events.seq` design, in `src/feed/mod.rs`, `src/feed/fs.rs` (removes the ignores from T026)

**Checkpoint**: store, events, hook ingest and feed work; the old dashboard still runs (reading the store in T031).

---

## Phase 3: User Story 1 — one-glance overview (P1) 🎯 MVP

**Goal**: every session of every supported agent in one list with state, location, task and age; waiting-on-me first. Claude first, Copilot after.

**Independent test**: quickstart S1, S9.

### Tests (write first, must fail)

- [X] T028 [P] [US1] Overview query tests: three worktrees, mixed states, `needs_permission` ordered first, sections active, interrupted and finished, flags (the done, dismissed and project section assertions are in Phase 8: T104 to T106) in `tests/overview.rs`
- [X] T029 [P] [US1] `list --json` shape and filter tests per `contracts/cli.md` in `tests/cli_list.rs`
- [X] T030 [P] [US1] TUI model tests with ratatui `TestBackend`: ordering, selection, live update on a feed event in `tests/tui.rs`

### Implementation

- [X] T031 [US1] Implement the overview/section/filter queries (indexes per data-model) in `src/store/queries.rs`
- [X] T032 [US1] Implement `list` and `show` commands in `src/cli/list.rs`, `src/cli/show.rs`
- [X] T033 [US1] Rebuild the TUI as pure `update`/`view` over the query and feed (keeps j/k, Enter-to-pane, d, q, notifications) in `src/tui/state.rs`, `src/tui/view.rs`, `src/tui/mod.rs`
- [X] T034 [P] [US1] Spike R3: install throwaway hooks under a temporary `COPILOT_HOME`, run a trivial Copilot session, record payloads, whether `$PPID` is the agent, resume from another cwd, and `permissionRequest` shape into `tests/fixtures/copilot/` and `nc:specs/008-ai-control-centre/research.md` (D7)
- [X] T035 [P] [US1] Spike R6: with the Claude monitor hooks registered in `~/.claude/settings.json`, run Copilot and count whether it fires them; record in `nc:specs/008-ai-control-centre/research.md`
- [X] T036 [US1] Decision gate: if T034 shows Copilot cannot report state or resume, update `nc:specs/008-ai-control-centre/spec.md` Assumptions and FR-004 notes to the FR-014 / "state unknown" fallback and tell the owner before continuing T037 to T042. Outcome 2026-10-12: gate passed (partly, mostly yes); no fallback needed; limits recorded in spec Assumptions
- [X] T037 [US1] Write Copilot hook-parser fixture tests (camelCase and snake_case), ignored until T038, in `tests/copilot_hook.rs`
- [X] T038 [US1] Implement the Copilot hook parser in `src/agents/copilot.rs` (removes the ignores from T037)
- [X] T039 [US1] Write Copilot passive-discovery tests (`session-state/*/workspace.yaml`, first `user.message`, state `unknown`, read-only, no assistant content), ignored until T040, in `tests/copilot_discover.rs`
- [X] T040 [US1] Implement Copilot passive discovery in `src/agents/copilot_discover.rs` (removes the ignores from T039)
- [X] T041 [US1] Add the Copilot hooks file (`~/.copilot/hooks/claude-monitor.json`, `version: 1`) and the `--agent` flag to the Home Manager module, with an eval check, in `nix/hm-module.nix`, `flake.nix`; document the trustedFolders requirement in the option description
- [X] T042 [US1] Add a `notify` watch on `~/.copilot/session-state/` as an `EventSource` so new Copilot sessions appear without a rescan in `src/feed/copilot.rs`, `tests/feed.rs`
- [X] T043 [P] [US1] Write Claude passive-discovery tests: sessions found by scanning `~/.claude/projects/*/*.jsonl` (not `sessions-index.json`, which newer versions no longer write; the encoded cwd is lossy, so take `cwd` from the transcript lines) get a record with cwd, first prompt and timestamps and state `unknown`, no conversation content beyond the first prompt, and a later hook upgrades the same record instead of duplicating it, ignored until T044, in `tests/claude_discover.rs`
- [X] T044 [US1] Implement Claude passive discovery as `AgentKind::discover` plus a `notify` watch on `~/.claude/projects` as an `EventSource`, covering sessions started before the hooks existed or by a tool without them; scan `*.jsonl`, not `sessions-index.json`, and consider the `~/.claude/sessions/<pid>.json` registry once T006a (R10) is done; also detect forks by shared message uuids (T072), in `src/agents/claude_discover.rs`, `src/feed/claude.rs` (removes the ignores from T043)
- [X] T045 [US1] Add-a-kind test (SC-008, FR-004): register a third fake `AgentKind` and run list, persist, respawn and export unchanged in `tests/third_agent_kind.rs`, ignored per step until respawn (T073) and export (T098) exist
- [x] T045a [US2] Write tests for the Claude session registry reader: parses `~/.claude/sessions/<pid>.json` (tolerates missing status and keys, retries once on a parse failure), maps status busy/waiting/idle/shell/missing to states, treats a file as live only when the pid is alive and `procStart` matches `/proc/<pid>/stat` field 22 (stale after `kill -KILL`, pid reuse), filters `entrypoint != cli`, never reads the `.key` files, takes the `tmux` field as `session:@window.%pane`, ignored until T045b, in `tests/claude_registry.rs`
- [x] T045b [US2] Implement the Claude session registry reader and a `notify` `EventSource` on `~/.claude/sessions` feeding liveness, status and pane into reconcile in `src/agents/claude_registry.rs`, `src/feed/registry.rs` (removes the ignores from T045a)

**Checkpoint**: US1 independently demonstrable in the TUI and `list --json` for Claude and Copilot.

---

## Phase 4: User Story 2 — work survives dead sessions (P1)

**Goal**: kills and reboots never lose a session; they show as interrupted, clean ends as finished and stay visible.

**Independent test**: quickstart S2.

### Tests (write first)

- [x] T046 [P] [US2] Kill test: fake process dies without `SessionEnd` → `interrupted` immediately on the exit event in `tests/durability.rs`
- [x] T047 [P] [US2] Reboot test: changed boot id marks every non-finished session interrupted in one pass; finished stays finished; reconcile idempotent in `tests/durability.rs`
- [x] T048 [P] [US2] Finished-stays-visible test: clean `SessionEnd` → finished, listed in the default query, respawnable flag set, `clear` creates a lineage step in `tests/durability.rs`
- [x] T049 [P] [US2] Degraded-record test: one corrupt row yields a `degraded` entry while the rest of the list works (FR-021) in `tests/degraded.rs`
- [x] T050 [P] [US2] Reconcile-on-open test: starting the TUI, `serve` or `list` with a killed session still recorded as running shows it `interrupted` before the first render, with no hook or watcher having fired (FR-008, SC-005) in `tests/reconcile_on_open.rs`

### Implementation

- [x] T051 [US2] Capture pid, pid start time and boot id in the hook (Linux `/proc`) behind the `Processes`/`BootId` providers in `src/liveness.rs`, `src/hook.rs`. Pid capture prefers the hook's `$PPID` and cross-checks the `~/.claude/sessions` registry when present (R10).
- [x] T052 [US2] Implement `reconcile` (all, `--pane`, `--session`), including `worktree_exists` refresh, as a pure function over the providers plus the CLI command in `src/reconcile.rs`, `src/cli/reconcile.rs`
- [x] T053 [US2] Run `reconcile` once at TUI start, `serve` start and `list`/`show`, before the first render (viewers correct a death nobody was watching) in `src/cli/mod.rs`, `src/tui/mod.rs`
- [x] T054 [US2] Implement the process-exit `EventSource` (`pidfd_open` + poll on Linux) with a real-OS test that kills a child, wired into the feed, in `src/feed/proc_exit.rs`, `tests/proc_exit.rs`
- [ ] T055 [P] [US2] Spike R5: record the macOS boot id (`sysctl kern.boottime`), start time (`ps -o lstart=`) and `kqueue` `NOTE_EXIT` behaviour in `nc:specs/008-ai-control-centre/research.md` (D2)
- [ ] T056 [US2] Implement macOS liveness behind `cfg(target_os = "macos")`, verified by the macOS CI build, in `src/liveness_macos.rs`, `.github/workflows/ci.yml`
- [x] T057 [P] [US2] Spike R9: on a private tmux server check that `pane-exited`, `pane-died` and `window-unlinked` hooks fire for panes running the agents and can pass the pane id; record in `nc:specs/008-ai-control-centre/research.md` (D12)
- [x] T058 [US2] Add tmux `set-hook` entries (`pane-exited`, `pane-died`, `window-unlinked`) calling `claude-monitor reconcile --pane`, with tools resolved by Nix store path, to the Home Manager module in `nix/hm-module.nix`
- [x] T059 [US2] Add the 60 s safety-net reconcile (only while a viewer is open) as a feed source with a test where a dropped event is repaired in `src/feed/safety_net.rs`, `tests/feed.rs`
- [x] T060 [US2] Implement the optional headless `watch` command in `src/cli/watch.rs`
- [x] T061 [US2] Add the off-by-default `watch` user-service option to the Home Manager module in `nix/hm-module.nix`

### Gaps found while building Phase 4 (investigate and close before Phase 5)

- [x] T051a [US2] Finish T051: cross-check the hook's `$PPID` against the `~/.claude/sessions` registry (pid, `procStart`) and prefer the registry when they disagree, in `src/hook.rs`
- [x] T062a [US2] Investigate the "unknown" clutter: the real-HOME smoke run found 177 sessions, 125 Claude and 39 Copilot of them `unknown` (disk-only, no pid, no hook history). Decide how they group in `list`/TUI (own "unseen" section, collapsed by default, never counted as active) and whether age should matter; write the finding in `research.md`, then implement the grouping with tests
- [x] T062b [US1] Fix FR-019: finished sessions must not be hidden by age. `overview` currently collapses finished sessions older than a threshold under a count; make them always listable and respawnable (per-project "done" stays the user-set tidy-up), with a test in `tests/overview.rs`
- [x] T062c [US2] Copilot hook event name: have the Copilot hooks file pass the event name explicitly instead of the parser inferring it from fields; keep inference as the fallback, in `src/agents/copilot.rs`, `nix/hm-module.nix`
- [ ] T062d [US2] Rewrite the Phase 4 commits that put implementation and tests in one commit (`spawn_live`, dashboard `warning_line`, `watch` subcommand parse) into test-then-implementation pairs, and autosquash the `fixup!` commit (`cb8d051`), before any merge
- [x] T062e [US2] Document and test the tmux multi-pane gap (R9: `kill-pane` of one pane in a multi-pane window fires no hook) as covered by the 60 s safety net, in `research.md`, `tests/safety_net.rs`
- [ ] T062f [US2] Real-hook activation: bump the claude-monitor flake input in nix-config so the user's hooks feed the new build (live change: ask the user first), in `nc:home/programs/claude-code/default.nix`, `flake.lock`
- [ ] T062g [US1] Decide `delete` (CLI contract has it, no task): add a task in Phase 8 or drop it from `contracts/cli.md`
- [ ] T062h [US2] macOS liveness (T055/T056) stays deferred until a macOS machine is available; track in `PENDING.md`

**Checkpoint**: kill and reboot scenarios pass; US1 and US2 together are a durable overview; the gaps above are closed or explicitly deferred.

---

## Phase 5: User Story 3 — respawn where they were (P1)

**Goal**: one action (or a multi-selection, or all interrupted) restarts sessions in their worktrees; post-login prompt with opt-out; finished sessions respawn the same way.

**Independent test**: quickstart S3, S4.

### Tests (write first)

- [x] T062 [P] [US3] Spike R7: prove a private `tmux -S` server runs inside a Nix `runCommand` check; keep it as the harness in `tests/tmux_harness.rs`, `flake.nix`
- [x] T063 [P] [US3] Planner tests: missing directory, missing transcript, branch gone, already running, no launcher, no tmux, agent without resume → fresh + notice, finished respawn identical to interrupted in `tests/respawn_plan.rs`
- [x] T064 [P] [US3] Alternatives tests: a missing worktree whose branch still exists gets a refusal that includes a `git worktree add` suggestion, and `respawn --recreate-worktree` runs it only when asked; a missing worktree with no branch suggests `respawn --fresh --in <repo_root>` (new session in the main checkout, saying history is not restored); nothing is ever created automatically (US3 scenario 3) in `tests/respawn_alternatives.rs`
- [x] T065 [P] [US3] Private-tmux integration tests: single respawn lands in the recorded cwd, five at once, lineage `resumed_from` set from the next `SessionStart` in the recorded pane, no duplicate row in `tests/respawn_tmux.rs`
- [x] T066 [P] [US3] `boot-check` tests: with interrupted sessions emits one notification, writes the marker and starts nothing; with none emits nothing; finished sessions neither selected nor counted (FR-019a, FR-034); `boot-check --banner` prints the one-line message once via the `Tmux` provider and clears the marker (FR-032) in `tests/boot_check.rs`
- [x] T067 [P] [US3] Fork lineage test (spec edge case): a forked conversation (per the R1 findings in T005) becomes a separate session with `forked_from` set and is not collapsed into the head of the respawn chain; a respawn linked through a `RespawnRequest` still collapses, in `tests/lineage_fork.rs`

### Implementation

- [x] T068 [US3] Implement the respawn planner (checks, refusal codes) and the launcher templates (`{session_id}`, `{cwd}`, `{name}`) in `src/respawn.rs`
- [x] T069 [US3] Implement the refusal alternatives and the `--recreate-worktree` and `--fresh --in <dir>` flags in `src/respawn.rs`, `src/cli/respawn.rs`
- [x] T070 [US3] Implement the tmux executor (create server/session `agents` if absent, window per session, `-c <cwd>`) behind the `Tmux` provider in `src/tmux.rs`
- [x] T071 [US3] Link a respawn: a `SessionStart` with `source=resume` and a known session id revives that record in place (resume keeps the id, T005); only `/clear` (`source=clear`, new id) creates a `resumed_from` link; tolerate an unexpected new id by treating the pane's open `RespawnRequest` as the link, in `src/hook.rs`, `src/respawn.rs`
- [x] T072 [US3] Record forks: Claude writes no parent link, so detect a fork at passive discovery by shared message uuids with an existing transcript, and record parent to child ourselves when we launch `--fork-session`; the fork gets `forked_from` and its own chain (store column in data-model.md). A fork launched by hand with no record shows as independent, in `src/hook.rs`, `src/store/schema.rs`
- [x] T073 [US3] Implement `respawn` and `restore` commands (`--all-interrupted`, `--include-finished`, `--fresh`, `--yes`; exit codes 2/3 per contract) in `src/cli/respawn.rs`, `src/cli/restore.rs`
- [x] T074 [US3] Add the restore view to the TUI: checkboxes, all interrupted pre-selected, finished unselected, deselect to opt out (deselected stay interrupted, not dismissed), Enter respawns, in `src/tui/restore.rs`, `tests/tui.rs`
- [x] T075 [US3] Implement `boot-check` (reconcile, notify, write marker, start nothing) in `src/cli/boot_check.rs`
- [x] T076 [US3] Implement `boot-check --banner` (one-line tmux `display-message`, then clear the marker) in `src/cli/boot_check.rs`
- [x] T077 [US3] Add the systemd login user unit running `boot-check`, with tools resolved by Nix store path, to the Home Manager module in `nix/hm-module.nix`
- [x] T078 [US3] Add the launchd agent running `boot-check` for macOS to the Home Manager module in `nix/hm-module.nix`
- [x] T079 [US3] Add the tmux `client-attached` hook running `boot-check --banner` to the Home Manager module in `nix/hm-module.nix`
- [x] T080 [US3] Add the `launchers.<kind>` and tmux-session options to the Home Manager module in `nix/hm-module.nix`
- [ ] T081 [US3] Enable the new module options in `nc:home/programs/claude-code/default.nix`
- [ ] T082 [US3] Extend the prefix+A binding with the restore view in `nc:home/programs/tmux/tmux.conf.nix`

**Checkpoint**: US1 to US3 form the MVP; run the manual lines of quickstart S3/S4 once with real agents.

---

## Phase 6: User Story 4 — where large projects stand (P2)

**Goal**: progress with a named source, "where we left off", optional local-model summary.

**Independent test**: quickstart S5.

### Tests (write first)

- [x] T083 [P] [US4] Parser tests incl. property tests: spec-kit `tasks.md` (phases, `T###`, `[P]`, `[US#]`), generic checklists, recorded todo-tool payload; 4 of 10 yields "4 of 10" and the current item in `tests/progress_parse.rs`
- [x] T084 [P] [US4] Binding tests: auto-bind via branch prefix or `.specify/feature.json`, ambiguous candidates → pick-one result and no figure, choice persists across restart, no binding → no figure (FR-015a, FR-016) in `tests/progress_bind.rs`
- [x] T085 [P] [US4] Summary tests: verbatim `task_description`/`left_off` from hook payload or transcript tail; model call rejected for any non-loopback endpoint; model text stored separately and labelled (FR-017a, FR-020) in `tests/summary.rs`

### Implementation

- [x] T086 [P] [US4] Implement the spec-kit and generic checklist parsers in `src/progress/speckit.rs`, `src/progress/checklist.rs`
- [x] T087 [P] [US4] Implement the agent todo-list snapshot from PostToolUse. The source is unverified and optional: T004 found no todo tool in this environment's Claude Code, so the shape is not captured; the implementation must tolerate its absence (spec-kit `tasks.md` and Markdown checklists are the verified sources). In `src/progress/todo.rs`
- [x] T088 [US4] Implement bindings, candidate discovery and the `progress bind` command in `src/progress/binding.rs`, `src/cli/progress.rs`
- [x] T089 [US4] Add a `notify` watch on bound files as an `EventSource` that re-parses only the changed file in `src/feed/files.rs`
- [x] T090 [US4] Implement verbatim summaries (first prompt; latest assistant message from the Stop payload or transcript tail) in `src/summary.rs`, `src/hook.rs`
- [x] T091 [US4] Implement the loopback-only OpenAI-compatible client and the `summaries` table in `src/summary.rs`, `src/store/schema.rs`
- [x] T092 [US4] Implement the `summarize` command in `src/cli/summarize.rs`
- [x] T093 [US4] Show progress with its source label and both summaries in the TUI detail and `show --json` in `src/tui/detail.rs`, `src/cli/show.rs`

**Checkpoint**: S5 passes; progress survives the session being killed.

---

## Phase 7: User Story 6 — ready to merge into cortexiphan (P2)

**Goal**: attributed, idempotent export in cortexiphan's vocabulary; links and conflicts; works with cortexiphan absent.

**Independent test**: quickstart S8.

### Tests (write first)

- [x] T094 [P] [US6] Golden-file test: a project with 20 steps and linked sessions exports to a checked-in file; two exports byte-identical; round trip stable in `tests/export_golden.rs`, `tests/fixtures/export/project20.jsonl`
- [x] T095 [P] [US6] Mapping tests: statuses, authors (`user`→`User`, `agent`→`Llm{model}`, `system`→`Connector`), `external{system,id}`, no conversation text unless `--include-text` in `tests/export_mapping.rs`
- [x] T096 [P] [US6] Link and conflict tests: link rows, `links check` with a fake cortexiphan CLI (agree, disagree, unreachable), never writes either side in `tests/links.rs`

### Implementation

- [x] T097 [US6] Implement the cortexiphan export module in `src/export/cortexiphan.rs`
- [x] T098 [US6] Implement the `export cortexiphan` command in `src/cli/export.rs`
- [x] T099 [US6] Generate `contracts/cortexiphan-export.schema.json` from the Rust types, check it in, and fail the build if they diverge in `src/export/schema.rs`, `nc:specs/008-ai-control-centre/contracts/cortexiphan-export.schema.json`
- [x] T100 [US6] Implement `CortexiphanLink` storage and the `link` command in `src/export/links.rs`, `src/cli/link.rs`
- [x] T101 [US6] Implement `links check` (best-effort shell-out to `cortexiphan --json node get` only when server and token are set) in `src/export/links.rs`, `src/cli/link.rs`
- [x] T102 [US6] Verify FR-029: add a fixture project mirroring cortexiphan's own worktrees and spec task lists and assert it needs no special-casing in `tests/cortexiphan_project.rs`
- [x] T103 [US6] Show link status and disagreements in the TUI and `show --json` in `src/tui/links.rs`

**Checkpoint**: S8 passes; the file is ready for a future cortexiphan loader.

---

## Phase 8: User Story 5 — group, annotate, tidy (P3)

**Goal**: projects, notes, park/dismiss, done sections (global and per project), filters, scale.

**Independent test**: quickstart S6 (`organise::`).

### Tests (write first)

- [x] T104 [P] [US5] Organise tests: group three sessions, note, dismiss hidden by default and returned by `--include-dismissed`, history intact; also the done, dismissed and project section assertions moved from the overview tests, in `tests/organise.rs`
- [x] T105 [P] [US5] Done-section tests (`organise::done_sections`): each session in exactly one group, per-project Done lists only its project, global Done for no-project sessions, `done` rejected for non-finished, `undone`, respawn clears `done_at`, no Done without a user-authored event in `tests/organise.rs`
- [x] T106 [P] [US5] `organise::finished_visible`: finished never hidden by age, collapsed older ones expand, not pre-selected by `restore`, respawn returns it to active in `tests/organise.rs`
- [x] T107 [P] [US5] Scale test: 500 historical sessions open in under 2 s with the default sections (SC-007) in `tests/perf.rs`

### Implementation

- [x] T108 [US5] Implement projects and the `group` command with their events in `src/store/projects.rs`, `src/cli/project.rs`
- [x] T109 [US5] Implement notes and the park/dismiss markers with their events in `src/store/markers.rs`, `src/cli/markers.rs`
- [x] T110 [US5] Implement `done`/`undone`, the `done_at` rule and the `--section` filter in `src/store/markers.rs`, `src/cli/done.rs`
- [x] T111 [US5] Add project views with their own Active, Interrupted, Finished and Done sections, the global Done section and filters to the TUI in `src/tui/projects.rs`, `src/tui/filter.rs`
- [x] T112 (DROPPED 2026-10-12: FR-019 forbids hiding finished sessions by age; superseded by T062b and the unseen section) [US5] Add the finished-group collapse rule (recent N days listed, older under a count, N configurable) in `src/store/queries.rs`, `nix/hm-module.nix`

**Checkpoint**: S6 passes.

---

## Phase 9: Web view (FR-030, FR-031, SC-011)

**Purpose**: loopback web UI with parity to the TUI. Cross-cutting, so no story label.

- [x] T113 [P] Write security tests: loopback-only bind, foreign `Host` → 421, missing or wrong token → 401, CSRF header on POST, no CORS headers, no transcript route, ignored until T117, in `tests/web_security.rs`
- [x] T114 [P] Write SSE tests with the fake feed: pushed change carries `seq` and what changed, reconnect with `Last-Event-ID` replays missed changes, keepalive, ignored until T118, in `tests/web_sse.rs`
- [x] T115 [P] Write the web parity test enumerating the library `Command` enum against web routes (SC-011), ignored until T119, in `tests/parity_web.rs`
- [x] T116 Run a design pass (invoke the `frontend-design` skill) for the overview, project and restore pages: waiting-on-me rows unmissable, calm otherwise, responsive, keyboard accessible; record decisions, and the templating and htmx choice, in `nc:specs/008-ai-control-centre/research.md` (D10)
- [x] T117 Implement `serve` with the security rules, token file (0600) and cookie hand-off (tokio started only here) in `src/web/mod.rs`, `src/web/auth.rs`, `src/cli/serve.rs`
- [x] T118 Implement the SSE endpoint driven by the `ChangeFeed` in `src/web/events.rs`
- [x] T119 Implement server-rendered pages and routes per `contracts/web-api.md` using the templating and htmx decision recorded in T116 (default if unanswered: `maud` plus vendored htmx, no external hosts) in `src/web/pages.rs`, `src/web/routes.rs`
- [x] T120 Add the `serve` user-unit option to the Home Manager module in `nix/hm-module.nix`
- [x] T121 Browser-verify with the `webapp-testing` skill: load the overview, mark a finished session done, find it in the right project's Done section, respawn it, confirm a TUI change appears within 10 s; save the evidence in the PR description

---

## Phase 10: Polish and cross-cutting

- [ ] T122 [P] Bump the `claude-monitor` flake input in `nc:flake.nix`, `nc:flake.lock`
- [x] T123 Write the topic doc `nc:docs/ai-control-centre.md` (what it is, how to enable the `programs.claude-monitor` options, hooks and units installed, state and log locations, recovery steps, how to export for cortexiphan), in the same nix-config PR as T122 (constitution Principle VI)
- [ ] T124 Set ADRs 0040 and 0041 to Accepted in `nc:docs/adr/0040-control-centre-store-liveness-event-feed.md`, `nc:docs/adr/0041-control-centre-code-home-cortexiphan-coupling.md`, in the same PR as T123
- [x] T125 [P] Add a one-paragraph pointer to `docs/ai-control-centre.md` in `nc:CLAUDE.md`, following the existing "Memory and skill retrieval" entry
- [x] T126 [P] Document how to add an agent kind (checklist from `contracts/agent-kind.md`) and the CLI in claude-monitor's `README.md`, and keep the `nc:` contracts in sync
- [x] T127 [P] No-egress test (FR-020): with a network-denying fake, every command except `links check` and `summarize` (loopback only) opens zero non-loopback connections, and nothing in the export or web paths sends session content anywhere, enumerating the `Command` enum so it covers every command, in `tests/no_egress.rs`
- [x] T128 [P] Absence test (SC-010): the whole US1 to US5 suite passes with `cortexiphan` absent from `PATH` in `tests/no_cortexiphan.rs`
- [x] T129 [P] Run `cargo clippy -- -D warnings`, `cargo fmt --check`, `cargo deny check`, `nix flake check` in claude-monitor and `just check` plus `prek run --all-files` in nix-config; fix findings in separate commits
- [ ] T130 Run quickstart S0 to S9 end to end, recording the manual-only success criteria as measured values (SC-001 under 1 minute and 3 actions to resume, SC-002 20 sessions read in 10 s, SC-004 95% respawn success, SC-006 90% re-entry, SC-012 at most 2 actions to done), run the manual lines once with real Claude and Copilot sessions, and record the outputs in the pull request descriptions (constitution Principle II)
- [x] T131 Run `/speckit-analyze` and resolve every CRITICAL finding before merging

---

## Dependencies and order

- Phase 1 spikes (T004 to T006) gate the fixtures used by T022 to T027. T002 can run any time; T003 waits for the owner's confirmation of the code home.
- Phase 2 blocks all stories. Inside it: T007 → T008; T010 → T011; T012 → T013; T014 → T015; T016 before T017; T018 needs T017; T019 → T020; T021 → T022 → T023; T024 → T025 (needs T013, T015, T023); T026 → T027 (needs T015 and T006).
- US1 (Phase 3) needs Phase 2. Copilot tasks T034 to T042 depend on T023 and can run alongside T031 to T033. T036 is a decision gate on T034. Claude passive discovery T043/T044 needs T023 and T027. T045 is completed in stages as respawn (T073) and export (T098) land.
- T045a/T045b need T043/T044 (discover) and T052 (reconcile).
- US2 (Phase 4) needs US1's queries (T031) and Phase 2. T053 needs T052. T054 needs T027. T056 needs T055; T058 needs T057.
- US3 (Phase 5) needs US2 (liveness, reconcile) and T005. T069 needs T068. T071 needs T068 and T070. T072 needs T071 and the T005 fork findings. T076 needs T075. T077 to T080 need T075 and T076; T081/T082 need T080.
- US4 (Phase 6) needs Phase 2 and T023; independent of US3.
- US6 (Phase 7) needs the `events` table (T015); its realistic fixtures want projects (T108), so schedule it after T108 even though its priority is P2, using fixture rows meanwhile.
- US5 (Phase 8) needs US1's queries and, for the `done_at` rules, US3's respawn (T068, T071).
- Web (Phase 9) needs US1 to US5 library commands (it renders them) and T027. T119 needs T116.
- Polish needs everything it touches; T123 and T124 land in the same PR as T122. T127 and T128 run last because they range over every command and suite.

### Parallel examples

- After T006: T007 alone first (everything moves), then T008/T009/T010/T012/T014/T016 in parallel.
- US1: T028, T029, T030, T034, T035, T043 in parallel; then T031 → T032/T033; Copilot T037/T039 in parallel after T036.
- US2: T046 to T050 in parallel; T055 and T057 parallel to T051 to T054.
- US3: T062 to T067 in parallel.
- US4: T083 to T085 in parallel; T086 and T087 in parallel.
- US6: T094 to T096 in parallel.

## Implementation strategy

1. **MVP = Phases 1, 2, 3 (Claude part, T028 to T033 and T043/T044), 4 and 5**: a durable overview that survives kills and reboots and respawns sessions, for Claude Code. Stop and run the manual lines of S2/S3/S4 with real sessions.
2. Add the Copilot part of US1 (T034 to T042) as soon as T036's gate is decided; if Copilot cannot meet FR-004, the spec is amended before more code.
3. Then US4 and US6 (P2), then US5 (P3), then the web view, then polish.
4. Each task is its own commit; review fixes as fixups against the task's implementation commit (constitution Principle I); no squashing; merge by local rebase and fast-forward push.
