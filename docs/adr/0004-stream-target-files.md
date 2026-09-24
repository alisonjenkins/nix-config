# 0004. Publish the stream target as files under `~/.local/state`

- Status: Accepted
- Date: 2026-08-26, commit `e3592250` (recorded 2026-09-24)

## Context

Three things need to know, while a client streams, which output it streams and
at what size: the display filter inside Steam ([0003](0003-steam-display-filter.md)),
the steam-command-runner shim that launches games, and anything debugging the
setup. The watcher that knows ([0005](0005-stream-mode-owns-stream-state.md))
is a separate process.

## Decision

The watcher writes two files in `~/.local/state/stream-mode/`, present only
while a client streams:

| File | Contents | Read by | Found through |
|---|---|---|---|
| `target` | `1280x800` | steam-display-filter | `STEAM_STREAM_TARGET` |
| `target.json` | `{"output":"steam","width":1280,"height":800,"refresh":60}` | steam-command-runner shim | `STEAM_COMMAND_RUNNER_STREAM_TARGET` |

Both variables are set in Steam's FHS environment in
`flake-modules/hosts/ali-desktop/default.nix`, from one `streamModeState`
binding. Absolute paths, because `buildFHSEnv` writes `extraEnv` verbatim and
a literal `$HOME` would reach the process unexpanded.

The files are the entire interface. The watcher never talks to the filter or
the shim, which is what lets each work, or be tested, without the others.

**Teardown order is load bearing:** turn the output off, *then* withdraw the
target. The reverse leaves the output present with the filter inert, Steam
recomputes in that gap, caches the union of both monitors, and sizes the next
stream to it.

## Alternatives rejected

- **`$XDG_RUNTIME_DIR` (`/run/user/<uid>`)**, the natural home for session
  state. `steamwebhelper` runs in a pressure-vessel container that mounts a
  filtered `/run/user/<uid>` and cannot see files there.
- **Only the size file.** Publishing just `WIDTHxHEIGHT` was the whole
  interface for a while. The shim also needs the output name, found nothing,
  took that for "not streaming", and launched games at the desktop's size.

## Consequences

The shim's own default is `$XDG_RUNTIME_DIR/stream-mode/target.json`, so the
variable is required. **It was missing until 2026-09-24**: from the move to
`~/.local/state` until then, the shim never saw a stream, and its resizing
([steam-command-runner ADR 0006](https://github.com/alisonjenkins/steam-command-runner/blob/main/docs/adr/0006-render-at-client-resolution.md))
never ran. Check it first if stream-aware behaviour seems absent:
`grep STREAM_TARGET /proc/$(pgrep -x steam)/environ`.

## Evidence

Nothing logged the missing variable. It was found by reading both sides'
defaults while wiring up [0007](0007-remote-play-game-mode.md). The built
Steam profile now contains
`STEAM_COMMAND_RUNNER_STREAM_TARGET=/home/ali/.local/state/stream-mode/target.json`.

## Revisit when

Steam stops running its client in a container, or a consumer needs more than
the target.
