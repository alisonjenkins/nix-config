# 0014. Re-announce Steam's virtual gamepads when Steam lists them

- Status: Accepted
- Date: 2026-09-24

## Context

After a Steam Deck reconnected to a running HD2, the camera worked and
nothing else did: no movement, no buttons. A relaunch fixed it, which is not
acceptable mid-mission.

The camera is mouse input. Movement and buttons go through a Steam virtual
gamepad, a uinput device named `Microsoft X-Box 360 pad N`. On a reconnect
Steam made a new one for the returning controller and left the old one in
place:

```
11:45:23  Microsoft X-Box 360 pad 1   event256   created at launch, held by the game
11:47:26  Microsoft X-Box 360 pad 0   event257   created at the reconnect, receives the input
```

Proton's `winedevice.exe` held `/dev/input/event256` and never opened
`event257`. It can hotplug: a test gamepad created with uinput was wrapped by
Steam and opened within seconds. The difference is Steam's list. The game's
SDL is told `SDL_GAMECONTROLLER_ALLOW_STEAM_VIRTUAL_GAMEPAD=1` and
`SteamVirtualGamepadInfo=.../config/virtualgamepadinfo.txt`, and only uses a
Steam virtual pad whose slot that file lists. SDL checks when the device
appears. On this reconnect Steam created `pad 0` first and listed slot 0
afterwards, so SDL rejected the pad and never looked at it again.

SDL also re-checks a device on `IN_ATTRIB` in `/dev/input`, because
permissions arrive after a node does. `touch /dev/input/event257` from the
user's shell made `winedevice.exe` open it, and the controls worked with no
relaunch.

## Decision

`home/programs/linux-only/steam-stream-mode/stream_mode.py` watches
`virtualgamepadinfo.txt` while a client is connected or streaming. When it
changes, it updates the timestamps of the uinput `pad N` nodes whose slot the
file lists and that no process has open (`check_gamepad_info`,
`device_in_use`). The node's uaccess ACL already gives the user write access;
no root is involved.

Only unopened pads, because a touched pad is added again even when Proton
already has it. The first version touched every listed pad; at 12:08 a
stream-mode restart touched the pad HD2 was using, `winedevice.exe` opened it
a second time, and the controls stopped. Only the game's `winedevice.exe`
holds these nodes, so a pad nothing has open is exactly the stranded one.

## Alternatives rejected

- **Relaunch the game.** Loses progress. The reason this exists.
- **A virtual gamepad of our own in front of Steam's**, forwarding from
  whichever pad is live, as InputPlumber does. It works for any game, but it
  is a second input stack to own for a race a timestamp resolves.
- **Removing the stale pad.** It belongs to Steam's uinput handle; nothing
  outside Steam can remove it.

## Consequences

- The file is polled by `stat` once a second while a client is connected.
- It relies on SDL's `IN_ATTRIB` handling and on Steam listing the pad at all.
  A game that reads gamepads without SDL, or a Proton without the inotify
  path, would not re-check.
- The underlying order (create, then list) is Steam's. This follows it rather
  than fixing it.

## Evidence

- Live 2026-09-24 11:47 to 11:52: `ls -l /proc/<winedevice>/fd` before and
  after the touch; controls restored in the running HD2.
- Tests: `TestVirtualGamepads` in `tests/test_stream_mode.py`.

## Revisit when

- A reconnect leaves the controls dead with the pad listed and touched: SDL no
  longer re-checks on `IN_ATTRIB`.
- Steam starts listing a pad before creating it, making this a no-op.
