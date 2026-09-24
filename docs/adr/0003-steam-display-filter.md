# 0003. Correct Steam's desktop geometry in SDL, not X

- Status: Accepted
- Date: 2026-08-25 (recorded 2026-09-24)

## Context

Even with a correctly sized output to capture ([0002](0002-virtual-output-for-remote-play.md)),
Steam sized the encoder wrong. It uses its own idea of the desktop, not the
size of the PipeWire stream the portal hands it. That idea comes from SDL3:
`steamui.so` calls `SDL_GetDisplays(NULL)`, walks the NULL-terminated array
calling `SDL_GetDisplayBounds` on each display, and unions them. With the
ultrawide and the virtual output both present, the union is the ultrawide.

Two faults gave one symptom, so fixing either alone changed nothing visible.
That is why this took several wrong turns.

## Decision

`pkgs/steam-display-filter` is an `LD_PRELOAD` shim hooking exactly
`SDL_GetDisplays` and `SDL_GetDisplayBounds`. While a stream target is
published it presents one display, sized to the target, at the origin.
Otherwise every hook falls straight through to real SDL.

Properties that are easy to break:

- **It terminates the array, not just the count.** Steam passes `NULL` for the
  count. Shortening only the count has no effect on the routine that decides
  the geometry.
- **It acts only in the Steam client** (`/proc/self/exe` basename `steam` or
  `steamwebhelper`). Games, Proton and gamescope inherit the `LD_PRELOAD` and
  it stays inert in them.
- **It is built for both architectures** and loaded through `$LIB`, so 32-bit
  and 64-bit Steam processes each get their own build.

## Alternatives rejected

- **Hook X11 or RandR.** Steam's display code imports every RandR entry point,
  so the imports show what is linked, not what is called. Two interception
  points were shipped there before it became clear Steam asks SDL.
- **Test with a probe that `dlopen`s SDL.** A handle-scoped `dlsym` bypasses
  `LD_PRELOAD`, so the probe reports "unfiltered" however well the filter
  works. `steamui.so` has `DT_NEEDED libSDL3.so.0` and calls through the PLT,
  which the preload does interpose. `sdl_probe.c` tests it the right way.

## Consequences

- Nothing in the filter is compositor-specific.
  `STEAM_STREAM_SIZE=1280x800` alone arms it, on any compositor.
- Testing needs two outputs present. With one output there is nothing to
  filter and every probe passes.

## Evidence

`docs/steam-remote-play-streaming.md`, "The SDL filter" and "Testing without
fooling yourself".

## Revisit when

Steam sizes the encoder from the capture stream, or stops using SDL3 for
display geometry.
