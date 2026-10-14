# AI control centre (claude-monitor)

`claude-monitor` is the overview for AI coding-agent sessions (Claude Code and
GitHub Copilot CLI) across worktrees and days. It shows what each session is
doing, keeps sessions after a kill or reboot, shows progress inside large
projects, and restarts sessions in the right worktree on request.

Design and decisions: `specs/008-ai-control-centre/` (spec, plan, research,
contracts, tasks), ADR 0040 (store, liveness, change feed) and ADR 0041 (code
home, coupling to cortexiphan). Code: the `claude-monitor` repository (a Rust
library plus a thin binary; features `tui` and `web`).

Nothing starts by itself. Respawning is always an explicit action: `respawn`,
`restore`, or the restore view in the TUI or web page.

## How it works

- **State**: one SQLite database (WAL) in `$XDG_STATE_HOME/claude-monitor`
  (default `~/.local/state/claude-monitor`; on macOS
  `~/Library/Application Support/claude-monitor`). Every change is an
  append-only `events` row with its author (user, agent, or system component);
  the row number is also the change feed that the TUI, `watch` and the web
  `/events` stream follow.
- **Sources**: agent hooks, plus passive discovery from Claude's
  `~/.claude/projects` and `~/.claude/sessions` registry and from Copilot's
  `session-state`. The overview works with no hook installed; hooks add the
  fine-grained states (needs permission, idle, working).
- **Liveness**: a session is live only when its pid is alive, the pid start
  time matches `/proc/<pid>/stat`, and the boot id matches. A different boot id
  marks every non-finished session `interrupted`. A clean end is `finished`
  and stays visible and respawnable whatever its age.
- **Sections**: active, interrupted, finished, done (set by you, finished
  only; per project and global), unseen (found on disk with no live process and
  no hook history; collapsed by default), dismissed (hidden).
- **Privacy**: no conversation text leaves the machine. The only network use is
  `summarize` (a loopback model you configure; there is no default) and
  `links check` (shells out to the cortexiphan client when its server and
  token variables are set). `tests/no_egress.rs` enforces this.

## Enabling it (Home Manager)

The module is `programs.claude-monitor` (in the claude-monitor flake). All
options default to off and change nothing until enabled.

| Option | What it installs |
|---|---|
| `enable`, `package` | The binary and the hooks that feed Claude sessions into the store |
| `copilot.enable`, `copilot.hooksDir` | A hooks file registering the binary as a Copilot CLI hook handler (each hook passes `--event`). Copilot only loads hooks for folders in `trustedFolders` in `$COPILOT_HOME/config.json` |
| `tmuxHooks.enable`, `tmuxHooks.snippet` | tmux `pane-exited`, `pane-died` and `window-unlinked` hooks that run `reconcile`. Needs tmux managed by Home Manager; otherwise paste `snippet` into your own `tmux.conf` |
| `bootCheck.enable` | A login job (systemd user unit, launchd agent on macOS) running `boot-check`: one notification if sessions were interrupted, starts nothing |
| `bootCheck.banner.enable`, `.snippet` | A tmux `client-attached` hook that shows a one-line banner once on the next attach |
| `watch.enable` | A systemd user service running the headless `watch` (one log line per state change) |
| `serve.enable`, `serve.port`, `serve.mtls` | The loopback web view as a background user service: a systemd user unit on Linux, a launchd agent on macOS (default port 8765). `serve.mtls` also requires a client certificate. Enabled on every machine here; see [Always-on web view](#always-on-web-view) |
| `launchers.<kind>`, `tmuxSession` | Resume command templates (`{session_id}`, `{cwd}`, `{name}`) per agent kind, and the tmux session respawned windows go in (default `agents`). Written to `$XDG_CONFIG_HOME/claude-monitor/config.json` |

Environment overrides: `CLAUDE_MONITOR_LAUNCHER_<KIND>` (for example
`_CLAUDE`), `CLAUDE_MONITOR_TMUX_SESSION`, `CLAUDE_MONITOR_TMUX_SOCKET` (a
private tmux server; used by tests), `CLAUDE_MONITOR_SUMMARY_URL` and
`CLAUDE_MONITOR_SUMMARY_MODEL` (loopback summaries), `CORTEXIPHAN_SERVER` and
`CORTEXIPHAN_TOKEN` (links check).

## Always-on web view

`home/programs/claude-code/default.nix` turns on `programs.claude-monitor.serve`
for every home-manager profile (decision: [ADR 0042](adr/0042-run-the-control-centre-web-view-as-a-user-service-everywhere.md)).
Besides the web view, the service runs the live refresh loop, so the store
stays current without a dashboard open. That is what a post-reboot `restore`
plan is built from.

| | Linux | macOS |
|---|---|---|
| Service | systemd user unit `claude-monitor-serve` | launchd agent `claude-monitor-serve` |
| Port | 8801 | 8801 |
| Client certificate (mTLS) | required; imported into the Zen profile at activation | required; imported into the Zen profile at activation |
| Log | `journalctl --user -u claude-monitor-serve` | `~/Library/Logs/claude-monitor-serve.log` |

Port 8801 and not the 8765 default, because DynamoDB Local holds 8765 on
ali-desktop.

First use on a machine:

1. Stop any `claude-monitor serve` you started by hand on 8801; it would stop
   the service from binding.
2. Switch the configuration (`just switch`).
3. Close Zen before the switch if you can: the activation skips a profile
   that is open, prints a line saying so, and the certificate is then not
   imported. Re-run `claude-monitor web setup-browser --browser zen` after
   closing it. On a Mac, check first with `--dry-run` that it finds the
   profile.
4. Run `claude-monitor web login` and open the URL it prints (valid five
   minutes, single use). Open `https://127.0.0.1:8801/` in Zen, which now
   trusts the install's CA and presents the client certificate. Another
   browser needs the CA (`claude-monitor web ca`) and a certificate
   (`claude-monitor web client-cert`) imported by hand; on a Mac that
   includes Chrome and Safari (Keychain).

Check it is up: `systemctl --user status claude-monitor-serve` (Linux),
`launchctl print gui/$(id -u)/org.nix-community.home.claude-monitor-serve`
(macOS; the label is the one the evaluated configuration sets, checked with `nix eval`).
Turn it off for one machine with
`programs.claude-monitor.serve.enable = lib.mkForce false;` in that host's
home configuration.

Limits: the listener is loopback only. TLS and mTLS do not stop malware running
as your user, because the client key sits in the browser profile. The macOS
agent and the macOS browser setup have been evaluated, not run on a Mac; the
Zen profile path there (`~/Library/Application Support/zen`) is unconfirmed.

## Using it

```
claude-monitor                      # TUI
claude-monitor list [--json]        # same overview as text or JSON
claude-monitor show <id>            # detail: progress, summaries, notes, links
claude-monitor restore              # dry run: what would restart
claude-monitor restore --all-interrupted --yes [--skip <id>...]
claude-monitor respawn <id>...      # also works for finished sessions
claude-monitor progress <id>        # plan progress and its source file
claude-monitor project|group|note|park|dismiss|done ...   # organise
claude-monitor export cortexiphan [--project P] [--include-text] [--out FILE]
claude-monitor serve                # web view on 127.0.0.1
```

`--no-refresh` skips the scan that `list`, `show` and the TUI do on open.

TUI keys: `j`/`k` move, Enter jumps to the pane, `i` detail, `R` restore view
(all interrupted pre-selected, deselect to opt out, Enter then Enter again to
start), `u` toggle the unseen section, `p` group by project, `/` filter, `f`
state filter, `a` agent filter, `S` show dismissed, `D` done, `U` undone, `x`
dismiss, `n` note, `L` check links, `d` hide, `q` quit.

## Reboot and recovery

1. After login, `boot-check` notifies once if sessions were interrupted; the
   next tmux attach shows the banner.
2. Open the TUI (`prefix` binding or `claude-monitor`), press `R`, deselect the
   ones to skip, confirm. Each session reopens in its recorded worktree inside
   the `agents` tmux session with `--resume` (same session id, same
   transcript).
3. A missing worktree is refused with the exact `git worktree add` command, or
   `respawn --fresh --in <repo>` when the branch is gone. Nothing is created
   unless you pass `--recreate-worktree`.
4. Wrong state? `claude-monitor reconcile` re-checks liveness; `--session` and
   `--pane` narrow it. The 60 s safety net does the same while a viewer is open.
5. Logs: the hook never fails the agent; its problems go to `hook.log` in the
   state directory.

## Exporting for cortexiphan

`export cortexiphan` writes JSON Lines (Project, Task, Memory, session records)
with `external{system:"ai-control-centre", id}` keys, so a re-export is
idempotent. No conversation text is included unless `--include-text`. The
schema is `specs/008-ai-control-centre/contracts/cortexiphan-export.schema.json`
and a test fails if it drifts from the code. `link <owner> <node-id>` records a
pairing; `links check` compares statuses read-only and never writes either side.
