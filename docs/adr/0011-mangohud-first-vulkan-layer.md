# 0011. Put MangoHud first in the Vulkan layer chain

- Status: Accepted
- Date: 2026-09-24

## Context

Once games streamed in game mode ([0007](0007-remote-play-game-mode.md)),
MangoHud was visible on the host screen but missing from the Remote Play
stream.

Steam's game capture (`Capture method set to Game Vulkan ...`) grabs each
frame inside the Steam overlay's Vulkan layer, at present time. MangoHud draws
its HUD into the frame in its own layer. Whichever layer is nearer the
application sees the frame first. Inside Steam's pressure-vessel container,
implicit layers are renamed to numbered manifests and chained in that order:

```
03-x86_64-linux-gnu.json  VK_LAYER_VALVE_steam_overlay_64
09-x86_64-linux-gnu.json  VK_LAYER_MANGOHUD_overlay_64_x86_64
```

So Steam captured each frame before MangoHud drew on it. Streams under
gamescope had shown MangoHud only because they were desktop captures of the
whole screen.

## Decision

`custom.mangohud.firstVulkanLayer`, enabled on ali-desktop, writes a Vulkan
loader settings file,
`~/.config/vulkan/loader_settings.d/vk_loader_settings.json`, listing the
64-bit and 32-bit MangoHud layers first and every other layer after them
(`{"control": "unordered_layer_location"}`). The loader then puts MangoHud
nearest the application, so it draws before Steam captures.

- `control: "auto"` keeps MangoHud's own rule: it is only active with
  `MANGOHUD=1`.
- Each entry needs a manifest `path` (loader source, `loader/settings.c`). The
  path is MangoHud's host manifest in `/nix/store`, generated from the same
  `pkgs.mangohud` the system installs, so it cannot go stale on an update.
  pressure-vessel's numbered copies change between launches and cannot be
  referenced.
- The container can read the file: it sits under `$HOME`, and the game uses
  the host's Vulkan loader, 1.4.341, which supports settings files.

## Alternatives rejected

- **`VK_INSTANCE_LAYERS`.** Explicitly enabled layers go after all implicit
  layers, further from the application than Steam's overlay. Wrong direction.
- **Renaming manifests to change discovery order.** pressure-vessel renumbers
  them itself, in an order we do not control.
- **MangoHud on the host only.** That was the state before this change.

## Consequences

- The file applies to every Vulkan application for this user, not just
  games. It only changes position, and MangoHud stays off without
  `MANGOHUD=1`.
- The loader logs that it read the file. Check with
  `VK_LOADER_DEBUG=layer vulkaninfo --summary`, and look for
  `Using layer configurations found in loader settings`. The layer inserted
  **last** is the one nearest the application.

## Evidence

With the file in place, MangoHud appeared in the stream on the Mac client.
`VK_LOADER_DEBUG=layer` shows the order flip: without the file MangoHud is
inserted first (nearest the driver); with it, last (nearest the application).

## Revisit when

Steam's capture moves to a point after every layer (for example a compositor
capture), or MangoHud changes its layer names.
