# Remote Play input routing through extest — design

- Date: 2026-09-23
- Host: `ali-desktop` (niri 02fdd8e + `patches/niri-virtual-outputs.patch`,
  DP-2 5120x1440 + `steam` virtual output, gamescope Wayland backend with
  `--force-grab-cursor`)
- Client: `ali-mba` (macOS, panel varies — 2880x1800 observed)
- Supersedes the axis-calibration approach in the first cut of
  `patches/extest-remote-play-relative-motion.patch` (PR #364/#365/#368
  before this doc), which was tested live and found insufficient

## 1. Problem

Two symptoms streaming Helldivers 2 from `ali-desktop` to `ali-mba` over
Steam Remote Play:

1. Mouse clicks/positions land on DP-2's desktop windows instead of the
   game, which runs on the `steam` virtual output.
2. In-game camera look (mouse look) does not work at all, or only
   intermittently.

## 2. What has been established (evidence, not assumptions)

Steam Remote Play's input path never touches `xdg-desktop-portal`'s
`RemoteDesktop` interface (checked earlier: no restore-token entries for it,
no D-Bus traffic on it). It goes through the legacy X11 XTEST protocol,
intercepted by `extest` (github.com/Supreeeme/extest, pinned version 1.0.2,
`evdev = "0.12.1"`, `wayland-client = "0.30.2"`), which turns `XTestFake*`
calls into a synthetic `uinput` device. This mechanism already existed in
this host's config for an unrelated reason (Steam Controller
trackpad-as-mouse on Wayland).

**libinput normalizes an absolute device's declared axis range away before
niri ever sees a value.** `absinfo_scale_axis()` computes
`(v - min) * W / (max - min + 1)` — only the *ratio* `v/range` survives, not
the range's magnitude (`libinput/src/util-input-event.h:93`).

**niri never maps a libinput absolute-pointer device to a specific
output.** `NiriInputDevice::output()` returns `None` unconditionally for
every `libinput::Device`, with niri's own comment:

```rust
// FIXME: Allow specifying the output per-device?
impl NiriInputDevice for libinput::Device {
    fn output(&self, _state: &State) -> Option<Output> {
        None
    }
}
```

(`niri/src/input/backend_ext.rs:19-30`, confirmed by reading the pinned
source directly, not from documentation.)

**`on_pointer_motion_absolute` therefore always falls back to the bounding
rectangle of every enabled output:**

```rust
let Some(pos) = self.compute_absolute_location(&event, None).or_else(|| {
    self.global_bounding_rectangle().map(|output_geo| {
        event.position_transformed(output_geo.size) + output_geo.loc.to_f64()
    })
}) else { return };
```

(`niri/src/input/mod.rs:2690-2696`; `global_bounding_rectangle` merges every
output's geometry, `niri/src/input/mod.rs:293-303`.)

**Consequence:** calibrating extest's declared axis range to the *target
output's own size* — the first cut of this patch — changes what *fraction*
of the streamed area lands across the whole desktop. It does not stop
positions from landing outside the target output, because the declared
range's magnitude is normalized away by libinput before niri applies it to
the bounding box of *every* output. This was tested live: it looked "a bit
better" (a smaller fraction of clicks hit DP-2) rather than cleanly wrong,
which is a worse outcome than a clean failure — it can look like partial
progress while validating the wrong model.

**The only way to land a position on a specific output is to compute that
output's actual place in the whole layout and emit already-global
coordinates** — which needs every output's position and size, not just the
target's.

**uinput has no API to change a live device's declared axis range.**
Checked directly in the pinned `evdev` 0.12.1 crate source: `VirtualDevice`
exposes no `set_abs`/update method; `UI_ABS_SETUP` only applies before
`UI_DEV_CREATE`. The device has to be dropped and recreated whenever the
axis range needs to change.

**Steam's `steamclient.so` imports both `XTestFakeMotionEvent` and
`XTestFakeRelativeMotionEvent`, and has `k_EMouseModeRelative` /
`CRelativeMouseMode` strings.** Whether Remote Play ever actually calls the
relative one for this game/session was never measured — the earlier
inference ("camera didn't move before this patch, so Steam must not call
it") is fully explained by absolute positions landing on the wrong output
instead, so it isn't evidence about which XTest entry point Steam uses.
Now instrumented (§5) instead of assumed.

**The target virtual output is toggled on/off between sessions, not just
resized.** `home/programs/linux-only/steam-stream-mode/stream_mode.py`
enables/disables it on connect/disconnect, which niri implements as
adding/removing the `wl_output` global outright — a watcher has to handle
`wl_registry`'s `GlobalRemove` correctly, not just `LogicalSize` changes.

## 3. Goals / non-goals

**Goal:** with `steam` enabled at size `W×H` at some global position
`(X, Y)` within the current output layout, an `XTestFakeMotionEvent(x, y)`
with `x` in `[0, W)`, `y` in `[0, H)` puts the niri pointer at exactly
`(X + x, Y + y)`, regardless of DP-2's own position/size or which output
niri's auto-placement happened to put `steam` at.

**Non-goal:** changing niri or gamescope. Both are patched/configured
already; a third niri patch for this (implementing the `backend_ext.rs`
FIXME properly, i.e. per-device output targeting) is a legitimate
alternative (§7) but needs a niri restart per iteration, which this design
avoids entirely — extest-only changes only ever need a Steam restart.

**Non-goal (for now):** guaranteeing correct behaviour with a real host
mouse cursor moving independently while a Remote Play session is active
(out of scope; this design assumes Steam is the only source of pointer
motion during a session).

## 4. Design

### 4a. Global-coordinate absolute mapping

`src/wayland.rs`'s `watch_layout` tracks **every** output's `xdg_output`
`LogicalPosition` and `LogicalSize` (not just the target's), keyed by
`ObjectId`, plus `wl_registry`'s `GlobalRemove` (via a `name → ObjectId`
map, since `GlobalRemove` only gives the numeric registry name). On any
change, it recomputes:

- `bbox`: the merge of every output whose geometry is fully known (`Rect`
  arithmetic mirrors niri's own `Rectangle::merge` — same
  min-corner/max-corner logic `global_bounding_rectangle` relies on).
- `target`: the named output's own `Rect`, if it currently exists.

and calls back with a `LayoutUpdate { bbox, target }` only when that pair
actually changes (deduplicated).

`src/lib.rs`'s `DEVICE` Lazy spawns this watcher (only when
`EXTEST_TARGET_OUTPUT` is set) and, on each update:

- Rebuilds the uinput device (drop + recreate) **only when `bbox`'s size
  changed** — that's the only thing the declared `AbsInfo` range has to
  track, matching the identity-transform property: setting `min=0`,
  `max=bbox.width-1` makes libinput's scale-by-range a no-op, so extest can
  emit already-global values directly and have them survive niri's
  `position_transformed(bbox.size) + bbox.loc` unchanged in the fraction
  that matters (the `+bbox.loc` is niri's own addition, so extest only
  needs to emit `global - bbox.loc`, i.e. an offset from the bbox's own
  origin, which the `TargetMapping.offset_x/y` already is).
- Updates a separate `TargetMapping` (offset + clamp bounds) on *every*
  layout change regardless of whether the device was rebuilt — this is
  pure arithmetic per event, no uinput call, so it can't drop input the way
  a device swap can.

`XTestFakeMotionEvent` reads `TargetMapping` and, when present, maps
`(x, y)` to `(offset_x + clamp(x, 0, max_x), offset_y + clamp(y, 0, max_y))`
before building the uinput event. When `EXTEST_TARGET_OUTPUT` is unset, or
the target doesn't currently exist, `TargetMapping` is `None` and positions
are emitted unchanged — byte-for-byte the same as extest's original,
non-Remote-Play behaviour (Steam Controller trackpad-as-mouse on the real
monitor), which this patch must not affect.

### 4b. Relative-motion synthesis (unchanged from the prior cut)

`XTestFakeMotionEvent` still derives a `REL_X`/`REL_Y` delta from
consecutive (now already-mapped) absolute positions and emits it alongside
the `ABS_X`/`ABS_Y` pair, since the pointer-lock path niri/gamescope use for
camera look only ever originates from real relative libinput events —
verified in the trace (§2, niri's `on_pointer_motion_absolute` never calls
`relative_motion`; gamescope's `Wayland_Pointer_Motion` discards host
absolute motion outright while a relative-pointer lock is active). This is
still gated behind the untested assumption that Steam doesn't also call the
real `XTestFakeRelativeMotionEvent` — see §5's instrumentation.

### 4c. Config

`flake-modules/hosts/ali-desktop/default.nix`: DP-2's `extraOutputs` KDL
block now pins `position x=0 y=0`, so the bounding box's origin is
deterministic instead of depending on niri's EDID-make-string
auto-placement ordering (`niri-config/src/output.rs`'s `OutputName::compare`)
reshuffling it. `steam`'s own position is left to niri's placement (it's
irrelevant to correctness — the mapping reads the *actual* position off
`xdg_output`, wherever niri puts it — pinning DP-2 alone is enough to make
the whole bbox deterministic for debugging).

## 5. Observability

`XTestFakeRelativeMotionEvent` now logs (once, to stderr — reaches the
journal via Steam's own process) the first time it's actually called,
settling whether Steam uses it at all for this session. `watch_layout`
already logs (stderr) when `zxdg_output_manager_v1` isn't advertised at
all, and every Wayland/dispatch error. This is deliberately lightweight
(no new log file, no `EXTEST_LOG` env var) — the existing
`STEAM_DISPLAY_FILTER_LOG`/`streaming_log.txt`/journal are enough to
correlate against if the next live test needs closer inspection; a
dedicated structured log is easy to add on top if that turns out not to be
enough.

For the next live session, in addition to those logs:

- `niri msg --json outputs` before/during the stream gives `bbox` and
  `steam`'s actual position/size directly, to compare against what extest
  computed.
- Raw evdev capture from the extest device (`libinput record
  /dev/input/eventN`, or the hand-rolled Python `struct` reader used
  earlier this session if `libinput`/`evtest` aren't installed) shows the
  actual `ABS_X`/`ABS_Y`/`REL_X`/`REL_Y` values emitted, to check they land
  in `[bbox.x, bbox.x+bbox.width)` and specifically within `steam`'s own
  sub-range.

## 6. Test-driven development

`patches/extest-remote-play-relative-motion.patch` now carries
`#[cfg(test)]` unit tests in both `wayland.rs` (the `Rect::merge` bounding-
box arithmetic, including the case observed live this session — DP-2 at
`(0,0)` 5120x1440 merged with `steam` at `(5120,0)` 2880x1800) and `lib.rs`
(the offset+clamp mapping: an output's own origin maps to its own global
position, its bottom-right corner stays within its own bounds, out-of-range
local input clamps rather than spilling onto a neighbouring output, and no
target configured means no mapping at all). `flake-modules/hosts/ali-desktop/default.nix`
sets `doCheck = true` on the patched `extest` derivation so `nix build`
runs them — `cargo test` inside the sandbox, no live Wayland connection
needed, confirmed via `nix log` showing `test result: ok. 6 passed`.

This is necessarily partial: the pure offset/clamp/merge arithmetic is
covered, but whether niri's *actual* `on_pointer_motion_absolute` fallback
really does what its source says, and whether a device rebuild is clean
from libinput's/Xwayland's perspective, can only be checked live (a nested
niri instance has one output and no libinput seat, and the
`niri-virtual-outputs.patch` itself notes virtual outputs are unsupported
under the winit backend — see the 2026-08-25 design doc §5b's own
limitation).

## 7. Risks / open questions

- Whether Steam calls `XTestFakeRelativeMotionEvent` for this
  client/game/session at all is still unmeasured — §5 settles it on the
  next live attempt. If it does, the synthesized delta in §4b would double
  up with it; nothing in this cut auto-disables the synthesis in that case.
- If the host is never in a relative-cursor mode Steam-side, an absolute-
  only stream would still hit the macOS client's own screen edge and stop
  producing further motion in that direction ("invisible wall") even once
  routing is otherwise correct. Unconfirmed either way; watch for it in the
  live test.
- niri's default hot corner (1×1 logical pixel, top-left of *every*
  output) toggles the overview when the pointer parks there
  (`niri/src/niri.rs:3207-3240`, checked inside the same absolute-motion
  handler). Once routing is correct, a Remote Play cursor sitting in
  `steam`'s top-left corner would trigger it. Not mitigated in this cut —
  no `hot-corners` option exists in `home/programs/linux-only/niri/module.nix`
  yet, and adding one is out of scope here; if this bites live, it's a
  one-line `niri msg` runtime check away from confirming, and a small
  follow-up module option away from fixing properly.
- A device rebuild (bbox size change) drops whatever `ABS`/`REL` events
  extest tries to emit in the window between the old device closing and
  the new one being open and picked up by libinput — expected to be tens
  of milliseconds, unconfirmed how it feels live (one dropped mouse
  position right as a stream starts or `steam` resizes, most likely).

## 8. Order of work

1. Redesign extest's mapping (this doc, done).
2. Unit tests + `doCheck = true` (done, `nix log` confirms 6/6 pass).
3. Pin DP-2's position (done).
4. `just switch`, restart Steam (no niri restart needed — extest is loaded
   per-Steam-process).
5. Live test: reattempt Remote Play + Helldivers 2, check the journal for
   the `XTestFakeRelativeMotionEvent` diagnostic, compare `niri msg outputs`
   against where clicks actually land, check camera look.
6. If §7's hot-corner or hit-a-wall risks show up, they're small, scoped
   follow-ups, not a sign the mapping design itself is wrong.
