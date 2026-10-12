# 0040. Keep control-centre state in SQLite, judge liveness by process identity, and drive it from events

- Status: Proposed
- Date: 2026-10-12
- Design: [`specs/008-ai-control-centre/`](../../specs/008-ai-control-centre/)
  (`research.md` D1, D2, D3 and D12)

## Context

`claude-monitor` keeps session state in
`$XDG_RUNTIME_DIR/claude-monitor/<id>.json`. That directory is wiped at reboot, so
the sessions that were running when the machine went down vanish, which is the
failure the AI control centre exists to fix. Three questions follow: where state
lives, how to tell a running session from a dead one, and how viewers learn that
something changed.

Constraints from the spec: the control centre must work with nothing else installed
(FR-027), detect a dead agent without the user reporting it (FR-008), keep an
attributed history of changes (FR-024), and treat a reboot as "interrupted", never
"finished".

## Decision

- **Store.** One SQLite database in the XDG state dir
  (`$XDG_STATE_HOME/ai-control-centre/state.db`, mode 0600, WAL, `busy_timeout` about
  2 s). The `hook` subcommand opens it, applies one short transaction and exits 0
  regardless of outcome. No daemon sits between a hook and the store.
- **Change feed.** An append-only `events` table is written in the same transaction
  as the projection update. Its `seq` is the cursor: the TUI, the web view (over
  Server-Sent Events) and the cortexiphan export all read "rows with `seq` greater
  than the last seen".
- **Liveness.** On `SessionStart`, and refreshed on later hooks, the hook records the
  agent PID, that PID's start time (`/proc/<pid>/stat` field 22) and the machine boot
  id (`/proc/sys/kernel/random/boot_id`). A session is running only if the PID exists
  with the same start time and the boot id matches. A different boot id marks every
  non-ended session interrupted without probing any process. macOS uses
  `sysctl kern.boottime` and `ps -o lstart=` (open spike R5).
- **End states.** A `SessionEnd` observed means `finished` (a clean end, whether or
  not the task was done). No `SessionEnd` and not running means `interrupted`.
  Finished sessions stay visible and can be respawned, because a clean exit does not
  mean the work was done. `/clear` is recorded as a lineage step, not as finishing.
  Reason codes are stored raw so the rule can be tightened without a migration.
- **Event-driven sources.** Nothing sleeps on a timer to find out something happened:
  hook invocations; `notify` file watches (inotify, FSEvents) on the state dir, on
  bound plan files and on `~/.copilot/session-state/`; `pidfd_open` plus `poll` on
  Linux and `kqueue` `EVFILT_PROC` on macOS for agent exit; `tmux set-hook` for pane
  exit; and a login user unit (systemd or launchd) that runs `boot-check`.
- **One safety net.** A reconcile every 60 s, only while a viewer is open, because
  inotify can drop events when its queue overflows and FSEvents coalesces. Viewers
  also reconcile once before the first render.

## Alternatives rejected

| Option | Why not |
|---|---|
| Durable JSON files per session | No indexed queries for the filters and SC-007, no history, no atomic multi-row update. Adding them means reimplementing a database. |
| A daemon that owns the store | One more thing that can be down while hooks fire. Hooks writing directly keeps the store correct with no viewer and no service. |
| Postgres, as cortexiphan uses | Needs a server; breaks "works without anything else". |
| Liveness by PID alone | PIDs are reused after hours or a reboot and would resurrect dead sessions. |
| Liveness by tmux pane existence only | Fails for sessions outside tmux, and pane ids repeat after a tmux server restart. Kept as a secondary signal. |
| Heartbeat timestamps only | Needs constant writes for a 30 s detection and cannot tell a killed session from an idle one. |
| Polling (`data_version`, periodic `list-panes`, periodic scans) | Wasted wakeups on a laptop and slower than the OS's own notifications. Reduced to the single 60 s safety net. |
| A Unix datagram bus that writers ping after commit | Writers must handle absent listeners; the file watch on the database gives the same signal with no protocol. |

## Consequences

- State survives reboot. The reboot case is decided by one boot-id comparison.
- Detecting a killed agent is immediate while a viewer or the optional headless
  `claude-monitor watch` service is running; without one, the next viewer's open-time
  reconcile corrects it. Worst case with a viewer open is the 60 s net.
- Hooks swallow their own errors (a failing hook must never wedge the agent) and log
  operation and inputs to a rotating file in the state dir. This is a deliberate
  exception to "errors carry context" propagation.
- The library exposes an `EventSource` trait and a `ChangeFeed`, so tests inject fake
  sources and a fake clock and nothing in the suite sleeps.
- Remaining pulls, stated honestly: the cortexiphan linked-side status (on view and on
  `links check`) and the on-demand model summary.

## Evidence

Not yet measured. These spikes in `research.md` decide whether the design holds:

- R8: inotify fires on SQLite `-wal` appends reliably, and the latency from commit to
  watcher callback; FSEvents latency on macOS.
- R9: tmux `pane-exited` and `pane-died` hooks fire for panes running `claude` or
  `copilot` and can pass the pane id.
- R5: macOS boot id and process start time.
- R2: the exact `SessionEnd.reason` vocabulary on Claude Code 2.1.293.

## Revisit when

- R8 shows WAL appends do not reliably wake the watcher; the change feed would need a
  different signal.
- A second writer other than hooks needs the store, which would make a daemon worth its
  cost.
- `SessionEnd` proves unreliable, so clean ends are mistaken for interruptions.
