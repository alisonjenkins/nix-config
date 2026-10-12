# Implementation Plan: AI Control Centre

**Branch**: `008-ai-control-centre` | **Date**: 2026-10-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/008-ai-control-centre/spec.md`

## Summary

Turn `claude-monitor` (today: a hook-fed, tmux-aware live list whose state lives in `$XDG_RUNTIME_DIR` and vanishes at reboot) into a durable control centre. The core move is a **SQLite store** that every hook writes to and every view reads, replacing the per-session runtime JSON files. On top of that store:

- **Liveness**: a session is running only if its process is alive and its boot id matches; anything else with no clean `SessionEnd` is `interrupted` (FR-005, FR-008).
- **Respawn**: a planner turns a stored session into "start this launcher in this directory inside tmux" and refuses wrong or missing directories (FR-009 to FR-014).
- **Agent adapters**: one Rust trait with two real implementations, Claude Code and Copilot CLI, each owning hook parsing, resume command, transcript locator and passive discovery (FR-004).
- **Progress**: parsers for the agent todo list, spec-kit `tasks.md` and generic Markdown checklists, with a stored per-session source binding (FR-015, FR-015a).
- **One program, three front ends**: a single `claude-monitor` binary that is both the interactive TUI (no subcommand) and a scriptable command line tool (subcommands with `--json` and exit codes), plus a loopback-only web UI started by `serve`. All three are thin consumers of one **library crate** that holds every behaviour; the binary only parses arguments, calls the library and maps its result to an exit code (FR-030, FR-031, FR-035).
- **Boot flow**: a login-time user unit that notifies and opens a restore list with per-session opt-out (FR-032 to FR-034).
- **Cortexiphan**: every mutation is an attributed event; a JSON Lines export maps onto cortexiphan's `Project` / `Task` / `ExternalRef` / `Author` types, idempotent by `(system, id)` (FR-023 to FR-029).

The code is built in the **`claude-monitor` repository** (one Cargo package: a library plus a thin binary), not in this one. This repository carries only this spec/plan, the flake input bump and the Home Manager wiring (units, tmux binding, hook registration). That split is the one load-bearing decision to confirm; see Complexity Tracking.

## Technical Context

**Language/Version**: Rust, edition 2021 (matches `claude-monitor` v0.2.0; cortexiphan is edition 2024, so crates stay edition-agnostic and migrate at merge)

**Primary Dependencies**: `rusqlite` (bundled SQLite, WAL), `serde`/`serde_json`, `clap` 4, `ratatui` 0.30 + `crossterm` 0.29 (existing), `notify` 8 (existing), `notify-rust`/`mac-notification-sys` (existing), `axum` + `tokio` (behind the `web` feature, used only inside `web::serve`), `uuid`, `time` or `chrono` (existing), `thiserror` for library errors. The library exposes cargo features `tui` and `web` (both on by default for the binary); with `default-features = false` it is the runtime-agnostic core that cortexiphan can depend on at merge (cortexiphan rule: libraries stay runtime-agnostic).

**Storage**: SQLite file at `$XDG_STATE_HOME/ai-control-centre/state.db` (fallback `~/.local/state`; macOS `~/Library/Application Support`), mode 0600, WAL, `busy_timeout`. Append-only `events` table is the attributed change log; projection tables serve the views. Existing runtime JSON files are read once for migration, then ignored.

**Testing**: tests target the library, not the binary. Commands are plain functions `fn run(cmd: Command, env: &Env) -> Result<Output, Error>` taking injected clock, boot-id, process, tmux, notifier and filesystem providers, so every CLI behaviour (including exit-code mapping and `--json` shape) is a unit or integration test with no process spawn. The TUI is split into pure `update(state, key) -> state` and `view(state) -> frame` functions, tested with ratatui's `TestBackend`. The binary has only a few `assert_cmd` smoke tests (argument parsing, exit codes, `hook` always exits 0). Also: `cargo test` with hook-payload fixtures per agent; property tests for the progress parsers and the state machine; an integration test that runs a real `tmux` server on a private socket inside the Nix check sandbox for respawn; a fake clock and fake `boot_id`/pid providers for reboot and kill scenarios. Gate: `nix flake check` (existing: test, clippy `-D warnings`, fmt, hm-module eval, cargo-deny).

**Target Platform**: Linux (NixOS, systemd user units) and macOS (launchd agent), as `claude-monitor` supports today. Boot-id source differs per OS (see research R5).

**Project Type**: single Cargo package: library crate (`claude_monitor`) + one binary (`claude-monitor`) that is both TUI and CLI and consumes the library. Plus a Home Manager module (extends the existing `programs.claude-monitor`).

**Event model**: event-driven wherever the OS or the agents can tell us (research D12): hooks, one append-only `events` table as the change feed, `notify` file watches, `pidfd`/`kqueue` process-exit notifications, tmux `set-hook` for pane exits, and the login unit for boot. The library exposes `EventSource` and `ChangeFeed` abstractions so tests inject events instead of sleeping. Only a 60 s safety-net reconcile (while a viewer is open) and the on-view pull of cortexiphan status remain time- or request-driven.

**Performance Goals**: hook invocation < 50 ms p95 and never blocks the agent; overview of 500 historical sessions < 2 s (SC-007); state staleness ≤ 10 s live, killed session shown not-running ≤ 30 s (SC-005); cross-view propagation ≤ 10 s (SC-011).

**Constraints**: hooks always exit 0 and write nothing to stdout (existing behaviour, keep); no network egress of session content (FR-020), including the optional model summary, which MUST target a loopback endpoint; web bound to loopback with Host check and bearer token (FR-031); all paths and launcher commands configurable, tools resolved from Nix or probed (constitution, Operational Constraints); times ISO 8601 UTC.

**Scale/Scope**: one user, one machine, tens of live sessions, hundreds to low thousands of historical sessions; ≤ ~50 projects.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design: no change.*

| Principle | Status | How the plan meets it |
|---|---|---|
| I. Atomic, revertable history | Pass | Delivery is sliced (see Phasing) so each slice builds on its own and reverts alone; fixups, no squash; no AI attribution. Test-first commits mark new tests `#[ignore = "T0nn"]` so every commit builds and passes, and the implementation commit removes the ignore. |
| II. Test first, evidence before done | Pass | Every slice starts with a failing test (fixtures, fake clock/boot-id, private tmux). Done = command output, per `quickstart.md`. Untestable glue named: notification delivery and real-agent resume are covered by the manual steps in `quickstart.md`, not CI. |
| III. IaC, live changes by consent | Pass | Units, hook registration and tmux binding are Home Manager options in this repo; nothing mutates a live host. The tool itself writes only to its own state dir and to tmux on an explicit respawn action. |
| IV. Errors carry context | Pass | `claude-monitor` already denies `unwrap`/`expect`/`panic`/indexing in clippy; extended to new crates. Hooks swallow errors by design (must never break the agent) but log operation + inputs to a rotating file in the state dir. This is the one deliberate "don't propagate" and is stated in code and ADR. |
| V. Right altitude, single source of truth | Pass with note | Trait only where two implementations exist today (Claude, Copilot). Session identity, boot id and cwd live in one place (the store). Status vocabulary is defined once in `acc-core` and mapped to cortexiphan in one export module. |
| VI. Record the why | Required | ADRs 0040 (store, liveness, event feed) and 0041 (code home / cortexiphan coupling) are drafted early as Proposed and set to Accepted, together with the topic doc `docs/ai-control-centre.md`, in the nix-config wiring PR (tasks T122 to T125). claude-monitor PRs link to them. |
| VII. Fork patches generated | N/A | No fork or generated patch involved. |
| Operational constraints | Pass | No hard-coded machine paths; tmux probed with `command -v`; launcher template configurable; secrets none (web token is a local 0600 file, not a secret in the store). |

## Project Structure

### Documentation (this feature)

```text
specs/008-ai-control-centre/
├── plan.md              # This file
├── research.md          # Phase 0: decisions, verified facts, open spikes
├── data-model.md        # Phase 1: tables, state machine, mappings
├── quickstart.md        # Phase 1: validation scenarios per user story
├── contracts/
│   ├── cli.md                    # claude-monitor subcommands
│   ├── hook-payloads.md          # Claude + Copilot payloads -> events
│   ├── agent-kind.md             # how to add an agent kind (FR-004)
│   ├── web-api.md                # loopback HTTP surface
│   └── cortexiphan-export.md     # JSON Lines export, mapping, idempotency
└── tasks.md             # Phase 2 (/speckit-tasks, not created here)
```

### Source Code

Code lives in the `claude-monitor` repository (path `/home/ali/git/personal/claude-monitor`, upstream `github:alisonjenkins/claude-monitor`):

```text
claude-monitor/
├── Cargo.toml                    # one package: [lib] claude_monitor + [[bin]] claude-monitor; features tui, web
├── src/
│   ├── main.rs                   # thin: parse args -> lib::cli::run -> exit code (existing main shrinks to this)
│   ├── lib.rs                    # public API; re-exports
│   ├── model.rs                  # Session, Project, Step, Note, Link, Attribution, State
│   ├── store/                    # sqlite schema, migrations, events, queries
│   ├── liveness.rs               # pid+starttime, boot_id, tmux pane probes (behind traits)
│   ├── agents/                   # trait AgentKind; claude.rs; copilot.rs
│   ├── progress/                 # todo.rs, speckit.rs, checklist.rs, binding.rs
│   ├── respawn.rs                # planner + executor (tmux behind a trait)
│   ├── summary.rs                # verbatim extraction + on-demand local model client
│   ├── export/cortexiphan.rs
│   ├── hook.rs                   # ingest (today's commands/hook_cmd.rs moves here)
│   ├── cli/                      # clap definitions, Command enum, run(), Output, exit-code mapping, --json
│   ├── tui/    (feature tui)     # state, update, view (today's ui.rs/dashboard.rs/watcher.rs move here)
│   └── web/    (feature web)     # axum + tokio; server-rendered HTML + SSE; the only async code
├── tests/                        # fixtures/, library integration (private tmux), reboot/kill sims, bin smoke tests
├── nix/hm-module.nix             # + Copilot hooks, serve unit, boot-check unit, options
└── docs/adr/                     # claude-monitor's own ADRs, if the repo adopts them

nix-config (this repo):
├── specs/008-ai-control-centre/  # this spec
├── docs/adr/0040-*.md, 0041-*.md
├── flake.nix / flake.lock        # claude-monitor input bump
├── home/programs/claude-code/default.nix   # enable new module options
└── home/programs/tmux/tmux.conf.nix        # prefix+A / restore binding
```

**Structure Decision**: library + thin binary in the existing `claude-monitor` repo so FR-022 (nothing lost) is satisfied by evolution, not rewrite, and so tests and re-use go through the library (owner's direction). One package, not a workspace: the `tui` and `web` cargo features keep `ratatui` and `tokio`/`axum` out of any consumer that does not want them, including the cortexiphan merge, and `tokio` is only started inside `web::serve`, so `hook` stays fast. Rule: nothing but argument parsing lives in `main.rs`. Cortexiphan-specific code is confined to `export/cortexiphan.rs` so a changing cortexiphan model touches one file (spec edge case).

## Phasing (each slice builds and reverts alone; maps to future tasks)

0. **Library/binary split (refactor only, no behaviour change)**: move today's `session`, `hook_cmd`, `tmux`, `watcher`, `ui` and `dashboard` code into the `claude_monitor` library behind `tui` and `cli` modules; `main.rs` shrinks to argument parsing plus `cli::run`. Existing tests move with the code and keep passing; `nix flake check` stays green. This is its own commit so it reverts alone.
The slices below are `tasks.md` phases. Every task is one commit that does one granular thing; test tasks land first with `#[ignore]`.

1. **Setup (tasks T001 to T006)**: baseline, draft ADRs, and the spikes whose results shape the design (R1 resume and fork behaviour, R2 hook payloads, R8 change-feed latency).
2. **Foundational (T007 to T027)**: library/binary split above (slice 0), SQLite store, `events` table as change feed, provider traits, `Command` enum with the CLI conformance test, legacy-file migration, `AgentKind` with the Claude parser, `hook` writing the store, `ChangeFeed`. No behaviour change for the user.
3. **Overview (US1, T028 to T045)**: queries, `list`/`show`, rebuilt TUI; Copilot spike (R3, R6) with a decision gate, Copilot parser, passive discovery and hooks file; Claude passive discovery; the third-agent-kind test.
4. **Durability (US2, T046 to T061)**: pid/start-time/boot-id capture, `reconcile` and reconcile-on-open, process-exit watchers (`pidfd`/`kqueue`), tmux `set-hook` for pane exits, safety-net reconcile, optional `watch`; `interrupted` vs `finished`, survives kill and reboot.
5. **Respawn and boot flow (US3, T062 to T082)**: planner, alternatives (`--recreate-worktree`, `--fresh --in`), tmux executor, lineage and fork handling, `respawn`/`restore`, `boot-check` with `--banner`, login units (systemd, launchd), tmux hook, launcher options, nix-config wiring.
6. **Progress and summaries (US4, T083 to T093)**: three parsers, source binding with picker, file watches, verbatim summaries, on-demand loopback-only model summary.
7. **Cortexiphan export and links (US6, T094 to T103)**: JSON Lines export, schema, `link`, `links check`, conflict display.
8. **Organise (US5, T104 to T112)**: projects, notes, parked/dismissed, done sections (global and per project), filters, finished-group collapse, scale test.
9. **Web view (T113 to T121)**: design pass, loopback server, token, SSE, parity with the CLI, browser check.
10. **Polish (T122 to T131)**: flake bump, topic doc, ADRs accepted, no-egress and cortexiphan-absence guards, end-to-end quickstart, analysis.

The MVP the user feels is slices 1 to 5 for Claude Code (a durable overview that survives reboots and respawns sessions). Copilot is gated early (task T036) by its spike because the Copilot capability is the main unverified claim in the spec.

## Complexity Tracking

| Deviation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| Spec and wiring live in nix-config; code lives in `claude-monitor` (constitution scope is "this repository") | FR-022 requires building on `claude-monitor`, which is its own repo, flake input and release train; the user already ships it that way | A copy of the tool inside nix-config would fork it and break its CI/release flow. A third new repo would discard its tested hook and TUI code. Owner to confirm; recorded in ADR 0041. |
| Hooks swallow errors (Principle IV) | A failing hook must never wedge or slow the agent | Propagating would make the agent report hook failures on every tool call. Errors are logged with operation and inputs instead. |
| SQLite instead of extending JSON files | Needs history, queries over hundreds of rows, atomic multi-table writes, and an attributed change log | Per-session JSON files cannot give durable history, filters or SC-007 without reimplementing a database. |
