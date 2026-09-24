# 0007. Stream games in game mode, without gamescope

- Status: Accepted, pending live test of the automated path
- Date: 2026-09-24

## Context

Over Remote Play, mouselook stopped at the edge of the client's window, so a
full 360 was impossible. It took two days and several wrong theories to find
the cause: **every session was a desktop stream.** In desktop mode the client
sends absolute cursor positions confined to its own window. Only game mode
makes it capture the mouse and send relative motion.

Read the mode from `~/.steam/steam/logs/streaming_log.txt`, never from the
picture. Desktop capture also shows the game.

| Mode | Log lines |
|---|---|
| Desktop | `Switching video stream ... to Desktop_MovieStream`, `Capture method set to Desktop PipeWire ...` |
| Game | `setting activity to k_EStreamActivityGame`, `Capture method set to Game Vulkan ...` |

Four independent blockers kept Steam out of game mode:

1. **gamescope hides the game from Steam.** gamescope runs the game on its own
   nested X display, `:1`. Steam runs on `:0` and logs
   `Changing record window: (nil)`.
2. **Stale `GAMESCOPE_*` atoms on `:0`.** gamescope opens the host display to
   copy its cursor and leaves atoms such as `GAMESCOPE_DISPLAY_HDR_ENABLED` on
   the root window. Steam then behaves as if it runs inside gamescope, reads
   focus from `GAMESCOPE_FOCUSED_APP`, gets `appID 0`, and flips between game
   and desktop mode.
3. **A helper process claims the game window first.** HD2's 32-bit GameGuard
   monitor registered the window through Steam's 32-bit overlay, then exited.
   Steam never re-binds, so game capture froze.
4. **Wine's tray window gets picked as the game.** steam-stream-mode
   fullscreened the 160x20 tray window and gave it focus. Steam streamed a
   white window.

## Decision

- steam-command-runner launches streamed games without gamescope, and keeps
  only the Steam overlay matching the game's architecture. This fixes 1 and 3,
  in that repo's ADRs 0007 and 0008. nix-config tells the shim where the
  stream target is ([0004](0004-stream-target-files.md)) and takes the runner
  from its branch until the PR merges.
- steam-stream-mode clears `GAMESCOPE_*` atoms from `:0` when a stream starts,
  and skips helper windows ([0005](0005-stream-mode-owns-stream-state.md)).
  This fixes 2 and 4.

## Alternatives rejected

All tried live on 2026-09-23 and 24:

- **Fix the camera in extest.** At the client's window edge nothing new
  arrives. A dwell-time measurement showed extest's X position pinned at the
  clamp value for 91% of a 13-second hold, with no events. An earlier reading
  missed this by counting events instead of measuring time.
- **gamescope `wayland_mouse_relmotion_without_keyboard_focus`**, set at
  runtime with `gamescopectl`. No effect: the client was never in relative
  mode.
- **Set `GAMESCOPE_FOCUSED_APP` on `:0` by hand.** Steam accepted the focus
  and still could not record a window that lives on `:1`.
- **Unmap and remap the game window, or rewrite `_NET_WM_PID`,** to make Steam
  re-attribute it. Steam caches the pid per window id and ignored both.
- **Run Steam inside one gamescope, Steam Deck style.** Would work, but it
  replaces the desktop session.

## Consequences

- Streamed games lose gamescope's HDR and FSR. The stream is SDR anyway.
- A game started locally and streamed later stays inside gamescope and streams
  in desktop mode until relaunched.
- HD2's Launch Options must be the shim again
  (`/home/ali/.local/bin/gamescope -- %command%`). The hand-made test wrapper,
  `~/.local/bin/no-overlay32`, goes once the automated path is confirmed.

## Evidence

With HD2 launched bare and the 32-bit overlay removed by hand:

```
>>> Switching video stream from Desktop_MovieStream to GameOverlay_MovieStream_634286
>>> Capture method set to Game Vulkan NV12 + VAAPI H264
```

An `evtest` capture of the extest device during a mouselook test showed zero
absolute events and 12,343 px of net relative X motion. The camera turned
freely. Full reasoning:
`docs/superpowers/specs/2026-09-24-remote-play-game-mode-design.md`.

## Revisit when

Steam can capture a window on a nested gamescope display, or a game misbehaves
without gamescope. The runner's per-game `stream_bypass_gamescope = false`
handles the second case.
