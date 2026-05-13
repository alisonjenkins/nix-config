# Create: Arkana + Aeronautics — client modpack

CurseForge-style import zip for the Arkana 1.5 + Aeronautics 1.2.1 floor on
Minecraft 1.21.1 NeoForge 21.1.228. Built reproducibly from nix-config at
[github.com/alisonjenkins/nix-config](https://github.com/alisonjenkins/nix-config).

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

`overrides/config/darkmodeeverywhere-client.toml` appends `"org.vivecraft"`
to `METHOD_SHADER_BLACKLIST`.

**Why:** Dark Mode Everywhere intercepts a list of well-known GUI render
methods and applies its dark shader to the GUI texture before the rest of
the render pipeline continues. In VR, Vivecraft samples that (already-dark)
GUI texture and composites it onto a flat panel in 3D world space — the
panel becomes near-black and the Vivecraft pointer becomes near-invisible.

DarkModeEverywhere's upstream default blacklist exempts vanilla
crosshair / hotbar / title-screen methods but doesn't know about
`org.vivecraft.*` — so VR players hit this. The shipped blacklist override
adds a single substring entry that covers every Vivecraft GUI render method
without enumerating them.

Non-VR players are unaffected — `selectedShaderIndex = 0` (perfect_dark)
stays as the upstream default.

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
