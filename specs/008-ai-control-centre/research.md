# Research: AI Control Centre

Findings from reading `claude-monitor`, cortexiphan and Copilot CLI 1.0.93 (2026-10-12). "Verified" = seen on this machine or in the repo; "Documented" = from GitHub docs, not exercised; "Unverified" = needs the spike named in the last column.

## Baseline

T001, 2026-10-12T10:12Z: `nix flake check` of claude-monitor `main` (6ab3433) exits 0 in about 4 s with a warm cache. Checks: `package`, `cargo-test`, `clippy`, `fmt`, `hm-module`. Only `x86_64-linux` is evaluated by default (`aarch64-linux`, `aarch64-darwin` and `x86_64-darwin` are omitted). Nix warns that `homeManagerModules` is an unknown flake output; harmless.

## Evidence from spikes (2026-10-12)

All OBSERVED on this machine unless marked. Claude Code 2.1.293, kernel 7.2.8-cachyos-lto. Redacted fixtures (13 files) are committed in the claude-monitor repo under `tests/fixtures/claude/`.

### R8: change feed

- Test: `tests/spikes/wal_notify.rs` (ignored test), `/tmp` tmpfs only. ext4, btrfs and NFS are untested.
- Three runs of 1000 commits 2 ms apart plus a 50-commit burst: zero missed commits. About 98% of events land on `state.db-wal`, a few on `state.db` and `state.db-shm`.
- Events coalesce (0.4-1.5 per commit in bursts, 1.04-1.27 steady). Latency is about 0.1-3 ms with one 13.6 ms outlier. The final `max(id)` was always observable after the last event.
- A pure trailing 50 ms debounce STARVES under continuous writes (first fire after 1.1-3.3 s). A start-anchored 50 ms window gave p50 about 25 ms, p99 about 50 ms.
- Verdict: a `notify` watch on the state dir is a reliable wake-up, not a payload. Re-query by `events.seq` on each wake, use a start-anchored throttle window, and keep the 60 s safety-net reconcile (other filesystems, inotify queue overflow, `-wal` deletion on checkpoint).

### R1: resume and fork

- Transcript path: `~/.claude/projects/` plus the absolute cwd with every non-alphanumeric character replaced by `-` (lossy).
- `--resume <id>` keeps the same session id and appends to the same transcript file. From a different cwd it works silently, with no error; the process runs in the new cwd (tools, CLAUDE.md lookup, git branch, per-line `cwd`), while the transcript stays in the original project dir.
- `--continue` is cwd-scoped and silently starts a fresh session when none exists there. Never use it for respawn.
- `--fork-session` creates a new session id and a new transcript in the same project dir with copied history. The original is untouched. No parent link is written (no `parentSessionId` or `forkedFrom`); the only trace is shared message uuids (35 of 42 uuid-bearing lines). A tool must record parent to child itself when it launches a fork, or compare uuids.
- `sessions-index.json` is STALE (not written by newer versions; 39 entries against 80 transcripts in one project). Scan the `.jsonl` files instead.
- NEW: `~/.claude/sessions/<pid>.json` registry, see R10 in the spike table and D2.
- Not tested: the invalid-id failure mode; `_` and unicode in the cwd encoding.

### R2: hook payloads

Five `claude -p` runs and one interactive tmux session. The full shapes are in `contracts/hook-payloads.md`. Points that change decisions:

- Every payload is one JSON object on stdin with `session_id`, `transcript_path`, `cwd`, `hook_event_name`.
- `SessionStart.source` is `startup`, `resume` (same session id) or `clear` (new session id). `compact` was not tried.
- `Stop` carries `last_assistant_message`, once per turn, so the transcript tail is not needed (D9).
- `PermissionRequest` has no `tool_use_id` and fires in `-p` mode too. `Notification` fires in interactive sessions only.
- `SessionEnd.reason` seen: `other`, `clear`, `prompt_input_exit` (D3).
- This Claude Code has no todo tool, so the agent todo list source could not be captured (D8).
- `ToolSearch` calls also fire `PreToolUse` and `PostToolUse`; filter them out.
- The hook's `$PPID` is the agent process (D2).

## Decisions

### D1. Durable store: SQLite, hooks write to it directly

- **Decision**: One SQLite database (WAL, `busy_timeout` ~2 s) in the XDG state dir. The `hook` subcommand opens it, applies one short transaction, exits 0 regardless of outcome. No daemon sits between hook and store.
- **Rationale**: Today's state is `$XDG_RUNTIME_DIR/claude-monitor/<id>.json` (verified: `src/session.rs`), which is wiped at reboot, the exact failure the spec exists to fix. SQLite gives atomic multi-row updates, indexed queries for SC-007 and a natural append-only event log for attribution (FR-024), with no service to keep alive.
- **Alternatives**: durable JSON files per session (no queries, no history); a daemon owning the store (extra moving part that can be down while hooks fire); Postgres as cortexiphan does (needs a server; breaks "works without anything else", FR-027).

### D2. Liveness = process identity + boot id, not just pid

- **Decision**: On `SessionStart` (and refreshed on later hooks) the hook records the agent PID (its parent), that PID's start time from `/proc/<pid>/stat` field 22, and the machine boot id (`/proc/sys/kernel/random/boot_id`, verified present). A session is *running* iff the PID exists with the same start time and the boot id matches. A session with no clean `SessionEnd` that is not running is *interrupted*. A different boot id marks every non-ended session interrupted immediately, with no process probing.
- **Rationale**: Pid reuse after hours or a reboot would otherwise resurrect dead sessions. Matches FR-008 ("detect without the user reporting") and the "reboot is interrupted, never finished" edge case. Existing `prune_stale_panes` (tmux pane gone) stays as a secondary signal.
- **Alternatives**: tmux pane existence only (breaks for sessions outside tmux; a pane id is reused after a tmux server restart); heartbeat timestamps only (30 s detection forces constant writes; cannot tell kill from idle).
- **Observed (R2)**: the hook process's `$PPID` is the agent process. Its command name is `.claude-wrapped`, so `pgrep -x claude` misses it; use the hook PPID, or match on the command line. PPID was stable across `Stop` and `SessionEnd` of a `-p` session; whether it survives `/clear` interactively is unverified.
- **Candidate source (R10)**: `~/.claude/sessions/<pid>.json` is a live-process registry with keys `cwd`, `kind`, `name`, `pid`, `sessionId`, `startedAt`, `status`, `updatedAt`, `tmux`, `entrypoint`, `version`. Inferred, not verified: entries exist only for live interactive processes (`-p` runs left none). It could supply liveness, status and the tmux pane natively; to be checked in spike R10.
- **Open**: macOS has no `/proc`: use `sysctl kern.boottime` for boot id and `proc_pidinfo`/`ps -o lstart=` for start time (R5).

### D3. Clean end vs interrupted

- **Decision**: `SessionEnd` observed → `finished` (clean end), regardless of whether the task completed; the user can still set *parked*, and a finished session stays visible and respawnable (FR-019a) because a clean exit does not mean the work was done. No `SessionEnd` and not running → `interrupted`. `/clear` (a `SessionEnd` with reason `clear`) starts a new session id in the same pane and is recorded as a lineage step, not as work finishing. Reason codes are stored raw so this can be tightened without migration.
- **Rationale**: The spec's "finished" is a user-meaning (task done) the system cannot know; the closest knowable proxy is a clean exit. The costly mistake is the opposite one (hiding interrupted work), which this rule avoids.
- **Observed (R2, 2.1.293)**: `SessionEnd.reason` values seen are `other` (`-p` exit), `clear` (`/clear`, old session id) and `prompt_input_exit` (Ctrl-D at an empty prompt, two presses). Not seen: `logout`, `bypass_permissions_disabled`, `resume`. Keep storing the raw value.

### D4. Respawn: tmux window per session, launcher from config

- **Decision**: Respawn runs a configurable launcher in `tmux new-window -c <cwd>` inside a configurable tmux session (default `agents`), creating the tmux server/session if absent. Default launchers: Claude `claude --resume <session_id>`, Copilot `copilot --resume <session_id>`. The user's real `claude` is a wrapper; the template is the single place that knows that.
- **Rationale**: the transcript lives at `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`, where the encoding replaces every non-alphanumeric character of the absolute cwd with `-` (lossy, cannot be decoded back). `--resume <id>` finds the transcript without regard to the cwd (R1), but the process then runs in the cwd it was launched from, which changes tools, CLAUDE.md lookup, the git branch and the per-line `cwd` field. So respawn in the recorded cwd for correctness. Before launching, the planner checks the directory exists and, for Claude, that the transcript file exists; either missing is the refusal in FR-012. Already-running check (FR-013) reads liveness, then the lineage head. Never use `--continue`: it is cwd-scoped and silently starts a fresh session when none exists there.
- **Same record on resume**: `--resume <id>` keeps the same session id and appends to the same transcript (R1). A respawn therefore revives the SAME Session record: a `SessionStart` with `source=resume` for a known session id updates that record in place and returns it to idle. No duplicate row appears (FR-011). The pane id stored on the respawn request still lets us attribute the new process to the request.
- **Lineage links**: a link row exists only where the session id changes: `/clear` (`SessionStart source=clear`, new id; `resumed_from` points at the old id) and `--fork-session` (new id, new transcript, copied history; `forked_from`). Claude writes no parent link into a fork; the only trace is shared message uuids (35 of 42 uuid-bearing lines shared in the spike). So a fork is detected at passive discovery by shared uuids, or recorded by us when we launch it. A fork launched by hand and never seen by us shows as an independent session.
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
  1. **Agent todo list** (unverified, optional): from the `PostToolUse` hook for the todo tool (`tool_input.todos[]` with `content`/`status`), stored as the session's latest list. The Claude Code in this environment (2.1.293) exposes no todo tool (no `TodoWrite`, `TaskCreate` or `TaskUpdate`), so the payload could not be captured; it may be gated by a setting. Treat this source as optional and tolerate its absence. For Copilot, none is found yet, so this source is absent for it.
  2. **Spec-kit `tasks.md`**: lines `- [ ] T### ...` / `- [x] T### ...`, grouped by phase headings.
  3. **Generic Markdown checklist**: any `- [ ]`/`- [x]` lines in a chosen file (`PENDING.md`, `todo.md`, other).
- **Selection (FR-015a)**: candidate files are those in the session repository root and `specs/*/`. A spec-kit directory is auto-bound when it matches the branch name prefix or `.specify/feature.json` (both exist in this repo and cortexiphan) or when only one candidate exists. Otherwise the candidates are listed and the user picks; the choice is stored in `progress_binding` keyed by session/project. Figures always show the source label.
- **Rationale**: the user explicitly chose all three sources; a wrong guess would present false progress, which FR-016 forbids.

### D9. Summaries: verbatim by default, local model on demand

- **Decision**: Task description = the first `UserPromptSubmit` prompt (truncated for display, full text stored). "Where we left off" = latest assistant message, taken from `last_assistant_message` in the `Stop` payload (once per turn, full text, observed in R2); the tail of the transcript JSONL (path from `transcript_path`) is only a fallback. On-demand summary calls an OpenAI-compatible endpoint configured in the module; the client **rejects non-loopback hosts**, enforcing FR-020 in code. Output is stored once in `summaries` with `model` and a `model_written` flag; verbatim text is never replaced.
- **Rationale**: the user chose this (clarification 5); this machine already runs local llama-server profiles for delegation.
- **Resolved (R2)**: the `Stop` payload carries the last assistant message on 2.1.293, so the transcript tail is not needed in the normal path.

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
| Store changed (for viewers in other processes) | would have been a `data_version` poll | **Change feed**: viewers watch the state dir with `notify` (inotify on Linux, FSEvents on macOS; `notify` 8 is already a dependency and `claude-monitor` already uses it for its dashboard). A write to `state.db-wal` fires the watcher; a start-anchored throttle window of 50 ms (fire 50 ms after the first event of a group, then re-arm; not a trailing debounce, which starves under continuous writes, see R8); then read `events` rows with `seq > last_seen` (cursor kept in memory). The watch is a wake-up, not a payload: the rows say exactly what changed, so the TUI and SSE push only that. |
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
- **Remaining polling, stated honestly**: (1) a slow safety-net reconcile (default 60 s, only while a viewer is open) because inotify can drop events when queues overflow, the `-wal` file is deleted on checkpoint, macOS FSEvents coalesces, and R8 only covered tmpfs on Linux (ext4, btrfs and NFS untested); (2) the cortexiphan linked-side status, which is a pull from a remote with no push channel, done on view and on `links check`, never on a timer; (3) the on-demand model summary is a request/response call.
- **Design consequence**: the library exposes `trait EventSource { fn next(&mut self) -> Event }` implementations (fs watcher, pidfd/kqueue, tmux hook invocation) and a `ChangeFeed` that merges them; tests inject a fake source and a fake clock, so no test sleeps or polls (constitution II; keeps CI fast and non-flaky).
- **Rationale**: lower latency and idle cost, no wasted wakeups on a laptop, and it matches the append-only event log already planned for attribution: the same `events.seq` is the cursor for views, SSE and the cortexiphan export.
- **Alternatives**: a long-running daemon owning everything (one more thing to be down; rejected in D1); a Unix datagram "bus" socket that writers ping after commit (precise, but listeners must exist or writers must handle absence; the fs watch on the DB achieves the same without a protocol and works when no listener is up); pure timers (what the plan had).
- **R8 (done 2026-10-12)**: inotify reliably fires on `-wal` appends on Linux/tmpfs; see the evidence section. Still open: macOS FSEvents latency (it coalesces, typically < 1 s) and non-tmpfs filesystems.

## Open spikes (ordered by risk to the spec)

| # | Question | Why it matters | Method | Blocks |
|---|---|---|---|---|
| R3 | Can Copilot hooks record a PID and report state on this machine? Does resume work from another cwd? | Decides whether "Copilot fully supported" (clarification 3) holds, or FR-014 applies | Install a throwaway hooks file under a temporary `COPILOT_HOME`, run a trivial session, inspect payloads and `$PPID` | Slice 5 |
| R1 | DONE 2026-10-12. On `claude --resume <id>` does the session id stay the same or change, and can it be resumed from another cwd? Same id; works from any cwd but runs there. | Lineage linking and the cwd rule | Run twice in a scratch dir; compare `~/.claude/projects/*` | Slice 3 |
| R2 | DONE 2026-10-12 (todo tool not capturable here). Exact hook payloads on Claude Code 2.1.293: `SessionEnd.reason`, `SessionStart.source`, todo tool name and `tool_input`, `Stop` last message | State machine, progress source 1, summaries | Log raw stdin with a throwaway hook for one session | Slices 1, 2, 6 |
| R6 | Does Copilot also run hooks from `~/.claude/settings.json`? | Double events | Run Copilot with the Claude monitor hook present and count events | Slice 5 |
| R5 | macOS boot id and process start time | Liveness parity | `sysctl kern.boottime`; `ps -o lstart= -p` | Slice 2 (macOS) |
| R7 | Does a private `tmux` server run inside the Nix check sandbox? | Respawn integration test in CI | Try in a `runCommand` check | Slice 3 |
| R8 | DONE 2026-10-12 on Linux/tmpfs (macOS FSEvents and other filesystems still open). Does inotify fire on SQLite WAL appends reliably, with what latency; FSEvents on macOS? | The whole change feed (D12) | Commit in one process, time the watcher callback in another, 1000 iterations | Slice 1 |
| R10 | What does `~/.claude/sessions/<pid>.json` hold for live interactive sessions: keys, when written and removed, `status` values, the `tmux` field? | Possible native source for liveness, status and tmux pane (D2) | Start and stop interactive sessions in tmux, watch the directory | Slice 2 |
| R9 | Do tmux `set-hook` `pane-exited`/`pane-died` fire for panes running `claude`/`copilot` on tmux's current version, and can they run a command with the pane id? | Instant pane-gone detection | Set hooks on a private tmux server, kill panes | Slice 2 |

R1, R2, R6 and R3 are each under 30 minutes and are scheduled as the first tasks of their slices, as characterisation tests that stay in the repo as fixtures.
