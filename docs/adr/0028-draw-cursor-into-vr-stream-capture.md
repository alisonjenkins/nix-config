# 0028. Draw the cursor into the capture during a Steam Link VR stream

- Status: Accepted, pending live test
- Date: 2026-10-04

## Context

A flat game shown in a Steam Link VR session ([0025](0025-steam-link-vr-stream-lifecycle.md))
had no mouse cursor in the headset.

Steam captures the `steam` output through niri's screencast and asks for the
cursor hidden. niri's journal, for every capture Steam started that day:

```
niri::dbus::mutter_screen_cast: record_monitor connector="steam" properties=RecordMonitorProperties { cursor_mode: Some(Hidden), ... }
```

That is right for Remote Play: Steam sends the cursor to the client separately
(`CLIENT: Got control packet k_EStreamControlSetCursor` in `streaming_log.txt`)
and the client draws it. SteamVR's desktop view shows the frames as they are
and draws nothing, so the headset never saw a cursor.

Windows users hit the same thing from SteamVR 2.13.5
([Steam thread](https://steamcommunity.com/app/250820/discussions/3/599666256597178710/)).
Their workaround, Windows' "Display pointer trails", works because it makes the
system paint the cursor into the screen image.

## Decision

The niri fork gains a per-output `embed-screencast-cursor`, also switchable at
runtime with `niri msg output <name> screencast-cursor on|off`. When it is on, a
cast of that output that asked for a hidden cursor gets it embedded instead.
stream-mode turns it on when a VR stream starts and again after a niri config
reload, which drops runtime output changes. It turns it off when the stream ends.

## Alternatives rejected

- **Embed the cursor in every cast of the `steam` output.** A Remote Play
  client in desktop mode draws its own cursor, so it would show two.
- **The game's own software cursor setting.** Per game, and most games do
  not have one.
- **Make Steam ask for an embedded cursor.** Steam chooses the mode and offers
  no setting for it.

## Consequences

- niri draws the pointer into an output cast only while the pointer is over
  that output. A VR stream qualifies, because the game only gets mouse input
  while the pointer is over its window there.
- stream-mode needs the fork's `screencast-cursor`. On a niri without it the
  call fails, stream-mode logs `could not turn the screencast cursor on`, and the
  stream carries on without a cursor.

## Evidence

- niri journal lines above; `pw-dump` of the cast node shows no cursor metadata.
- niri fork: `effective_cursor_mode` tests in `src/screencasting/pw_utils.rs`,
  `parse_embed_screencast_cursor` in `niri-config`.
- stream-mode tests: `test_a_vr_stream_draws_the_cursor_into_the_capture`,
  `test_a_stream_without_steamvr_leaves_the_cursor_alone`,
  `test_the_vr_stream_ending_stops_drawing_the_cursor`,
  `test_a_config_reload_mid_vr_stream_draws_the_cursor_again`.

## Revisit when

SteamVR draws the cursor itself, or Steam starts asking for an embedded or
metadata cursor.
