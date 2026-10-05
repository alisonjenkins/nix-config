# 0015. Stream audio through a positioned sink, chosen per client

- Status: Accepted
- Date: 2026-09-25

## Context

Voices were missing from Forza Horizon 6 over Remote Play. FH6 plays two
surround streams, 7.1.4 (12 channels) and 7.1, into Steam's
`steam-streaming-playback` sink, which is a null sink Steam creates with two
channels and no positions (`aux0,aux1`). PipeWire cannot place a centre
channel on unpositioned outputs, so it keeps channels 1 and 2 (front left and
right) and drops centre, LFE and surrounds. Dialogue is on the centre channel.

Measured in the 440 Hz band of what Steam captured, with FH6 running:

| Tone on | Into Steam's sink | Through a positioned stereo sink |
|---|---|---|
| nothing | 0.00062 | 0.0015 |
| front left | 0.0058 | 0.0059 |
| centre | 0.00089 (dropped) | 0.0059 (kept) |

Clients tell the host only their channel count (`audio channels = 2`,
`Opened audio device: ... channels=2`), never whether they are on headphones
or speakers.

## Decision

- `modules.desktop.pipewire.remotePlaySinks` installs two standalone PipeWire
  configs: `/etc/steam-remote-play/stereo.conf`, a loopback sink with FL/FR
  positions, and `binaural.conf`, the desktop's HRTF filter-chain (the same
  function builds both). Each output is pinned to Steam's sink with
  `target.object` and `node.dont-fallback`.
- stream-mode starts the client's one (`pipewire -c`) when Steam logs
  `Setting default.configured.audio.sink to {"name":"steam-streaming-playback"}`
  and moves the game's streams onto it: those already in Steam's sink, and
  while the stream runs, any belonging to the game (not its own output). It
  stops the process when the stream stops. It leaves the default sink as
  Steam set it. See "Amendment 2026-10-05" below for why.
- The mode comes from `custom.steamStreamMode.audio.clients` by client name,
  `audio.default` otherwise. ali-desktop streams binaural to `ali-mba`.
- `binauralSurround.outputGain` makes up the level the compensation EQ cuts:
  the binaural path measured 7.1 dB below the downmix with the same 7.1 pink
  noise, and +7 dB (2.24) matched it within 0.5 dB. It applies to the desktop
  sink too, which was too quiet with the Scarlett at full gain.

## Amendment 2026-10-05: no default-sink change, keep moving the game

HD2 streamed to `ali-mba` with no audio (`Signal levels: ---, ---` in
`streaming_log.txt` for the whole 05:38–05:43 stream). Two causes:

1. **Steam records the monitor of whatever becomes the default sink.** After
   stream-mode ran `pactl set-default-sink remote-play-binaural`, Steam logged
   `Clearing previous record stream` / `Recording on device
   remote-play-binaural.monitor`. That monitor is the filter chain's 8-channel
   input, before the HRTF, not the stereo output that plays into Steam's sink.
   Earlier streams recorded Steam's own sink after the same default change
   (`Sink remote-play-binaural is default` with no re-record, 2026-09-27
   11:01); apparently Steam had not yet listed the new sink then, which is an
   inference from the log, not something it states. It also left Steam
   restoring a default that no longer exists when the stream ended.
2. **A game launched after the stream starts is never moved.** The one-shot
   move at stream start found 0 streams (HD2 launched 3 s later), and
   WirePlumber's `stream-properties` pins `helldivers2.exe` to
   `easyeffects_sink`, so it never plays into Steam's sink either.

Now: the default stays Steam's, so Steam keeps recording
`steam-streaming-playback.monitor`. While the sink process runs, stream-mode
polls `pactl list sink-inputs` every `AUDIO_CHECK_INTERVAL` (1 s) and moves any
stream already in Steam's sink, plus any whose `application.process.id` is the
game's pid or a descendant of it (`Session.game_pid`, known once the window is
staged), onto the stream sink. Until the pid is known a pinned game still
plays at the desk.

Not verified live: that the audio client's process tree reaches the pid Steam
reports for the game. The log line `moved N game stream(s) to <sink>` says
whether it matched; if HD2 is silent and that line is missing, compare
`pactl -f json list sink-inputs` (`application.process.id`) against
`stream-mode: staged ... pid N`.

## Alternatives rejected

- **Declaring the sinks permanently in PipeWire's config.** WirePlumber
  remembers the sink a stream was moved to (`stream-properties`: FH6 was
  recorded against `stream-downmix` after one move). A permanent sink that
  leads nowhere outside a stream would then silence that game at the desk.
  Sinks that exist only while streaming leave the remembered target dangling,
  and WirePlumber falls back to the default.
- **A WirePlumber rule giving Steam's sink positions.** WirePlumber 0.5 rules
  apply to device monitors and client streams, not to a node another client
  creates with `support.null-audio-sink`.
- **Re-targeting the desktop binaural sink's output to Steam's sink.** The
  relink services (`audio-context-suspend`, `audio-usb-reconnect-heal`)
  restore its link to the Scarlett, so audio would go to both.
- **Detecting headphones.** The protocol carries no such field.

## Consequences

- Surround games stream with their centre, LFE and surrounds, as a downmix or
  binaurally.
- A client with more than two channels (a surround receiver) still gets a
  stereo sink. Untested: Steam's channel order for more than two unpositioned
  channels is unknown.
- A stream that starts while `/etc/steam-remote-play` is missing (before a
  switch) keeps Steam's sink and its dropped channels; stream-mode logs it.
- The desktop's binaural chain is 7 dB louder. Nothing limits it, so a very
  loud mix can clip at the Scarlett.

## Evidence

- `pactl list sinks` for Steam's sink: `Channel Map: aux0,aux1`.
- `pw-link -l`: FH6's two outputs linked to `playback_1`/`playback_2` only.
- The tone and pink-noise measurements above, 2026-09-25.
- Tests in `tests/test_stream_mode.py`: `TestStreamAudio`,
  `test_audio_follows_steams_sink_and_the_stream_end`.

## Revisit when

- Steam's streaming sink gains channel positions.
- A client reports more than two audio channels.
- WirePlumber can set properties on nodes created by other clients.
