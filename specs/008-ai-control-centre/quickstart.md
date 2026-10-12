# Quickstart: validating the AI Control Centre

Run from the `claude-monitor` repository root unless stated. Each scenario names the spec requirement it proves. "Auto" scenarios are CI checks (`nix flake check`); "Manual" ones need a real agent or desktop session and cover the glue CI cannot (notifications, real resume).

## Prerequisites

- `nix develop` (Rust toolchain, `tmux`, `sqlite`).
- A scratch state dir so the real one is untouched: `export XDG_STATE_HOME=$(mktemp -d)`.
- Fixtures: `tests/fixtures/{claude,copilot}/*.json` (recorded hook payloads, created by spikes R1, R2, R3).

Tests call the library (`claude_monitor::cli::run` with injected providers, TUI `update`/`view` with `TestBackend`); the "Manual" lines and a handful of `assert_cmd` smoke tests are the only places the real binary runs.

## S0: library/binary split (FR-035)

Auto: `cargo build --no-default-features` builds the library without `ratatui` or `tokio` in the dependency tree (`cargo tree --no-default-features | grep -E 'ratatui|tokio'` prints nothing). A test asserts `src/main.rs` stays under 60 lines. A parity test asserts every `Command` variant has both a CLI subcommand and, where interactive, a TUI action, and that each emits valid JSON with `--json`.

## S1: overview (US1; FR-001 to FR-003)

Auto: `cargo test overview::` feeds the Claude and Copilot fixtures for three worktrees through `claude-monitor hook`, then asserts the query behind the view returns three rows with agent, repo, branch, state, task description and age, with `needs_permission` ordered first.
Manual: `claude-monitor` shows the same list; the waiting row sorts first.

## S2: durability (US2; FR-005 to FR-008, SC-003)

Auto: `cargo test durability::kill` starts a fake agent process, sends `SessionStart`, kills it with SIGKILL, runs reconcile, asserts `interrupted`. `durability::reboot` swaps the boot-id provider and asserts every non-finished session becomes `interrupted` in one pass while a `SessionEnd`ed one stays `finished`.
Manual: with real sessions open, reboot, log in, `claude-monitor list --json` still lists all, none `working`.

Event-driven checks (research D12): `feed::` tests inject a fake `EventSource` and assert, with no `sleep` anywhere, that (a) a committed event reaches the TUI model and the SSE stream carrying its `seq` and what changed; (b) a dropped SSE connection resumed with `Last-Event-ID` replays exactly the missed changes; (c) a process-exit event for a running session reconciles that session to `interrupted` immediately; (d) the 60 s safety-net reconcile repairs a deliberately dropped event; (e) with no viewer open, a tmux `pane-exited` invocation of `claude-monitor reconcile --pane` updates the store. One real-OS test (Linux CI, `pidfd`) kills a child process and asserts the exit event arrives.

`reconcile_on_open::` kills a session recorded as running and asserts the TUI model, `list` and `serve` start-up all show it `interrupted` before first render. `claude_discover::` finds a Claude session that no hook ever reported and lists it as `unknown`, then upgrades the same record when a hook arrives.

## S3: respawn (US3; FR-009 to FR-014, SC-001, SC-004)

`respawn_alternatives::` asserts a missing worktree with a surviving branch prints the `git worktree add` suggestion and creates nothing until `--recreate-worktree` is given, and one with no branch prints `respawn --fresh --in <repo_root>`.

Auto: `cargo test --test respawn` runs a private `tmux -S $TMP/sock` server with a stub launcher that records its cwd and args. Cases: single respawn lands in the recorded worktree; five at once land in five worktrees; missing directory is refused with the path in the message and nothing starts; already running is refused; no-resume agent starts fresh and returns the "history not restored" notice; the following `SessionStart` from the new pane links `resumed_from` and the overview shows one logical row.
Manual: kill a real Claude session in a worktree, `claude-monitor restore`, confirm it opens in that worktree with the conversation intact (`claude --resume` resumes), and `tmux ls` shows the `agents` session.

## S4: boot flow (FR-032 to FR-034)

Banner: `boot_check::banner` asserts `boot-check --banner` prints the one-line tmux message once and then nothing (marker cleared).

Auto: `cargo test boot_check::` asserts that with interrupted sessions the command emits one notification request (fake notifier), starts no process, and writes the banner marker; with none, it emits nothing.
Manual: log out and back in; the notification appears; `restore` shows all selected; deselect one; confirm it stays `interrupted` and is not started.

## S5: progress (US4; FR-015, FR-015a, FR-016, SC-006)

Auto: `cargo test progress::` runs the three parsers on fixtures (a spec-kit `tasks.md` with 10 tasks, 4 done; a plain checklist; a recorded todo-tool payload) and asserts `4 of 10`, the current item, and the source label. A session with two candidate files and no match yields a "pick one" result and no figure; after choosing, the binding persists across reconcile and process restart.
Manual: open this feature's `tasks.md` session after `/speckit-tasks`; the overview shows the correct count and names `specs/008-ai-control-centre/tasks.md`.

## S6: organise (US5; FR-018, FR-019)

Auto: `cargo test organise::` groups three sessions into a project, adds a note, dismisses one, asserts the default query hides it and `--include-dismissed` returns it with history intact. `organise::finished_visible` ends a session cleanly and asserts it stays in the default query (finished group), is not hidden after any age, is not pre-selected by `restore`, and respawns through the same planner as an interrupted one, then reappears in the active group.

`organise::done_sections` finishes two sessions (one in project P, one in none), marks both done, and asserts: each is in exactly one group; P's Done section lists only P's session; the global Done section lists the other; `done` on a running or interrupted session is rejected; `undone` returns it to Finished; respawning a done session clears `done_at` and puts the resumed work in Active; no session enters Done without a `user`-authored event.

## S7: web view (FR-030, FR-031, SC-011)

Auto: `cargo test --features web web::` asserts the server binds only to loopback, rejects a request with a foreign `Host` header, rejects a missing or wrong token, sets no CORS headers, and that a state change written through the core appears on the SSE stream within 10 s. A parity test asserts every action in S1 to S6 exists as both a TUI command and a web route.
Manual: `claude-monitor serve`, open the printed URL, compare with the TUI.

## S8: cortexiphan export (US6; FR-023 to FR-029, SC-009, SC-010)

Auto: `cargo test export::` builds a project with 20 steps and linked sessions, exports twice, asserts the two outputs are byte-identical, validates against `contracts/cortexiphan-export.schema.json`, and asserts each record has `external.system == "ai-control-centre"` and an `author`. A conflict test sets different statuses on the two sides of a link and asserts the conflict is reported, not resolved. `SC-010`: the whole suite S1 to S6 is run again with the cortexiphan CLI absent from `PATH`.
Cross-repo check (when cortexiphan gains ingest): import the file twice into a scratch cortexiphan; node count identical after the second run.

## S9: Copilot (FR-004, SC-004)

Auto: Copilot fixtures produce the same events as Claude ones; passive discovery over a fixture `COPILOT_HOME` lists sessions as `unknown` and resume builds `copilot --resume <uuid>`.
Manual (spike R3): real Copilot session with the hooks file installed reports `working`, `needs_permission`, `idle`.

## Done when

S1 to S9 pass, `nix flake check` is green, and the manual lines have been run once and their outcomes recorded in the pull request.
