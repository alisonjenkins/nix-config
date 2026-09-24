# Remote Play troubleshooting

Symptom first. Each check says what to run, what the answer means, and which
decision record explains the mechanism. How the pieces fit together is in
[`steam-remote-play-streaming.md`](steam-remote-play-streaming.md); why each
one exists is in [`adr/`](adr/README.md).

**The one rule: trust the logs, not the picture.** A desktop stream also shows
the game. A frozen frame looks like a slow one. Most wrong turns so far came
from reasoning about what the client showed instead of what Steam logged.

## Symptoms

| Symptom | Check first | Record |
|---|---|---|
| Camera stops turning at the edge of the client window | [Stream mode](#which-mode-is-the-stream-in). Desktop mode means absolute mouse. | [0007](adr/0007-remote-play-game-mode.md) |
| Stream shows the whole desktop, not just the game | [Stream mode](#which-mode-is-the-stream-in), then [the shim's decision](#did-the-shim-launch-the-game-directly) | [0007](adr/0007-remote-play-game-mode.md) |
| Video frozen on one frame, input still works | [Which process Steam captures](#which-process-is-steam-capturing) | [0007](adr/0007-remote-play-game-mode.md) |
| Stream is a near-black rectangle | `grep 'Capture method' streaming_log.txt`: `Desktop Black Frame` that never becomes `Game Vulkan` or `PipeWire`, after `no more input formats` earlier in the log, means Steam's capture died. Restart Steam | PENDING.md item 9 |
| Client can't start a stream, host log shows nothing | No `connected`/`streaming request` line in `remote_connections.txt` means the client never reached Steam. Restart the client | |
| Game went through gamescope while streaming | Target withdrawn before launch? `journalctl --user -u steam-stream-mode \| grep -E 'published\|withdrew'` | [0013](adr/0013-disarm-on-client-disconnect.md) |
| Aspect stretched or wrong size | `cat ~/.local/state/stream-mode/clients.json`; `grep -E 'Maximum capture\|output size' streaming_log.txt` | [0012](adr/0012-size-output-from-client-reports.md) |
| Stream is a white or grey window | [Focus and helper windows](#which-window-has-focus) | [0005](adr/0005-stream-mode-owns-stream-state.md) |
| Stream flips between game and desktop mode | [`GAMESCOPE_*` atoms on `:0`](#gamescope-atoms-on-the-host-display) | [0007](adr/0007-remote-play-game-mode.md) |
| Clicks land on the wrong monitor | [extest loaded and current](#is-the-current-extest-loaded) | [0006](adr/0006-extest-remote-play-input.md) |
| Game letterboxed on the client | Display filter armed? `cat ~/.local/state/stream-mode/target` | [0003](adr/0003-steam-display-filter.md) |
| Overview keeps opening | Hot corner on the virtual output: [niri config valid?](#is-niris-config-actually-loaded) | [0002](adr/0002-virtual-output-for-remote-play.md) |
| A niri config change had no effect | [niri config valid?](#is-niris-config-actually-loaded) | [0010](adr/0010-niri-config-kdl.md) |
| MangoHud on the host but not in the stream | `VK_LOADER_DEBUG=layer vulkaninfo --summary`: MangoHud must be inserted last | [0011](adr/0011-mangohud-first-vulkan-layer.md) |
| No hardware encoding | `grep 'Capture method' streaming_log.txt` should end `+ VAAPI H264` | [0008](adr/0008-steam-libva.md) |
| Game dies at launch with `bwrap: Unexpected capabilities` | bubblewrap patch or the umu wrapper missing | [0009](adr/0009-gamescope-capabilities-and-bubblewrap.md) |

## Checks

All of Steam's logs are in `~/.steam/steam/logs/`.

### Which mode is the stream in?

```sh
grep -E 'setting activity|Switching video stream|Capture method|foreground' \
  ~/.steam/steam/logs/streaming_log.txt | tail
```

- `k_EStreamActivityGame`, `GameOverlay_MovieStream_<pid>` and
  `Capture method set to Game Vulkan ...` mean **game mode**: the client
  captures the mouse and sends relative motion.
- `Desktop_MovieStream` and `Bringing streamed game to foreground - failed`
  mean **desktop mode**: absolute cursor, confined to the client's window.

Steam decides the mode when the stream starts. After fixing something, start a
new stream.

### Did the shim launch the game directly?

```sh
grep ' app ' ~/.steam-command-runner-shim.log | tail -5
```

Every launch writes one line here, whatever `shim_debug` says. Steam throws
away the game's stderr, so the journal never has it. A streamed launch reads
`... app 553850: streaming to steam, launching without gamescope, overlay X86_64 only (from ...)`.
`no stream target, launching through gamescope` means the target was absent
when the game started. No line at all means the shim never ran. Then check,
in order:

1. Launch Options are `/home/ali/.local/bin/gamescope -- %command%`. A bare
   `gamescope` can skip the shim silently.
2. Steam can see the target:
   `tr '\0' '\n' < /proc/$(pgrep -x steam)/environ | grep STREAM_TARGET`
   must show `STEAM_COMMAND_RUNNER_STREAM_TARGET`.
3. The target exists while streaming:
   `cat ~/.local/state/stream-mode/target.json`.

### Which process is Steam capturing?

```sh
grep -E 'GameOverlay_MovieStream|Changing record window' ~/.steam/steam/logs/streaming_log.txt | tail -3
grep -E 'adding PID|no longer tracking' ~/.steam/steam/logs/gameprocess_log.txt | tail
```

Take the pid from `GameOverlay_MovieStream_<pid>` and check it is alive
(`ls /proc/<pid>`). A dead pid means a short-lived helper (an anti-cheat, a
launcher) registered the window first, and Steam never re-binds. Identify it
with a process logger during launch. Short-lived processes are gone before you
can look.

`Changing record window: (nil)` means the game window is not on `:0` at all.
It is probably inside gamescope.

### Which window has focus?

```sh
niri msg windows            # look for "(focused)" and the game's app id
DISPLAY=:0 xprop -root _NET_ACTIVE_WINDOW
```

Steam records `:0`'s active window. If that is a small, untitled window with
the game's app id, a helper window has focus, often Wine's tray window. If
focus keeps moving back after you change it, steam-stream-mode is re-asserting
it: `systemctl --user stop steam-stream-mode` while you investigate. A
`just switch` starts it again.

### `GAMESCOPE_*` atoms on the host display

```sh
DISPLAY=:0 xprop -root | grep GAMESCOPE
```

Any output means Steam will act as if it runs inside gamescope. stream-mode
clears these at stream start. By hand:
`DISPLAY=:0 xprop -root -remove <ATOM>`.

### Is the current extest loaded?

```sh
nix-store -qR /run/current-system | grep extest
tr '\0' '\n' < /proc/$(pgrep -x steam)/environ | grep -o '[^:]*extest[^:]*'
```

The two store paths must match. Steam reads `LD_PRELOAD` once, at start.
**After a switch, fully restart Steam** or it keeps the old build. On
2026-09-23 a whole evening of testing ran against a stale extest because of
this.

### What input is actually arriving?

```sh
nix shell nixpkgs#evtest --command evtest /dev/input/eventN > capture.log
```

Find `N` from `evtest`'s device list ("extest fake device"). Your user needs
the `input` group. extest rebuilds the device when outputs change, so re-check
the node after the virtual output appears.

Reading the capture:

- Absolute and relative events together: Steam sent positions, and extest
  derived motion from them. That is desktop mode.
- Relative events only: real relative motion from a game-mode stream.
- **Measure dwell time, not event count.** The kernel drops an absolute event
  that repeats the last value, so a position pinned at an edge produces no
  events at all. 66 events can hide 12 seconds of silence.
- **Analyse a copy, not a file still being written**, and say where a test
  window starts and ends. A capture that keeps growing makes "the log ends
  here" meaningless.

### Is niri's config actually loaded?

```sh
niri validate -c ~/.config/niri/config.kdl
```

If it fails, niri is running an older config and ignoring every change since.
See [0010](adr/0010-niri-config-kdl.md).

## Reaching the desktop with no screen

When DP-2 is off and you only have SSH, the virtual output can be shared over
VNC. Turn the output on if it is off, then:

```sh
export WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000
nix shell nixpkgs#wayvnc --command wayvnc -o steam -r localhost
```

Tunnel `5900` over SSH and use TigerVNC. Traps:

- `-w` means websocket, not "no auth". A plain VNC client hangs on connect.
- `-a` (all outputs) crashes when no output is enabled.
- `NIRI_SOCKET` in an old shell can point at a niri that no longer exists. Find
  the live one with `pgrep -af 'niri --session'`.
- Size the output to the viewer's screen (`niri msg output steam custom-mode 1440x900@60`)
  rather than scaling in the client. TigerVNC 1.16 has no scaling option.
- The Super key only reaches niri from TigerVNC in fullscreen, and not
  reliably on macOS. `niri msg action ...` over SSH is the dependable way to
  move focus.

## Habits that saved time

- Change one thing per test, and restart Steam when the change is in its
  environment.
- A log line that appears once proves a code path is reachable, not that it
  runs. The single `XTestFakeRelativeMotionEvent` line in a desktop-mode
  session was a stray call, not evidence of relative motion.
- When a theory survives two tests but the symptom does not change, look one
  layer up. The camera fault was never in the input path. It was the stream
  mode.
