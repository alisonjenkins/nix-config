# 0013. Disarm on client disconnect, and never leave niri without an output

- Status: Accepted
- Date: 2026-09-24

## Context

stream-mode publishes the stream target when a client connects, so the shim
and the display filter are armed before anything launches. A 45-second
connect timeout withdrew it again if no stream started, meant for a client
that only browses and leaves.

On 2026-09-24 the Mac connected at 08:35:22 and browsed. The timeout withdrew
the target at 08:36:07. HD2 was launched from the client at about 08:36:26,
and a launch starts the game before `>>> Starting desktop stream`, so the
shim read no target and ran HD2 inside gamescope. Steam then logged
`Changing record window: (nil)`: the game was on gamescope's nested display,
out of reach of game capture ([0007](0007-remote-play-game-mode.md)).

The timeout's premise was that a client can leave without Steam logging it.
`remote_connections.txt` shows otherwise: every connect has a disconnect.

```
Client 11334438332915102515 (ali-mba) disconnected: ping timeout
Client 11334438332915102515 (ali-mba) disconnected: disconnecting all
Client 5182124125287412536 (ali-framework-laptop) disconnected: told us it was offline
```

`disconnecting all` is Steam shutting down.

## Decision

In `home/programs/linux-only/steam-stream-mode/stream_mode.py`:

- The target stays published while the client is connected. `disconnect()`
  withdraws it and turns the output off when the client's disconnect line
  arrives. Mid-stream it leaves that to the stop marker and its grace period.
- A Steam crash is the one way to lose a client with no disconnect line. The
  existing Steam-alive check now also runs while a client is connected.
- `end_stream()` leaves the output on when niri has no other active output.
- The `connectTimeout` option is removed.

## Alternatives rejected

- **A longer timeout.** Any value is a guess at how long someone browses.
- **Republishing the target on the launch line.** Steam spawns the launch
  chain, shim first, in the same millisecond it logs the process, so this
  would still race.

## Consequences

- A Steam shutdown now disarms and turns the output off. With the monitor
  off, that left niri with zero outputs. Steam restarted into that state
  fails with `DesktopLoginWindow_uid0: Failed to create fallback output
  window, bailing`, stays logged off and is invisible to every client. That
  is why the only-output guard ships in the same commit.
- "Connected" is not "streaming". A client whose Steam is merely open stays
  connected for hours: the Deck connected at 10:53 on 2026-09-24 and never
  logged a disconnect after its stream ended at 11:04. The target stays armed
  all that time, which is harmless for the display filter but would make a
  game started at the desk launch as if streamed. So the shim no longer
  trusts the file alone: it launches as streamed only when Steam sets
  `SteamStreaming=1` (runner ADR 0007), which it does for launches from a
  client.
- The output stays on while the monitor is off. Nothing else can use it then,
  so nothing is lost.
- niri drops every change made over IPC when it reloads its config, and
  re-applies the declared `off` and mode. A `just switch` that touched
  config.kdl turned the output off at 09:01 on 2026-09-24 and left niri with
  no outputs. stream-mode now reacts to niri's `ConfigLoaded` event by
  restoring the client's mode and turning the output back on, or keeping it
  on when it is the only output.
- Tying the target to the connection means a stream-mode restart must not
  forget the connection. Each `just switch` restarts it, and it follows the
  logs from their end, so at 09:07 on 2026-09-24 it started with no client
  while the Mac had been connected since 08:39. HD2, launched 18 seconds
  later, went through gamescope. On start it now adopts the latest client in
  `remote_connections.txt` with no disconnect after it, while Steam runs.

## Evidence

- `grep -E 'connected|disconnected' ~/.steam/steam/logs/remote_connections.txt`
- Tests: `test_a_client_disconnecting_before_streaming_disarms`,
  `test_a_disconnect_mid_stream_leaves_the_stop_marker_in_charge`,
  `test_steam_dying_with_a_client_connected_disarms`,
  `test_the_only_output_is_left_on`.

## Revisit when

- A target is found published with no client connected and Steam running:
  a disconnect Steam did not log.
