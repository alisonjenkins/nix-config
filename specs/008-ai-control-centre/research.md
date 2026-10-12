# Research: AI Control Centre

Findings from reading `claude-monitor`, cortexiphan and Copilot CLI 1.0.93 (2026-10-12). "Verified" = seen on this machine or in the repo; "Documented" = from GitHub docs, not exercised; "Unverified" = needs the spike named in the last column.

## Decisions

### D1. Durable store: SQLite, hooks write to it directly

- **Decision**: One SQLite database (WAL, `busy_timeout` ~2 s) in the XDG state dir. The `hook` subcommand opens it, applies one short transaction, exits 0 regardless of outcome. No daemon sits between hook and store.
- **Rationale**: Today's state is `$XDG_RUNTIME_DIR/claude-monitor/<id>.json` (verified: `src/session.rs`), which is wiped at reboot, the exact failure the spec exists to fix. SQLite gives atomic multi-row updates, indexed queries for SC-007 and a natural append-only event log for attribution (FR-024), with no service to keep alive.
- **Alternatives**: durable JSON files per session (no queries, no history); a daemon owning the store (extra moving part that can be down while hooks fire); Postgres as cortexiphan does (needs a server; breaks "works without anything else", FR-027).

### D2. Liveness = process identity + boot id, not just pid

- **Decision**: On `SessionStart` (and refreshed on later hooks) the hook records the agent PID (its parent), that PID's start time from `/proc/<pid>/stat` field 22, and the machine boot id (`/proc/sys/kernel/random/boot_id`, verified present). A session is *running* iff the PID exists with the same start time and the boot id matches. A session with no clean `SessionEnd` that is not running is *interrupted*. A different boot id marks every non-ended session interrupted immediately, with no process probing.
- **Rationale**: Pid reuse after hours or a reboot would otherwise resurrect dead sessions. Matches FR-008 ("detect without the user reporting") and the "reboot is interrupted, never finished" edge case. Existing `prune_stale_panes` (tmux pane gone) stays as a secondary signal.
- **Alternatives**: tmux pane existence only (breaks for sessions outside tmux; a pane id is reused after a tmux server restart); heartbeat timestamps only (30 s detection forces constant writes; cannot tell kill from idle).
- **Open**: macOS has no `/proc`: use `sysctl kern.boottime` for boot id and `proc_pidinfo`/`ps -o lstart=` for start time (R5).

### D3. Clean end vs interrupted

- **Decision**: `SessionEnd` observed → `finished` (clean end), regardless of whether the task completed; the user can still set *parked*, and a finished session stays visible and respawnable (FR-019a) because a clean exit does not mean the work was done. No `SessionEnd` and not running → `interrupted`. `/clear` (a `SessionEnd` with reason `clear`) starts a new session id in the same pane and is recorded as a lineage step, not as work finishing. Reason codes are stored raw so this can be tightened without migration.
- **Rationale**: The spec's "finished" is a user-meaning (task done) the system cannot know; the closest knowable proxy is a clean exit. The costly mistake is the opposite one (hiding interrupted work), which this rule avoids.
- **Open**: confirm the exact `SessionEnd.reason` vocabulary on 2.1.293 (R2).

### D4. Respawn: tmux window per session, launcher from config

- **Decision**: Respawn runs a configurable launcher in `tmux new-window -c <cwd>` inside a configurable tmux session (default `agents`), creating the tmux server/session if absent. Default launchers: Claude `claude --resume <session_id>`, Copilot `copilot --resume <session_id>`. The user's real `claude` is a wrapper; the template is the single place that knows that.
- **Rationale**: Claude Code resume is keyed to the working directory (verified layout: `~/.claude/projects/<cwd-with-slashes-as-dashes>/<session-id>.jsonl` plus `sessions-index.json`), so the directory must be the recorded worktree. Before launching, the planner checks the directory exists and, for Claude, that the transcript file exists under the encoded path; either missing is the refusal in FR-012. Already-running check (FR-013) reads liveness, then the lineage head.
- **Lineage link**: the respawn request stores the new pane id; the next `SessionStart` from that pane with `source=resume` attaches to the original record as `resumed_from`. No duplicate row appears (FR-011). Whether Claude keeps the same session id on resume or mints a new one is Unverified; the model supports both (R1).
- **Alternatives**: spawn into the user's current terminal (cannot respawn many at once); a terminal-emulator specific launch (not portable across Linux/macOS).

### D5. Boot flow: user unit + notification, restore list is a TUI mode

- **Decision**: A systemd user unit (Linux) / launchd agent (macOS), installed by the Home Manager module, runs `claude-monitor boot-check` at login. It reconciles the store, and if there are interrupted sessions it sends a desktop notification (libs already in `claude-monitor`) and leaves a marker so the next terminal or tmux client shows a banner. The notification and banner lead to `claude-monitor restore`, a TUI list with checkboxes (all selected, deselect to opt out), Enter to respawn the selected. Nothing starts without that action (FR-034).
- **Rationale**: Reuses the existing notification path; no new UI technology; the same list is also in the web view.
- **Alternatives**: a tmux-server start hook (misses users who have not started tmux); auto-respawn (explicitly out of scope).

### D6. Agents: one trait, two implementations

- **Decision**: `trait AgentKind` in the library crate (`claude_monitor::agents`): `id()`, `parse_hook(payload) -> Vec<Event>`, `resume_command(session) -> Launch`, `transcript_locator(session) -> Option<PathBuf>`, `passive_discover() -> Vec<SessionStub>`. Implementations: Claude, Copilot. Documented in `contracts/agent-kind.md` (FR-004, SC-008).
- **Rationale**: Principle V allows an abstraction on the second real use; this is the second.

### D7. Copilot: hooks for state, files for durability, resume verified

| Need | Finding | Status |
|---|---|---|
| Resume | `copilot --resume <id\|prefix\|name>`; `--continue`; `--session-id`; session ids are UUIDs; cwd is not required by the CLI | Verified (`--help`, 1.0.93); behaviour from a different cwd Unverified |
| Storage | `~/.copilot/session-state/<uuid>/{workspace.yaml,events.jsonl,...}`; `COPILOT_HOME` relocates. `workspace.yaml` has id, cwd, git_root, repository, branch, name, created_at, updated_at | Verified (listing only) |
| First prompt | `events.jsonl` `user.message` | Verified (type names seen) |
| Hooks | `sessionStart`, `sessionEnd`, `userPromptSubmitted`, `preToolUse`, `postToolUse`, `permissionRequest`, `notification`, `agentStop`, ... in `~/.copilot/hooks/*.json` (`version: 1`, handlers with `bash`, `cwd`, `env`, `timeoutSec`) | Documented |
| Waiting state | no dedicated event; `notification` with `permission_prompt` or `elicitation_dialog` | Documented |
| Idle/stop | `agentStop`, `notification` `agent_idle`/`agent_completed` | Documented |
| PID | not in payload; the hook script can record its parent PID | Unverified (R3) |
| Todo/plan | not found | Unverified |

- **Decision**: Copilot is supported through (a) a hooks file written by the Home Manager module that calls `claude-monitor hook --agent copilot`, and (b) passive discovery of `session-state/*/workspace.yaml` so sessions are durable and listed even when hooks did not run. Sessions found only passively are state `unknown` until a hook arrives (matches the spec's "state unknown" edge case). So "fully supported" holds for durability, listing and resume today; state accuracy depends on the hook install, which the module provides.
- **Risk**: Copilot's docs also list `.claude/settings.json` as a hook source. Our Claude hooks live in the user-level `~/.claude/settings.json`, which is not documented as read by Copilot, so no double registration is expected; confirm in the spike (R6).

### D8. Progress sources and binding

- **Decision**: three parsers behind one `ProgressSource` result `{source_label, items[{text,status}]}`:
  1. **Agent todo list**: from the `PostToolUse` hook for the todo tool (`tool_input.todos[]` with `content`/`status`), stored as the session's latest list. For Copilot, none is found yet, so this source is absent for it.
  2. **Spec-kit `tasks.md`**: lines `- [ ] T### ...` / `- [x] T### ...`, grouped by phase headings.
  3. **Generic Markdown checklist**: any `- [ ]`/`- [x]` lines in a chosen file (`PENDING.md`, `todo.md`, other).
- **Selection (FR-015a)**: candidate files are those in the session repository root and `specs/*/`. A spec-kit directory is auto-bound when it matches the branch name prefix or `.specify/feature.json` (both exist in this repo and cortexiphan) or when only one candidate exists. Otherwise the candidates are listed and the user picks; the choice is stored in `progress_binding` keyed by session/project. Figures always show the source label.
- **Rationale**: the user explicitly chose all three sources; a wrong guess would present false progress, which FR-016 forbids.

### D9. Summaries: verbatim by default, local model on demand

- **Decision**: Task description = the first `UserPromptSubmit` prompt (truncated for display, full text stored). "Where we left off" = latest assistant message, taken from the hook payload when present, else the tail of the transcript JSONL (path from `transcript_path`). On-demand summary calls an OpenAI-compatible endpoint configured in the module; the client **rejects non-loopback hosts**, enforcing FR-020 in code. Output is stored once in `summaries` with `model` and a `model_written` flag; verbatim text is never replaced.
- **Rationale**: the user chose this (clarification 5); this machine already runs local llama-server profiles for delegation.
- **Open**: whether the `Stop` payload carries the last assistant message on 2.1.293 or the transcript tail is required (R2).

### D10. Web view: loopback server, token, server-rendered

- **Decision**: `claude-monitor serve` runs an axum server on `127.0.0.1:<port>`; rejects requests whose `Host` is not the loopback name/port (DNS rebinding), requires a bearer token (random, in a 0600 file in the state dir, passed once in the opening URL then set as an `HttpOnly; SameSite=Strict` cookie), sends no CORS headers. Pages are server-rendered HTML, updates pushed over Server-Sent Events from the change feed in D12 (no polling loop). No JS build step.
- **Rationale**: FR-031 and "session content never leaves the machine". Server-rendered keeps parity with the TUI cheap (same core queries) and avoids a second front-end stack before the cortexiphan merge; cortexiphan's own web UI (Dioxus/WASM) replaces it then.
- **Alternatives**: Unix socket (browsers cannot use it); WASM front-end now (pays the cost twice); no auth beyond loopback (other local users and web pages can reach it).

### D11. Cortexiphan: loose coupling, JSON Lines export, mapping in one module

- **Facts (verified in `/home/ali/git/personal/cortexiphan`)**: `NodeKind` is `#[non_exhaustive]` with `Project`, `Task`, `Custom { kind, fields }`. `ProjectFields { status: Active|Paused|Done|Archived, repos: Vec<RepoRef{name,uri,clones[{machine,path}]}> }`. `TaskStatus` = `Todo|Doing|Done|Blocked|Custom`. `Author` = `User|Llm{model}|Connector{name}`. `ExternalRef{system,id,url}` is the dedupe key for connectors (`(system,id)` index in `ExpandConnectorNode`). The CLI creates only notes and tasks; MCP `node_create` rejects `project`; there is **no file import**; local CLI mode is in-memory and persists nothing.
- **Decision**: export JSON Lines with one record per project, step, session and link, each carrying `external = {system:"ai-control-centre", id:<uuid>}` and an `author`. Statuses map as in `data-model.md`. Sessions export as `Custom{kind:"session"}`. The ingest side is cortexiphan work and is out of scope here; this feature delivers a documented, versioned, schema-checked format and a test that re-export is byte-stable.
- **Rationale**: cortexiphan is Phase 0 and cannot be a dependency (FR-027); the connector pattern already defines idempotent upsert on `(system,id)`, so matching it makes "re-import creates zero duplicates" (SC-009) a property of the format.
- **Reading the linked side (US6 scenario 2)**: best-effort shell-out to `cortexiphan --json node get`, only when `CORTEXIPHAN_SERVER`/token are set; otherwise the link shows "other side unavailable". Cortexiphan `NodeId` is a per-shard `u64`; stored as text with its doc id.

### D12. Event-driven by default: one change feed, OS notifications for everything external

- **Decision**: nothing in the system sleeps on a timer to find out something happened, except one safety net (below). Every source of change is an event, and all of them funnel into the same feed.

| Thing that changes | Today's plan | Event source |
|---|---|---|
| Agent state | hooks | Hook invocation (already push). Writes a row to `events` in the same transaction as the projection update. |
| Store changed (for viewers in other processes) | would have been a `data_version` poll | **Change feed**: viewers watch the state dir with `notify` (inotify on Linux, FSEvents on macOS; `notify` 8 is already a dependency and `claude-monitor` already uses it for its dashboard). A write to `state.db-wal` fires the watcher; debounce ~50 ms; then read `events` rows with `seq > last_seen` (cursor kept in memory). The rows say exactly what changed, so the TUI and SSE push only that. |
| Agent process died (kill, crash) | periodic reconcile | **Process-exit notification**: Linux `pidfd_open` + `poll` per running session (watch registered when the session is seen); macOS `kqueue` `EVFILT_PROC`/`NOTE_EXIT`. Fires at the moment of death; reconcile for that one session runs immediately (SC-005 becomes "immediately while a viewer or watcher is up", 30 s kept as the worst case). The pid_start check from D2 still guards pid reuse. |
| tmux pane closed | periodic `list-panes` | tmux control hooks: `tmux set-hook -g pane-exited` / `pane-died` / `window-unlinked` run `claude-monitor reconcile --pane %N`. Installed by the HM module, so no viewer needs to be open. |
| Reboot | boot_id compare | `boot-check` runs from the login user unit (systemd / launchd), an OS-triggered event; plus a boot-id compare on every reconcile. |
| Plan source changed (`tasks.md`, checklist) | re-read on view | `notify` watch on each bound file; re-parse that one file on change and write a progress event. Agent todo lists are already pushed via hooks. |
| Copilot sessions with no hooks | rescan | `notify` watch on `~/.copilot/session-state/` (new directory = new session; `events.jsonl` append = activity). |
| Claude left-off text | transcript tail | Read only on the `Stop`/`agentStop` hook event, never on a schedule. |
| Web clients | SSE | Server push from the change feed; the browser holds one open stream, no client polling. |
| Respawn lineage link | match later | The next `SessionStart` hook from the recorded pane (event), not a poll for the new process. |
| Desktop notifications | on hook transitions | Same: raised by the hook process on transition into needs_permission/idle (already event-driven in `claude-monitor`). |

- **Where who watches**: the TUI and `serve` each run the watchers while open. With neither open, hooks, tmux hooks and the login unit still keep the store correct; only "tell me instantly a process died" needs a watcher, and a viewer being open is when anyone is looking. An optional `claude-monitor watch` user service (off by default) runs the same watchers headless for desktop notifications; it is a thin loop over the library's `Watcher`.
- **Viewers reconcile on open**: the TUI, `serve` and `list`/`show` run one reconcile before the first render, so a death nobody was watching is corrected the next time anyone looks (task T044).
- **Remaining polling, stated honestly**: (1) a slow safety-net reconcile (default 60 s, only while a viewer is open) because inotify can drop events when queues overflow and macOS FSEvents coalesces; (2) the cortexiphan linked-side status, which is a pull from a remote with no push channel, done on view and on `links check`, never on a timer; (3) the on-demand model summary is a request/response call.
- **Design consequence**: the library exposes `trait EventSource { fn next(&mut self) -> Event }` implementations (fs watcher, pidfd/kqueue, tmux hook invocation) and a `ChangeFeed` that merges them; tests inject a fake source and a fake clock, so no test sleeps or polls (constitution II; keeps CI fast and non-flaky).
- **Rationale**: lower latency and idle cost, no wasted wakeups on a laptop, and it matches the append-only event log already planned for attribution: the same `events.seq` is the cursor for views, SSE and the cortexiphan export.
- **Alternatives**: a long-running daemon owning everything (one more thing to be down; rejected in D1); a Unix datagram "bus" socket that writers ping after commit (precise, but listeners must exist or writers must handle absence; the fs watch on the DB achieves the same without a protocol and works when no listener is up); pure timers (what the plan had).
- **Open (R8)**: confirm inotify reliably fires on `-wal` appends under WAL mode and measure latency from commit to watcher callback on this machine; confirm macOS FSEvents latency is acceptable (it coalesces, typically < 1 s).

## Open spikes (ordered by risk to the spec)

| # | Question | Why it matters | Method | Blocks |
|---|---|---|---|---|
| R3 | Can Copilot hooks record a PID and report state on this machine? Does resume work from another cwd? | Decides whether "Copilot fully supported" (clarification 3) holds, or FR-014 applies | Install a throwaway hooks file under a temporary `COPILOT_HOME`, run a trivial session, inspect payloads and `$PPID` | Slice 5 |
| R1 | On `claude --resume <id>` does the session id stay the same or change, and can it be resumed from another cwd? | Lineage linking and the cwd rule | Run twice in a scratch dir; compare `~/.claude/projects/*` | Slice 3 |
| R2 | Exact hook payloads on Claude Code 2.1.293: `SessionEnd.reason`, `SessionStart.source`, todo tool name and `tool_input`, `Stop` last message | State machine, progress source 1, summaries | Log raw stdin with a throwaway hook for one session | Slices 1, 2, 6 |
| R6 | Does Copilot also run hooks from `~/.claude/settings.json`? | Double events | Run Copilot with the Claude monitor hook present and count events | Slice 5 |
| R5 | macOS boot id and process start time | Liveness parity | `sysctl kern.boottime`; `ps -o lstart= -p` | Slice 2 (macOS) |
| R7 | Does a private `tmux` server run inside the Nix check sandbox? | Respawn integration test in CI | Try in a `runCommand` check | Slice 3 |
| R8 | Does inotify fire on SQLite WAL appends reliably, with what latency; FSEvents on macOS? | The whole change feed (D12) | Commit in one process, time the watcher callback in another, 1000 iterations | Slice 1 |
| R9 | Do tmux `set-hook` `pane-exited`/`pane-died` fire for panes running `claude`/`copilot` on tmux's current version, and can they run a command with the pane id? | Instant pane-gone detection | Set hooks on a private tmux server, kill panes | Slice 2 |

R1, R2, R6 and R3 are each under 30 minutes and are scheduled as the first tasks of their slices, as characterisation tests that stay in the repo as fixtures.
