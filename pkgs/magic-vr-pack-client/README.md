# magic-vr-pack

Magic-focused Minecraft 1.21.1 pack on NeoForge, with VR support through Vivecraft.

## Install

1. Import this zip in Prism Launcher (`Add Instance` → `Import`) or the CurseForge launcher.
2. Set the JVM arguments in `JVM-ARGS.md`. Java 21.0.13.1+ is required.
3. Launch once without VR to check the pack loads.

## VR

1. Start SteamVR, or another OpenVR-compatible runtime, before the game.
2. Launch the pack. It starts in desktop mode.
3. Click the VR button on the title screen to switch to VR. Vivecraft remembers the choice.

- Without a headset, the game stays in desktop mode.
- The pack pre-sets faster seated-mode turning and a yellow crosshair that turns red on hit.

## Shaders

- Iris, Complementary Reimagined and Euphoria Patches are included.
- Euphoria Patcher builds a patched copy of Complementary on first launch.
- Shaders start off. Turn them on in `Options` → `Video Settings` → `Shader Packs`.
- Shaders cost a lot of frame time in VR. Try them on desktop first.

## Defaults that keep your changes

Default Options copies `config/defaultoptions/` into place on launch, but only where you have no file yet.
Pack updates never overwrite your own settings.

- `servers.dat`: the multiplayer list starts with Magic VR Pack (`magic.alison-jenkins.com`).
- `options.txt`: render distance 8, simulation distance 6, GUI scale 3, first-run tutorial screens skipped.
- `extra/config/iris.properties`: Complementary Reimagined selected, shaders off.
- `extra/config/DistantHorizons.toml`: LODs hidden behind cave ceilings.
- `extra/config/vivecraft-client-config.json`: seated-mode turning speed.
- `extra/config/colered-crosshair.json`: crosshair colours (the file name copies the mod's spelling).

To get a default back, delete your own copy of that file in the instance folder and relaunch.

## Config the pack owns in `overrides/config/`

Updates replace these.

- `ftbquests/`: the quest book (Archmage Veyla's guide), the same one the server ships.
- `l2configs/l2hostility-server.toml`: L2 Hostility with per-section difficulty off (`allowSectionDifficulty = false`), the same file the server ships.

## L2 Hostility difficulty

- Mob level still grows with your own kills, distance from spawn and the dimension.
- Killing many mobs in one area no longer makes that area harder.
- A Hostility Orb still clears the sections around it, and cleared sections stay safe.

### Existing worlds and servers

The file only reaches new installs.
The server copies `config/` into its data volume once, when the volume has no `config/` yet, so a running server keeps its old file.

1. Copy `overrides/config/l2configs/l2hostility-server.toml` from this zip (or from the server image's `/opt/server/config/l2configs/`) over the same path on the server's data volume, or in the instance folder for single-player.
2. Restart the server or the game.

## Chat on restricted accounts

No Chat Restrictions (client only) lets accounts that Microsoft has blocked from chat, for example UK accounts without an age check, use text chat.

- It turns on the account's chat, multiplayer and Realms permissions inside the game client.
- It skips the client's name-ban check.
- Telemetry and the Microsoft profanity filter stay off by default.
- Blocked players and chat reporting still work as normal.
- Change these in `config/NoChatRestrictions.json`.

The list of mods is in `modlist.html`.
