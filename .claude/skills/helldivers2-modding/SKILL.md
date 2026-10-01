---
name: helldivers2-modding
description: How this repo scaffolds Helldivers 2 modding via pkgs/h2mm-cli
  and home/modules/helldivers2-mods. Use when installing/enabling a
  Helldivers 2 mod, debugging why h2mm can't find the game, bumping
  h2mm-cli's pinned version, or explaining why mod install itself isn't
  declarative here.
paths:
  - "pkgs/h2mm-cli/**"
  - "home/modules/helldivers2-mods/**"
---

# Helldivers 2 modding

Two pieces:

- `pkgs/h2mm-cli`: packages `h2mm` (v4n00/h2mm-cli), the only Linux-native
  Helldivers 2 mod manager today — upstream's own GUI tool ("Arsenal") has
  no Linux build yet. Upstream ships it as a single committed bash script
  with no releases/tags, so the package is `fetchurl` + `wrapProgram`
  pinned by content hash, not a git rev.
- `home/modules/helldivers2-mods`: installs that package and, on every
  `home-manager switch`, pre-seeds h2mm's own path cache
  (`~/.config/h2mm/h2path`) by searching `steamLibraryRoots` for the game.
  That's **all** it automates.

## What this module deliberately does NOT do

Installing or enabling a mod is a manual, imperative step you run by hand —
not activation. Two reasons:

1. **Mod archives can't be nix-fetched.** Nexus gates Helldivers 2 mods'
   scripted/API downloads behind a Premium account (e.g.
   <https://www.nexusmods.com/helldivers2/mods/16493> for DiverKit), unlike
   `pkgs/beatsaber-mods`, which fetches straight from the BeatMods API by
   content hash.
2. **`h2mm install`/`h2mm enable` mutate live game state** — numbered
   `.patch_N` archives and a `mods.csv` ledger inside the game's `data/`
   directory. Running that unattended on every switch risks corrupting it,
   the same reason `beatsaber-patch-mods`'s `IPA.exe` patch step is kept off
   activation (see the `beatsaber-modding` skill).

## Installing a mod

1. Download the mod's zip from Nexus by hand into
   `modules.helldivers2Mods.modsDir` (default `~/mods/helldivers2`,
   created by activation).
2. `h2mm install ~/mods/helldivers2/<mod>.zip`
3. `h2mm enable <mod>` if it doesn't prompt to enable it itself.

`h2mm` reads the game's `data/` directory from `~/.config/h2mm/h2path` —
pre-seeded by this module so the first invocation doesn't stall waiting on
a TTY prompt in a non-interactive context. If that file is empty or
missing, `h2mm` falls back to an interactive `find` + prompt instead of
failing outright.

## Debugging

- **Activation warns "no Helldivers 2 install found under: ..."**: none of
  `modules.helldivers2Mods.steamLibraryRoots` (default
  `~/.local/share/Steam`) contains a `steamapps/common/Helldivers 2` with
  both a `data/` dir and `bin/helldivers2.exe` — the latter check exists so
  an empty Steam-created placeholder dir (hit once with the beatsaber
  module) doesn't get treated as a real install. Check
  `steamapps/libraryfolders.vdf` under any Steam install for where appid
  `553850` actually lives, and add that root to the host's
  `steamLibraryRoots`.
- **`h2mm` prompts interactively instead of using the pre-seeded path**:
  `~/.config/h2mm/h2path` is empty or stale — rerun `just switch` (it's
  idempotent, rewritten every activation), or check the warning above fired
  because the game genuinely isn't found yet.
- Steam library lookup here, in `home/modules/beatsaber`, and in
  `home/modules/subnautica-vr` are three separate implementations with
  different validation shapes (see the cross-reference comments in each) —
  a Flatpak-Steam-paths fix or similar needs to be applied to all three by
  hand.

## Bumping h2mm-cli's pinned version

Upstream has no releases/tags; `pkgs/h2mm-cli` pins by content hash of the
raw script. Check
<https://raw.githubusercontent.com/v4n00/h2mm-cli/master/version> against
the `version` in `pkgs/h2mm-cli/default.nix`, and if it's moved, bump both
`version` and `hash` (`nix hash to-sri --type sha256 $(nix-prefetch-url
https://raw.githubusercontent.com/v4n00/h2mm-cli/master/h2mm)` or let the
build fail once and read the hash mismatch error) together in one commit.
