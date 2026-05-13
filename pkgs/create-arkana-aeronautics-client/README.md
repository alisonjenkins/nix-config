# Create: Arkana + Aeronautics — client modpack

CurseForge-style import zip for the Arkana 1.5 + Aeronautics 1.2.1 floor on
Minecraft 1.21.1 NeoForge 21.1.228. Built reproducibly from nix-config at
[github.com/alisonjenkins/nix-config](https://github.com/alisonjenkins/nix-config).

## VR is a first-class citizen here

This pack treats VR via Vivecraft as a primary play mode, anticipating
players using Steam Frame headsets when they ship. Pre-baked client
configs aim to make the VR experience usable out of the box without
manual tweaks:

- **`darkmodeeverywhere-client.toml`** — extends DarkModeEverywhere's
  `METHOD_SHADER_BLACKLIST` to exclude vanilla GUI rendering + the
  Vivecraft render path. Otherwise the dark shader makes Vivecraft's
  3D GUI panel near-black + the pointer near-invisible.
- **`vivecraft-client-config.json`** — bumps the seated-mode mouse-edge
  rotation speeds to 2.0–2.5× Vivecraft's defaults. Without this, seated
  players have to repeatedly lift + reposition their mouse to turn
  around (Vivecraft's "keyhole" model only rotates the camera while the
  cursor is pressed against the screen edge, and the default 1.0×
  multiplier makes that very slow).

If a value isn't right for your setup, tweak in-game:

| Pain point | Fix |
|---|---|
| Turning is still too slow in seated VR | `VR Settings → Seated → Rotation Speed` slider (writes `xSensitivity`) |
| Pitch (look-up/down) feels off | `VR Settings → Seated → Y Sensitivity` |
| Standing-mode smooth-turn too slow | `VR Settings → Rotation → Rotation Speed` (writes `worldRotationXSensitivity`) |
| Main menu / inventory still dark | In-game `Dark Mode` cycle button bottom-left of main menu |

Players' in-game tweaks save back to `<instance>/config/vivecraft-client-config.json`
under the active profile and persist on subsequent launches.

## What's in the zip

| Path | What |
|---|---|
| `manifest.json` | CurseForge launcher manifest — list of mods to fetch by projectID/fileID |
| `modlist.html` | Human-readable mod list |
| `JVM-ARGS.md` | Recommended JVM args for the client (per-launcher steps inside) |
| `README.md` | This file |
| `overrides/mods/` | Modrinth-hosted mods + the JIJ-stripped ars_nouveau (CurseForge launcher won't fetch non-CF URLs from the manifest, so they ship here directly) |
| `overrides/openloader/data/` | Bundled datapacks (OpenLoader auto-loads them into every world) |
| `overrides/config/` | Pre-baked config overrides for known-issue mods |

## Pre-baked fixes shipped in this zip

### Distant Horizons — `glUploadMode = DATA`

`overrides/config/DistantHorizons.toml` pins the GL upload mode so M1/M2 Macs
don't crash on the GL 4.1 buffer-storage code path. DH merges this partial
TOML into its full default config on first run.

### Dark Mode Everywhere + Vivecraft (VR)

`overrides/config/darkmodeeverywhere-client.toml` extends
`METHOD_SHADER_BLACKLIST` to cover the whole vanilla GUI package plus the
Vivecraft render path.

**Why:** Dark Mode Everywhere intercepts a list of well-known GUI render
methods and applies its dark shader to the GUI texture before the rest of
the render pipeline continues. In VR, Vivecraft composites that
(already-dark) GUI texture onto a flat panel in 3D world space, leaving
text + pointer near-unreadable. Upstream's default blacklist exempts a
narrow set of classes by exact name (`TitleScreen`, `renderCrosshair`,
etc.) but not `AbstractWidget` / `Button` / other components that the
title screen and inventories draw via — so most of the GUI stayed dark.

Three additions to the upstream default list:

| Entry | Catches |
|---|---|
| `net.minecraft.client.gui` | Every vanilla Screen / button / widget / layout. Effectively disables DMME for vanilla GUI rendering — VR players see readable text + buttons on Vivecraft's 3D panel. |
| `org.vivecraft` | Vivecraft's own render path. |
| `vivecraft` | Loose modid-package fallback. |

Side effect: vanilla inventory / chest GUIs also stop being dark. Non-VR
players who specifically want the dark theme can remove the
`net.minecraft.client.gui` entry from the config or use the in-game
`Dark Mode` cycle button on the title screen to switch shader variants.

### EuphoriaPatcher 1.8.6 needs Complementary Reimagined r5.7.1

The pack's manifest pins the upstream-published Arkana 1.5 versions of both
mods so EuphoriaPatcher 1.8.6 finds the matching shaderpack base
(r5.7.1) at launch. The legacy `overrides/shaderpacks/Complementary
Reimagined_r5.5.1 + EuphoriaPatches_1.6.5/` directory still ships (Arkana
bakes a pre-patched copy) but goes unused — EuphoriaPatcher 1.8.6 produces
a fresh `... r5.7.1 + EuphoriaPatches_1.8.6/` directory on next launch.
Delete the legacy directory from `<instance>/shaderpacks/` to clean up.

### No-pixie-spam datapack — `rare-pixie-villages-1.0.zip`

Ice and Fire pixies cluster around pixie villages and steal items from
player inventories on contact. The mod's `PixieConfig` only exposes
`size` + `stealItems` (no spawn-rate knob), but the underlying density is
driven by how dense the `pixie_village` structure_set is — Arkana ships
spacing=8 separation=4 chunks (≈4× denser than vanilla villages).

The shipped datapack overrides `data/iceandfire/worldgen/structure_set/
pixie_village.json` with spacing=32 separation=12 — vanilla-village
density, ~4× rarer than upstream. Existing chunks keep their generated
villages; new exploration generates a sparser grid. Pixie spawn eggs and
the pixies inside the villages that do generate are unaffected, so the
pixie-dust craft path stays open.

## Existing instances — applying these on upgrade

The CurseForge launcher only copies `overrides/` into a NEW instance during
import. If you already imported an older release and want the new fixes:

1. **Easiest:** re-import the new zip as a fresh instance. Move your
   `saves/`, `screenshots/`, `config/` (per-world tweaks) over manually.
2. **In-place merge:** copy individual files out of the zip's `overrides/`
   into your instance directory, overwriting as needed. For TOML files
   like `darkmodeeverywhere-client.toml` you may want to diff first to
   preserve any local tweaks.

## JVM args

Per-platform recommendations in `JVM-ARGS.md` (zip root). Three variants
shipped:

- macOS aarch64 → Shenandoah (ZGC crashes on Apple Silicon for this
  workload).
- Linux x86_64 → ZGC generational.
- Windows x86_64 → ZGC generational.

## Reporting issues

Server side and pack-overlay issues:
https://github.com/alisonjenkins/nix-config/issues

Individual mod bugs: report upstream to the mod author's tracker (linked
on the mod's CurseForge / Modrinth page).
