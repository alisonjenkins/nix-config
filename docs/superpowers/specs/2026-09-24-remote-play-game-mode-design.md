# Remote Play game mode: stream-aware launches

Date: 2026-09-24
Status: design, implementation starting with steam-command-runner

## 1. Problem

Mouselook over Steam Remote Play stops at the edge of the client window. The
camera turns until the Mac client's cursor reaches its own window edge, then
stops. A full 360 is impossible.

The cause is not input routing. Every session so far ran as a **Desktop
stream**. In that mode the client sends absolute cursor positions confined to
its window, so there is nothing to send past the edge. Only a **game-mode
stream** makes the client capture the mouse and send relative motion.

Live evidence from 2026-09-24, all from Steam's own logs and a uinput capture:

| Mode | streaming_log.txt | Mouse from the client |
|---|---|---|
| Desktop | `Switching video stream ... to Desktop_MovieStream` | absolute, clamped at the window edge |
| Game | `k_EStreamActivityGame`, `Capture method set to Game Vulkan NV12` | relative, unbounded (12,343 px net in one test) |

With HD2 launched the working way, the camera turned freely and video was live.

## 2. Why Steam never entered game mode

Four separate blockers. Each one alone keeps Steam in desktop mode or breaks
game capture.

1. **Per-game gamescope hides the window from Steam.** gamescope runs the game
   on its own nested X display (`:1`). Steam runs on `:0` and logs
   `Changing record window: (nil)`. It cannot find the game window, so it falls
   back to desktop capture.
2. **Stale `GAMESCOPE_*` atoms on `:0`.** gamescope opens `:0` to copy the host
   cursor and leaves atoms such as `GAMESCOPE_DISPLAY_HDR_ENABLED` on its root
   window. Steam sees them, behaves as if it runs inside a gamescope session,
   reads focus from `GAMESCOPE_FOCUSED_APP`, gets `appID 0`, and flaps between
   game and desktop mode.
3. **A helper process of the other bitness claims the game window.** HD2's
   GameGuard monitor is a 32-bit Wine process. Steam preloads both the 32-bit
   and 64-bit overlay into every process of the game, so GameGuard's copy of the
   overlay registers the game window first. Steam binds game capture to that
   pid (`GameOverlay_MovieStream_599422`). GameGuard exits after about 8 seconds
   and the video freezes.
4. **Wine's tray window gets treated as the game.** With no XEmbed tray on
   `:0`, Wine shows its own 160x20 `explorer.exe /desktop` tray window.
   `steam-stream-mode` picks it as the game window, fullscreens it and keeps
   giving it focus, so Steam records a white window.

A fifth, smaller one: niri's top-left hot corner opens the overview whenever
the stream cursor parks there.

## 3. Goals and non-goals

Goals:

- Any game launched from a Remote Play client streams in game mode, with no
  per-game setup.
- Local play is unchanged, including gamescope and its HDR and FSR tuning.
- Every decision is logged, so a failure can be read from logs rather than
  guessed from the picture.

Non-goals:

- A game started locally and streamed later. It stays inside gamescope and
  streams in desktop mode until relaunched. Launching from the client is the
  normal flow.
- Fixing Steam's pid binding itself. It is closed source. We avoid triggering it.

## 4. Design

The split follows when each decision is made. Per-launch decisions go in
steam-command-runner, which already sits in the launch chain as the
`gamescope` shim. Per-session decisions go in `steam-stream-mode`, which
already owns the stream lifecycle.

### 4a. steam-command-runner: launch without gamescope while streaming

When the shim runs and a stream is active (`StreamTarget::detect()` finds
`$XDG_RUNTIME_DIR/stream-mode/target.json`), it runs the game directly instead
of wrapping it in gamescope. The game then lands on `:0`, where Steam can find,
focus and capture it. This fixes blockers 1 and 2 at their source, because no
gamescope process starts to write atoms to `:0`.

The direct launch keeps everything that is not gamescope:

- `pre_command` (for example `obs-gamecapture gamemoderun`)
- `env` and `inner_env`, both on the game process since there is no compositor
- `game_args`
- the `pre_launch` and `post_exit` hooks, still via spawn and wait

It drops the gamescope-only variables (`ENABLE_GAMESCOPE_WSI`,
`STEAM_GAMESCOPE_*`). Those tell the overlay that gamescope is present, which
would be false.

`gamescope_enabled = false` also takes the direct path, stream or not. Today
the shim ignores that flag for everything except extra arguments, which
surprised us tonight. Subnautica sets it, and runs fine either way, because
SteamVR renders to the headset without gamescope.

Configuration, global with per-game overrides:

```toml
[stream]
bypass_gamescope = true   # default true
overlay = "auto"          # auto | both | x86_64 | i386

# per game (games/<appid>.toml)
stream_bypass_gamescope = false
stream_overlay = "both"
```

### 4b. steam-command-runner: keep only the matching overlay

While streaming, the shim reads the game binary's architecture and removes
the other architecture's `gameoverlayrenderer.so` from `LD_PRELOAD`. A 64-bit
game keeps `ubuntu12_64/gameoverlayrenderer.so` and loses the 32-bit one, so a
32-bit launcher or anti-cheat helper cannot register the window first. This is
blocker 3, generalised.

Finding the game binary in Steam's `%command%` chain:

1. The last argument ending in `.exe` that exists on disk (Proton). The PE
   header's machine field says `0x8664` (x86_64) or `0x014c` (i386).
2. Otherwise, the first argument after the last `--` that exists and is an ELF
   file (native). `EI_CLASS` says 64 or 32 bit.
3. Otherwise, the architecture is unknown. The shim keeps both overlays and
   logs why.

Limit: a helper of the **same** bitness as the game can still claim the window
first. `stream_overlay` lets a game override the automatic choice. I expect
this to be rare. If it turns up, the fix is a per-game setting, not a code change.

Outside a stream, `LD_PRELOAD` is left alone. Local play gains nothing from the
filter, so it keeps Steam's exact behaviour.

### 4c. steam-stream-mode (nix-config, second step)

- At stream start, remove every `GAMESCOPE_*` atom from `:0`'s root window.
  After 4a no new ones appear during a stream, but a gamescope game played
  locally earlier leaves them behind.
- When picking the game window, skip windows smaller than 320x240 or with an
  empty title. That excludes Wine's tray window and splash popups, so
  fullscreen and focus reclaim land on the real window.

### 4d. niri (nix-config, second step)

Disable the hot corner. It exists only for local mouse use, and the stream
cursor keeps triggering it.

### 4e. extest: leave the derived relative motion alone

extest fabricates relative motion from consecutive absolute positions. In one
desktop-mode capture it double-counted with a rare real relative event (a real
+4 and a derived +5 for the same movement).

No change, on the evidence. In the working game-mode test the extest device
received zero absolute events: Steam sent only real relative motion, so the
derived path never ran. It only matters in desktop mode, which is now a
fallback. Revisit if a game-mode capture ever shows absolute and relative
events together.

## 5. Observability

The shim prints one line to stderr per launch, which reaches the journal
through Steam:

```
steam-command-runner: streaming to steam, launching without gamescope, overlay x86_64 only (from .../helldivers2.exe)
```

With `shim_debug`, the full decision and the final command line go to
`~/.steam-command-runner-shim.log`.

To verify a stream end to end, read `streaming_log.txt` for
`Capture method set to Game Vulkan`. A picture on the client is not proof.
Desktop capture also shows a picture.

## 6. Testing

steam-command-runner, test first, no live Steam needed:

- architecture detection from minimal PE and ELF headers written to temp files
- picking the game binary out of the real HD2 `%command%` chain, a native
  chain, and a chain with no recognisable binary
- `LD_PRELOAD` filtering for each architecture and for unknown
- the launch decision: gamescope when not streaming, direct when streaming,
  direct when `gamescope_enabled = false`, gamescope when streaming but
  `stream_bypass_gamescope = false`
- the direct command line: pre_command, then the game command, then game_args,
  and no gamescope variables in its environment

Live check after deploying: launch HD2 from the Mac with Launch Options back
on the shim. Expect the shim's stderr line, `Game Vulkan` in
`streaming_log.txt`, and unbounded camera rotation.

## 7. Order of work

1. steam-command-runner 4a and 4b, with tests: alisonjenkins/steam-command-runner#5.
2. nix-config 4c and 4d, plus `STEAM_COMMAND_RUNNER_STREAM_TARGET` so the shim
   can see the target at all (it never could: the watcher publishes under
   `~/.local/state`, the shim defaulted to `$XDG_RUNTIME_DIR`). Flake input on
   the runner branch.
3. Switch, set HD2's Launch Options back to the shim, remove
   `~/.local/bin/no-overlay32`, live test.
4. Merge the runner PR, point the flake input back at its default branch.
