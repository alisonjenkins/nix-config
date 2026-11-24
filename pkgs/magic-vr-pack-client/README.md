# magic-vr-pack

Magic-focused Minecraft 1.21.1 pack on NeoForge, with VR support through Vivecraft.

## Install

1. Import this zip in Prism Launcher (`Add Instance` → `Import`) or the CurseForge launcher.
2. Set the JVM arguments in `JVM-ARGS.md`. Java 21.0.13.1+ is required.
3. Launch once without VR to check the pack loads.

## VR

- Vivecraft runs in VR when SteamVR (or another OpenXR runtime) is running at launch.
- Without a headset, the game starts in normal desktop mode.
- The pack pre-sets faster seated-mode turning and a yellow crosshair that turns red on hit.

## Shaders

- Iris, Complementary Reimagined and Euphoria Patches are included.
- Euphoria Patcher builds a patched copy of Complementary on first launch.
- Shaders start off. Turn them on in `Options` → `Video Settings` → `Shader Packs`.
- Shaders cost a lot of frame time in VR. Try them on desktop first.

## Config shipped in `overrides/config/`

- `DistantHorizons.toml`: GPU upload mode that works on Apple Silicon; LODs hidden behind cave ceilings.
- `vivecraft-client-config.json`: seated-mode turning speed.
- `colered-crosshair.json`: crosshair colours (the file name copies the mod's spelling).
- `ftbquests/`: the quest book (Archmage Veyla's guide), the same one the server ships.

The list of mods is in `modlist.html`.
