# 0053. Tag game audio streams for OBS instead of routing them through a sink

- Status: Accepted, pending live test
- Date: 2026-10-26

## Context

OBS's default "Desktop Audio" slot (`DesktopAudioDevice1`, source
`pulse_output_capture`, `device_id: default`) records the monitor of the default
sink. On ali-desktop the default sink is `effect_input.binaural71`, which every
application plays into, so stream audio carried Zen and everything else, not
just the game.

OBS's Application Audio Capture (`obs-pipewire-audio-capture`) records only the
streams that match a name. It matches `node.name`, `application.process.binary`
or `application.name`. Games name their streams after themselves (`Cyberpunk
2077`, with no binary set), so a fixed target would need editing per game.

## Decision

Launch games with `PULSE_PROP_OVERRIDE="application.name=obs-game"` through
`programs.steamCommandRunner.innerEnv`, and declare the OBS Desktop Audio slot
as an application audio capture with `TargetName = "obs-game"`
(`sceneCollections.<c>.audioSlots`).

libpulse applies the override to the context, so pipewire-pulse names the
stream `obs-game`. Checked on 2026-10-26 with `pacat`: `node.name` became
`obs-game`. Proton's winepulse links libpulse, so it should do the same; that
has not yet been seen in a real game.

## Alternatives rejected

- **A `game` null sink with a loopback to the binaural sink.** Games would play
  to the null sink (`PULSE_SINK`) and OBS would capture its monitor. It needs an
  8-channel sink and loopback so games keep negotiating 7.1, and it moves the
  games' links away from the sink that `binauralLinks`, `relinkPorts` and
  `expectedLinks` pin. `PULSE_SINK` would also override steam-stream-mode's
  relink to the Remote Play sinks.
- **One OBS source per game, matched by name.** Needs an edit for each new
  game.
- **Capture `effect_input.binaural71.monitor`.** Same as the default: it holds
  every application.

## Consequences

- Only games launched through steam-command-runner are captured. Anything
  started outside it is silent on stream.
- Every tagged game appears as `obs-game` in mixers and EasyEffects. No rule in
  this repo matches on those properties.
- Discord and music no longer reach the stream. Mic/Aux is unchanged.
- A game already running when this lands keeps its own name until relaunched;
  pick its stream by hand in OBS meanwhile.
- The activation patch replaces the slot's settings on every switch, so a hand
  picked `TargetName` does not survive one. OBS also rewrites its config on
  exit, so restart it after a switch.

## Evidence

- `pw-dump` while `PULSE_PROP_OVERRIDE="application.name=obs-game" pacat
  --playback` ran: `node.name = obs-game`.
- `strings` on `linux-pipewire-audio.so` (1.2.1) lists `node.name`,
  `application.process.binary` and `application.name` as the matched
  properties.

## Revisit when

A real game launched with the tag shows no `obs-game` stream in `pw-dump`, or
OBS's Game Audio stays silent while one is playing. Then override
`application.process.binary` as well, or fall back to the sink design above.
