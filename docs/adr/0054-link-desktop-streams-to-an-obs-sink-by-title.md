# 0054. Link desktop streams to an OBS sink by title, not by app

- Status: Accepted, pending live test in OBS
- Date: 2026-10-26

## Context

The OBS "Desktop" scene records the whole desktop without voice chat. Discord
and Signal calls are separable by app, but Element Call runs in a browser tab,
and OBS's Application Audio Capture matches only `node.name`,
`application.process.binary` and `application.name` (read from
`pipewire-audio-capture-app.c`). Every tab shares the browser's values for
those.

What differs per tab is `media.name`, the tab title. Seen with `pw-dump` on
2026-10-26: `Element Call | General 1` for the call, `(1299) … - YouTube` for
videos, `Watch` for a Facebook tab. No PipeWire or WirePlumber rule renames a
stream by that property: `pulse.rules` match the client, which all tabs
share, and WirePlumber 0.5 has no stream rules.

## Decision

`custom.obsDesktopAudio` runs a user service (`obs-desktop-audio`) that creates
a null sink, `obs-desktop`, and watches `pw-dump --monitor`. For each playing
stream whose properties match no exclude rule, it adds a link from the
stream's output ports to the sink, FL to FL, FR to FR, MONO to both. OBS
records `obs-desktop.monitor` with an ordinary audio output capture. Rules
map a node property to a regex, so a title pattern works in any browser.

## Alternatives rejected

- **Exclude mode in Application Audio Capture.** Cannot see `media.name`;
  excluding `zen` removes YouTube and music along with the call.
- **Rename the stream with a rule.** Nothing in PipeWire or WirePlumber does
  it, see above.
- **Route calls to their own sink.** Moves the stream, so it changes what is
  heard and fights the pinned binaural and Remote Play links (ADR 0053).
- **Capture the default sink monitor.** Includes everything, calls too.

## Consequences

- Streams keep their normal links, so listening is unchanged and a crash of
  the service only stops the recording feed. Its links outlive it (pw-link
  links linger), so a stopped service leaves the last set in place until the
  sink is unloaded.
- A stream is linked only after something else has linked it. The session
  manager picks a new stream's target from its own links, and ours arriving
  first could leave it unconnected to the speakers.
- A tab retitled mid-stream changes side: links are added or removed on the
  next graph event.
- Surround channels with no stereo target (RL, RR, SL, SR, FC, LFE) are not
  summed in. A game's own audio is recorded by OBS's Game Audio slot, so the
  game is excluded here (`node.name = ^obs-game$`).
- Streams of EasyEffects, OBS and the binaural filter chain are always
  skipped; they carry a mix of the others and would put excluded audio back.
- Rules match the title at the time of the graph event. A call whose tab is
  not yet titled `Element Call` when its stream appears is recorded until the
  title changes.

## Evidence

- Live run on 2026-10-26 against a throwaway sink: a stream titled `plain tab`
  was linked, one titled `Element Call | test` was not, and the default sink
  stayed `effect_input.binaural71`.
- The planner is pure and covered by `tests/test_obs_desktop_audio.py`.

## Revisit when

OBS's Application Audio Capture can match on `media.name`, or WirePlumber gains
stream rules that can rewrite a node's name. Either replaces the service.
