# 0006. Map Remote Play input to global coordinates in extest

- Status: Accepted, pending live test of the multi-output case
- Date: 2026-09-23 (recorded 2026-09-24)

## Context

Steam injects Remote Play's mouse and keyboard input with the X11 XTEST
extension, on `:0`. On a Wayland session that goes to xwayland-satellite,
which cannot inject input into niri. `extest` is an `LD_PRELOAD` shim that
reimplements XTEST calls as a Linux uinput device. It is preloaded into the
32-bit Steam client, which is the process that makes the calls, so it is built
from `pkgsi686Linux`.

Upstream extest sizes its absolute axes to the largest output. Remote Play
clicks then landed on DP-2, not on the streamed output.

Two facts from source decide the design:

- **niri never maps an absolute device to one output.**
  `NiriInputDevice::output()` returns `None` for every libinput device, so an
  absolute position is scaled across the bounding box of *all* enabled
  outputs.
- **libinput scales an absolute axis by `(max - min + 1)`.** Only the ratio of
  the value to the declared range survives, not the range's size in pixels.

## Decision

`patches/extest-remote-play-relative-motion.patch`:

- A background Wayland connection watches every output's position and size
  (`watch_layout`).
- The uinput device's axes cover the bounding box of all outputs, with
  `max = size - 1` so positions map one to one. uinput cannot change an axis
  range on a live device, so the device is rebuilt when the box changes size.
- Each position from Steam, which is in the streamed output's own
  coordinates, is offset to that output's place in the box and clamped to its
  edges, so input can never spill onto a neighbouring output.
- The target output comes from `EXTEST_TARGET_OUTPUT`, derived from the one
  declared virtual output in nix, with an assertion that there is exactly one.
- `doCheck = true` runs the patch's unit tests during the build.

extest also derives relative motion from consecutive absolute positions. That
was meant to move the camera, but it cannot get past the edge of the client's
window ([0007](0007-remote-play-game-mode.md)). It is kept for desktop-mode
streams. In game mode Steam sends only real relative motion, so the derived
path never runs there.

## Alternatives rejected

- **Size the axes to the target output only.** This was the first fix. niri
  still scales across the whole bounding box, so positions landed in the wrong
  place anyway.
- **Calibrate once, at the first XTEST call.** That call comes from
  steamwebhelper long before a client connects, while the virtual output is
  still off.
- **Fix it in niri or gamescope.** niri has no concept of which output an
  absolute device belongs to (its own FIXME). gamescope drops absolute motion
  while it holds a pointer lock.

## Consequences

- DP-2's position is pinned in niri's config, so the layout is the same every
  session and logged coordinates are predictable. The mapping follows live
  geometry and does not depend on the pin.
- Only one virtual output is supported. The assertion fails the build if a
  second is added.

## Evidence

`docs/superpowers/specs/2026-09-23-remote-play-input-routing-design.md` has
the source citations. 7 unit tests pass in the build.

## Revisit when

niri learns to map absolute devices to one output, or Remote Play stops using
XTEST.
