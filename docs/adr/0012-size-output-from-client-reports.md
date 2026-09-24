# 0012. Size the streamed output from what the client reports

- Status: Accepted
- Date: 2026-09-24

## Context

stream-mode sizes the `steam` virtual output to the client. It learned that
size from the first `CLIENT: ... output size: WxH` line of a session and kept
it. For the MacBook client it learned `4470x1676`, about 2.67:1, on a 16:10
screen. Every stream after that ran at that shape, and games that follow the
display got a stretched aspect.

The first report is not the client's screen. It is our own output echoed
back. The client opens its window at the capture size and only then goes
fullscreen, so a session built at `4470x1676` reports `4470x1676` first and
learns it again. The loop never corrects itself. From `streaming_log.txt` on
2026-09-24:

```
08:12:47 CLIENT: Video size: 2880x1080, output size: 4470x1676, overlay size: 4470x1676
08:12:54 CLIENT: Video size: 2880x1080, output size: 2880x1080, overlay size: 2880x1080
08:12:56 CLIENT: Video size: 2880x1080, output size: 2880x1800, overlay size: 2880x1800
```

The echo held for 7 seconds and a transitional size for 2 before the real
fullscreen size, 2880x1800 physical pixels on a 1440x900 Retina display.

The client also sends its resolution limit when the stream starts, before
any of those:

```
Streaming started to ali-mba at 0.0.0.0:0, audio channels = 2, MTU = 1200
Maximum capture: 2880x1080 60.00 FPS
```

Steam scales its capture down to fit inside that box, keeping the host's
aspect: `4470x1676` became `>>> Capture resolution set to 2880x1080`,
`2232x1597` became `1510x1080`. Output pixels beyond the limit are rendered
and thrown away. I have not found where the client derives the limit. The
width matches the Mac's panel and 1080 looks like its streaming resolution
setting, but that is an inference.

## Decision

`home/programs/linux-only/steam-stream-mode/stream_mode.py`:

- Follows `output size` for the whole session instead of taking the first
  one. A new value is acted on only after it has held for
  `CLIENT_SIZE_SETTLE` (10 seconds), so the echo and the transition are
  skipped. A client window resized mid-stream is followed the same way.
- Reads `Maximum capture: WxH` and sizes the output to the client's shape
  fitted inside it, never scaled up, with even dimensions. For the Mac that
  is 2880x1800 fitted into 2880x1080: 1728x1080, 16:10.
- Runs the output at the frame rate in the same line (`60.00 FPS`), rounded
  to whole Hz for niri's custom mode. Before this it ran at the configured
  `refresh`, 90 Hz on ali-desktop, so a game following the display rendered
  frames a 60 FPS stream dropped. The configured value is now only the
  fallback for a client never seen before.
- Remembers `{"output": [w, h], "max_capture": [w, h], "refresh": hz}` per client in
  `clients.json`, so the next connect starts at the right size before the
  client has said anything. The older bare `[w, h]` entries are read as an
  output size with no limit, and are rewritten the first time the client
  settles.

Nothing is configured per client.

## Alternatives rejected

- **A per-client size in nix (`clientSizes.ali-mba = 1440x900`).** Written
  and thrown away before it was committed. It needs editing for every new
  device and every window size, and it is wrong the moment the client's
  settings change. The protocol already carries the answer.
- **Output at the client's full resolution (2880x1800).** Steam downscales
  to the limit anyway, so the extra pixels cost GPU time and are never seen.
- **Rejecting reports wider than the limit.** It would drop the 4470 echo,
  but it rests on the unproven guess that the limit's width is the client's
  screen width. A client with a lower limit would never be sized at all.
- **Learning the first report only when it differs from our output.** The
  echo matched, but the 2-second transitional size did not, and a first
  connect at the default size is echoed too.

## Consequences

- A new client runs at the default size for about 10 seconds after its
  window settles, then is resized once. Later connects start right.
- Each resize is a display change Steam re-negotiates capture on. That was
  seen working mid-session (`>>> Capture resolution set to 1510x1080`, then
  back), but a game already running may not follow a resize. See PENDING.md
  item 2.
- The first session after this change resizes the Mac once, from its stale
  `4470x1676` entry, and rewrites the entry.

## Evidence

- `grep -E 'Maximum capture|output size' ~/.steam/steam/logs/streaming_log*.txt`
- Tests in `tests/test_stream_mode.py`:
  `test_a_reported_size_waits_to_settle`,
  `test_learned_output_is_fitted_inside_the_resolution_limit`,
  `test_a_later_change_is_followed_too`,
  `test_a_legacy_entry_is_fitted_to_this_sessions_limit`.

## Revisit when

- A client's settled `output size` is not its window, for example a client
  that reports its screen while windowed.
- `Maximum capture` stops appearing, or appears after the first
  `output size`.
- 10 seconds proves too short: look for an echo still in `clients.json`
  after a session.
