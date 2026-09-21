---
name: beatsaber-modding
description: How this repo declaratively installs Beat Saber mods (BSIPA +
  BeatMods-resolved mod list) via pkgs/beatsaber-mods and
  home/modules/beatsaber. Use when adding/removing a Beat Saber mod,
  regenerating beatsaber-mods.nix, bumping the pinned game version, or
  debugging why a mod didn't load / BSIPA shows "not installed" / the
  beatsaber-patch-mods script.
paths:
  - "pkgs/beatsaber-mods/**"
  - "home/modules/beatsaber/**"
---

# Beat Saber mod install

Two pieces:

- `pkgs/beatsaber-mods`: builds the mod *payload* — resolves
  `wanted-mods.json` (mod names) against the BeatMods API for a pinned game
  version, transitively includes dependencies, and unzips every resolved
  mod's zip into a tree mirroring the game's install layout (`Plugins/`,
  `Libs/`, `IPA/`, ...).
- `home/modules/beatsaber`: places it — merge-copies (not symlinks: BSIPA
  and mods write new files inside the tree at runtime, which a symlink into
  the read-only nix store can't support) that tree into the live Steam
  install on every `home-manager switch`, plus ships `beatsaber-patch-mods`
  (run by hand, not activation) to run BSIPA's
  one-time `IPA.exe` patch.

## Adding or removing a mod

1. Browse <https://beatmods.com/mods> for the pinned game version (see
   `gameVersion` default in `pkgs/beatsaber-mods/default.nix`) and note the
   mod's exact `name` as BeatMods lists it.
2. Edit `pkgs/beatsaber-mods/wanted-mods.json` — this is the **top-level**
   wanted list only; do not add a mod's dependencies by hand, the generator
   resolves those.
3. Regenerate:
   ```bash
   cd pkgs/beatsaber-mods
   python3 generate-mods.py <game-version> wanted-mods.json beatsaber-mods.nix
   ```
   `<game-version>` must match `default.nix`'s `gameVersion` default (or pass
   `.override { gameVersion = ...; }` when building). Needs network; not run
   inside the Nix sandbox, same reason `generate-arkana-mods.sh` isn't (see
   `minecraft-modpack-packaging` skill).
4. Rebuild and check every mod you expect is actually in the output:
   ```bash
   nix build --impure --expr '
     let f = builtins.getFlake (toString ./.); sys = "x86_64-linux";
         pkgs = import f.inputs.nixpkgs { system = sys; config.allowUnfree = true; overlays = builtins.attrValues f.outputs.overlays; };
     in pkgs.beatsaber-mods
   ' -o /tmp/beatsaber-mods-result
   ls /tmp/beatsaber-mods-result
   ```
5. Commit `wanted-mods.json` + the regenerated `beatsaber-mods.nix` together
   (one commit — the generated file is a pure function of the wanted list at
   that game version, splitting them serves no revert purpose).

## Bumping the pinned game version

BeatMods coverage lags the live Beat Saber release, often by months — most
of the mod ecosystem's staples (ScoreSaber, BeatLeader, Chroma,
NoodleExtensions, Heck, PlaylistManager) are pinned to whatever game version
their authors last verified against, not the current one. Before bumping:

1. Query BeatMods for the candidate version and confirm every mod in
   `wanted-mods.json` still resolves:
   ```bash
   curl -s "https://beatmods.com/api/mods?gameVersion=<version>&status=verified" \
     -H "User-Agent: nix-config-beatsaber-mods/1.0" | \
     python3 -c "import json,sys; print(sorted(e['mod']['name'] for e in json.load(sys.stdin)['mods']))"
   ```
2. Confirm the version is actually installable — Steam only ships specific
   pinned beta branches (Beat Saber → Properties → Betas), not every point
   release. Check the branch list matches before committing to a version.
3. Update `gameVersion`'s default in `pkgs/beatsaber-mods/default.nix`,
   regenerate (step 3 above), rebuild, commit.
4. Switch the Steam beta branch by hand — this repo doesn't (and can't)
   drive Steam's branch selection.

## Debugging

- **Mod doesn't show up in-game**: `beatsaber-mods.nix` is stale — rerun the
  generator (step 3 above); a mod's `wanted-mods.json` entry alone changes
  nothing until regenerated.
- **Nothing shows up in the game dir / activation warns "doesn't look like a
  real Beat Saber install"**: `home/modules/beatsaber`'s activation searches
  `modules.beatsaber.steamLibraryRoots` (default `~/.local/share/Steam`) for
  `steamapps/common/Beat Saber`, and refuses to touch a match that doesn't
  already contain `Beat Saber.exe`/`Beat Saber_Data` (it will otherwise
  happily populate an empty Steam-created placeholder dir with mod files,
  which is not the same thing as the real install — this bit us once on
  ali-desktop, which splits games across two library folders on the same
  drive; the game was on the second one). Check
  `steamapps/libraryfolders.vdf` under any Steam install dir for where appid
  `620980` actually lives, and add that root to the host's
  `steamLibraryRoots`.
- **BSIPA shows "not installed" / mods don't load at all**: `winhttp.dll`
  is missing from the game dir. BSIPA's zip ships `IPA.exe`, not a
  pre-built `winhttp.dll` — the activation copy places `IPA.exe` but can't
  run it. Run `beatsaber-patch-mods` (installed by the module) by hand;
  it's idempotent (skips if `winhttp.dll` already exists) — pass `--force`
  to re-patch after a Steam "verify integrity" wipes it.
- **`beatsaber-patch-mods` fails with "Could not locate game executable"**:
  `IPA.exe` finds the game exe via its own working directory; the script
  `cd`s into the game dir before invoking `protontricks-launch` for exactly
  this reason — if this recurs, something changed that ordering.
- **`beatsaber-patch-mods` fails with "Access to the path ... is denied"**:
  something in the game install under `IPA/`, `Libs/`, `Plugins/`, or
  `UserData/` is a symlink into the nix store again (e.g. leftover from a
  manual test, or a regression in the module). The activation plain-copies
  the payload specifically so BSIPA/mods can write inside those
  directories at runtime — a symlinked directory, or even a symlinked
  *file* that BSIPA executes (the .NET CLR resolves a running exe's own
  location through symlinks), breaks that. Find and clear any nix-store
  symlinks under the game dir (`find "<gameDir>" -type l -lname
  '/nix/store/*'`, `chmod -R u+w` first if `-delete` hits permission
  errors on store-mode directories), then rerun `just switch`.
- **`beatsaber-patch-mods` fails for another reason**: it shells out via
  `protontricks-launch --appid <steamAppId>`, which needs Steam to have
  actually launched Beat Saber at least once (so its Proton prefix exists)
  and `protontricks` to be able to see it.
