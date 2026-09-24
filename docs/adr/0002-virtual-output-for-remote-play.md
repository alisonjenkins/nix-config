# 0002. Stream from a declared niri virtual output

- Status: Accepted
- Date: 2026-08-25 (recorded 2026-09-24)

## Context

Steam Remote Play captures a whole output. Its portal picker offers monitors
only, never a window. Streaming the 5120x1440 ultrawide to a 16:10 client
letterboxes the game into a sliver of the client's screen.

## Decision

niri is patched (`patches/niri-virtual-outputs.patch`) with a `virtual`
output kind. `custom.niri.virtualOutputs.steam` declares one in niri's config,
disabled. steam-stream-mode sets its mode to the client's size and enables it
when a client connects, and turns it off again once streaming has been idle.
The game workspace moves onto it for the stream.

Properties that matter, all in the patch or `home/programs/linux-only/niri/module.nix`:

- **A real physical size.** Upstream reports `0mm x 0mm` for virtual outputs,
  and Steam discards outputs of that size entirely. The patch derives
  millimetres from the mode at about 96 dpi.
- **`set-window-fullscreen` IPC**, which sets a state instead of toggling one.
  Upstream only has `fullscreen-window`, a toggle with no readable state, and
  inferring the state from geometry once took an already fullscreen game back
  out of fullscreen.
- **Hot corners off** on virtual outputs. The Remote Play cursor parks in a
  corner and kept opening the overview. Physical outputs keep theirs.

Gated behind `modules.desktop.niriVirtualOutputs`. When off, stock niri is
used.

## Alternatives rejected

- **Create and destroy the output over IPC for each stream.** This was the
  first design. It raced niri's own output handling and left outputs that kept
  their name but were unusable. Toggling a declared output is the same path as
  plugging in a monitor, and it came with that path's correctness.
- **Remove the output between streams.** Steam remembers its capture source
  and resolves it when a session starts. An output that came and went broke
  that request.
- **A maximised column (`set-column-width "100%"`) instead of fullscreen.** A
  column sits inside the working area, so noctalia's bar reserved 34px on the
  virtual output and a 1280x800 client got 1280x766 of game.

## Consequences

- The patch is generated from a fork branch (`git diff e9b215fe HEAD` on
  `rebase-feat-virtual`). Fixes go there as commits, then the patch is
  regenerated. Do not hand-edit it.
- Something on the host has to toggle the output. That is steam-stream-mode
  ([0005](0005-stream-mode-owns-stream-state.md)).

## Evidence

`docs/steam-remote-play-streaming.md` tells the full story. The 34px shortfall
was diagnosed from the loss being vertical only: gaps and borders cost width
too, a layer-shell exclusive zone does not.

## Revisit when

Remote Play gains window capture, or niri gains virtual outputs upstream.
