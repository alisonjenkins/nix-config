# 0025. Start a Steam Link VR stream on desktop capture, end it when SteamVR exits

- Status: Accepted, pending live test
- Date: 2026-10-04

## Context

stream-mode only treats a session as a stream after Steam logs
`Streaming started to <client>`. Fullscreening the game on the `steam` output
and taking focus back both wait for that.

A Steam Link VR session (a Quest 2 here) never logs it. The headset sends a
streaming request, Steam starts SteamVR (app 250820), and SteamVR's vrlink
driver carries the session. A flat game shown in the headset only makes Steam
start desktop capture once the game has a window:

```
11:58:16 Streamed game has created a window
11:58:16 Bringing streamed game to foreground - failed
11:58:16 >>> Starting desktop stream
```

There was no `Streaming started to`, `>>> Stopped desktop stream` or
`PipeWire: Deinitializing streaming` for the rest of the session. stream-mode
connected the headset (`device connected; steam on at 1280x800`) and moved
Helldivers 2 to the output, but never fullscreened it. It sat at 616x734 on a
1280x800 output.

The game also went through gamescope, because the launch carried
`StreamForOpenVR=1` and not the `SteamStreaming=1` the shim looked for. That
half is steam-command-runner's
[0012](https://github.com/alisonjenkins/steam-command-runner/blob/main/docs/adr/0012-vr-streamed-games-skip-gamescope.md).

## Decision

`>>> Starting desktop stream` begins a stream when none is running and a client
is connected. If SteamVR's `vrserver` is running at that moment, the stream is a
VR one. The slow Steam-alive poll then also ends it once `vrserver` exits, and
forgets the client, so the headset's next streaming request connects again.

A VR stream runs the output at the refresh SteamVR agreed with the headset
(`vrlink: SendUpdatedFramerateRequest: Best client match 90.00 Hz` in
`vrserver.txt`), or 90 Hz when the log has none. The headset never reports a
refresh to Steam, so the output used to fall back to 60 Hz under a 90 Hz panel.
Each game frame then stayed up for one headset refresh, then two, and turning
to aim felt uneven.

Another client connecting during a VR stream is recorded but changes nothing.
Steam on an idle Mac reconnected mid-session and resized the output to its
1728x1080 at 60 Hz under the game.

## Alternatives rejected

- **Treat `>>> Starting/Stopped desktop stream` as the session markers for
  everyone.** Steam swaps between desktop and game capture several times in a
  Remote Play session. Read as the end, a swap tore the stream down (see the
  comment on `START_RE`). Here the line only starts a stream when none is
  running, so inside a Remote Play session it does nothing.
- **End on `Game Recording - game stopped [gameid=250820]`.** It is logged
  several times during every SteamVR start, as its helper processes come and
  go.
- **Publish a `live` flag in the target for the shim.** The desktop stream
  starts seven seconds after the launch decision (11:58:09 vs 11:58:16), so it
  is too late. The shim reads `StreamForOpenVR` instead.

## Consequences

- SteamVR left running after the headset is put down keeps the stream, and the
  `steam` output, up until it exits.
- A desktop capture with a client connected but no SteamVR also begins a
  stream. It ends the usual ways: the stop marker, a disconnect, or Steam
  exiting.
- A service restart in the middle of a VR session does not pick the stream back
  up: `stream_in_progress` looks only for Remote Play markers.

## Evidence

- `~/.steam/steam/logs/streaming_log.txt`, 2026-10-04 11:57-12:06: no
  `Streaming started to`; `>>> Starting desktop stream` at 11:58:16.
- `remote_connections.txt`, 11:57:37: `Received streaming request ... with
  device ID ...` and no `connected via` line.
- `driver_vrlink.txt`: `ReceivedHMDStaticProps. Model Number: Oculus Quest2`.
- stream-mode journal: `staged game (window 30, ...) on steam; now
  output=steam size=[616, 734]`, and no `fullscreening` line.
- Tests in `tests/test_stream_mode.py`:
  `test_a_desktop_stream_with_no_session_marker_starts_one`,
  `test_a_desktop_stream_inside_a_remote_play_session_is_ignored`,
  `test_a_vr_stream_ends_when_steamvr_exits`,
  `test_a_vr_stream_runs_the_output_at_the_headsets_rate`,
  `test_another_client_connecting_mid_vr_stream_leaves_the_output`.
- Second session, 12:47-13:05: `Best client match 90.00 Hz` in `vrserver.txt`
  while the output ran at 1280x800 and 60 Hz, then `ali-mba connected; steam on
  at 1728x1080` mid-game.

## Revisit when

Steam starts logging `Streaming started to` for Steam Link VR, or SteamVR
stays running between headset sessions often enough that the output staying up
gets in the way.
