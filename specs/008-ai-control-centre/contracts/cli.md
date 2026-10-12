# Contract: `claude-monitor` command line

One binary, two modes (FR-035): with no subcommand it opens the interactive TUI; with a subcommand it is a non-interactive CLI. Every action reachable in the TUI (respawn, restore selection, done, dismiss, park, note, group, choose progress source, summarize, link) is a subcommand below with `--json` output, so scripts and the TUI do the same things. The binary is a thin consumer of the `claude_monitor` library: it parses arguments, calls `claude_monitor::cli::run`, prints the returned `Output` (text or JSON) and maps the library's error type to the exit codes below. Parity between TUI actions and subcommands is enforced by a test that enumerates both from the library's `Command` enum.

Existing behaviour (no subcommand = TUI dashboard; `hook` reads hook JSON on stdin) is unchanged. New and extended subcommands below. Global flags: `--json` (machine output, errors as `{"ok":false,"error":"<operation>: <detail>"}`), `--state-dir <path>` (overrides the XDG state dir; tests use it). Exit codes: `0` success, `1` usage/config error, `2` precondition refused (e.g. respawn refused), `3` partial success (some items failed).

| Command | Purpose | Requirements |
|---|---|---|
| `claude-monitor` | TUI overview: active and interrupted first, then finished (recent listed, older collapsed under a count), dismissed hidden | FR-001 to FR-003, FR-019 |
| `claude-monitor list [--json] [--state S]... [--agent K] [--repo R] [--project P] [--text T] [--include-dismissed] [--expand-finished]` | Overview as text/JSON; the filter set the TUI and web share | FR-019 |
| `claude-monitor show <session>` | One session: description, left-off, progress with source label, links, notes, lineage | FR-015, FR-017 |
| `claude-monitor hook [--agent claude\|copilot]` | Ingest one hook payload from stdin. Always exits 0, never writes stdout; failures go to `<state-dir>/hook.log` | FR-005, FR-008 |
| `claude-monitor reconcile [--pane %N \| --session ID]` | Apply liveness rules to everything, or only to one pane/session (what the tmux `pane-exited` hook calls); idempotent | FR-008 |
| `claude-monitor watch` | Optional headless watcher (user service, off by default): runs the same process-exit, file and tmux event sources as the viewers so desktop notifications fire with no viewer open | FR-008, research D12 |
| `claude-monitor restore [--all-interrupted] [--include-finished] [--yes]` | TUI checklist of interrupted sessions (all selected; deselect to opt out); finished sessions are listed unselected and can be ticked (FR-019a); Enter respawns the selection. `--all-interrupted --yes` is the non-interactive form; still requires the explicit flag (FR-034) | FR-009, FR-010, FR-033 |
| `claude-monitor respawn <session>... [--fresh [--in <dir>]] [--recreate-worktree]` | Respawn named sessions. `--fresh` starts without resume and says so; `--fresh --in <dir>` starts a new session in another directory (for example the repo's main checkout); `--recreate-worktree` runs `git worktree add` for a missing worktree whose branch still exists, only when given. A refusal names the problem and prints these alternatives; none is ever taken automatically | FR-009, FR-012 to FR-014 |
| `claude-monitor boot-check [--banner]` | Reconcile; if interrupted sessions exist, notify and write the marker; start nothing. `--banner` prints a one-line tmux `display-message` ("N AI sessions interrupted, prefix+A to review") once and clears the marker; run by tmux's `client-attached` hook | FR-032, FR-034 |
| `claude-monitor project add\|rename\|set-status <name>`; `claude-monitor group <project> <session>...` | Projects and grouping | FR-018 |
| `claude-monitor note <session\|project> <text>` | Attach a note | FR-018 |
| `claude-monitor park\|unpark\|dismiss\|undismiss <session\|project>` | Markers; never deletes | FR-018, FR-019 |
| `claude-monitor done <session>...` / `undone <session>...` | Mark a finished session done (moves to its project's Done section) or return it to Finished; `done` on a non-finished session exits 2 with the reason | FR-019b, FR-019c |
| `claude-monitor list --section active\|interrupted\|finished\|done\|dismissed [--project P]` | Restrict to one view section; `--project` scopes to that project's sections, `--project -` to sessions in no project | FR-019b |
| `claude-monitor delete <session>` | The only deleting command; asks to confirm unless `--yes` | spec Assumptions (retention) |
| `claude-monitor progress bind <owner> [--file P \| --source agent_todo]` | Choose the plan source; with no flag lists candidates | FR-015a |
| `claude-monitor summarize <session\|project>` | Generate and store a model-written summary using the configured loopback endpoint; refuses a non-loopback endpoint | FR-017a, FR-020 |
| `claude-monitor serve [--port N]` | Web view on `127.0.0.1`; prints the URL with the one-time token | FR-030, FR-031 |
| `claude-monitor link <owner> --cortex <node-id> --kind project\|task\|memory` | Record a cortexiphan link | FR-026 |
| `claude-monitor export cortexiphan [--project P] [--out FILE]` | JSON Lines export, see `cortexiphan-export.md` | FR-025 |
| `claude-monitor links check` | Show linked records whose two sides disagree | FR-028 |
| `claude-monitor migrate` | One-time import of legacy runtime JSON files into the store (run automatically on first start) | FR-022 |

## Output shape for `list --json`

```json
{
  "sessions": [
    {
      "id": "uuid",
      "agent_kind": "claude",
      "agent_session_id": "…",
      "repo": "nix-config",
      "branch": "008-ai-control-centre",
      "cwd": "/home/…/worktrees/…",
      "state": "needs_permission",
      "running": true,
      "last_activity_at": "2026-10-12T14:03:22Z",
      "task_description": "…",
      "left_off": "…",
      "progress": { "source": "specs/008-ai-control-centre/tasks.md", "done": 4, "total": 10, "current": "T005 …" },
      "project": "ai-control-centre",
      "flags": ["worktree_missing"]
    }
  ]
}
```

`progress` is omitted (not zero) when no binding exists (FR-016). `section` is one of `active`, `interrupted`, `finished`, `done`, `dismissed`. `flags` may contain `worktree_missing`, `parked`, `dismissed`, `state_unknown`, `degraded` (record unreadable in part, FR-021).
