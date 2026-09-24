# 0005. One event-driven watcher owns all stream state

- Status: Accepted
- Date: 2026-08-24 (recorded 2026-09-24)

## Context

Several things must happen around a Remote Play session, in order: size and
enable the virtual output, publish the target, move the game onto the output,
fullscreen and focus it, and undo all of it afterwards. Steam offers no hook
for any of it. What it does offer is logs.

## Decision

`home/programs/linux-only/steam-stream-mode/` is a single Python program run
as a systemd user service. It is the only component that holds state or
decides anything. It reacts to events and never polls:

| Source | Watched for |
|---|---|
| `streaming_log.txt` | stream start and stop, the client's video size, `Adding window ... for process ... and gameID ...` |
| `remote_connections.txt` | client connects, including relayed connections |
| `niri msg --json event-stream` | windows opening, closing and changing layout, workspaces |

Rules that each came from a real failure:

- **Only touch the staged game**, plus anything that arrives on the streamed
  output while a game is staged, because splash screens get replaced by a new
  window. Acting on everything on the output once resized a terminal that
  drifted there 90 seconds after the game exited.
- **Skip helper windows.** Floating windows and anything under 320x240 are
  never treated as the game. Wine shows a 160x20 tray window with the game's
  app id when a game (HD2's GameGuard) adds a tray icon. stream-mode used to
  fullscreen it and keep giving it focus, and Steam streamed a white window.
- **Clear `GAMESCOPE_*` atoms from `:0` at stream start.** See
  [0007](0007-remote-play-game-mode.md).
- **Cap retries.** Fullscreen and refocus attempts per window are capped
  (`WIDEN_LIMIT`, `REFOCUS_LIMIT`), so a window that genuinely cannot be
  corrected is not fought forever, and a deliberate focus change on the
  desktop is not overridden indefinitely.
- **Teardown order**: output off, then withdraw the target. See
  [0004](0004-stream-target-files.md).

## Alternatives rejected

- **Polling niri.** The first version listed windows several times a second
  and still had to guess a deadline, because a game's window can appear
  minutes after Steam reports its pid.
- **Spreading the logic across the filter, the shim and niri config.** Each of
  those would need to know about the others. With one owner, each other piece
  only reads a file.

## Consequences

- **It fights manual window management while a stream runs.** When debugging
  focus, stop it first: `systemctl --user stop steam-stream-mode`. A
  `just switch` restarts it.
- The service needs `DISPLAY` for `xprop`. It inherits `DISPLAY=:0` from the
  systemd user environment.

## Evidence

`tests/test_stream_mode.py` (145 tests) covers log parsing, window selection,
staging, fullscreen, focus, helper windows and atom clearing. The atom tests
stub `xprop`, and the module pins `XPROP` to a path that does not exist, so no
test can touch a real X server.

## Revisit when

Steam exposes streaming events through an API, or niri gains a way to pin
windows to an output by rule while a condition holds.
