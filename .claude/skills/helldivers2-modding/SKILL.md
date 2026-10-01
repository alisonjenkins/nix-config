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

## How mod loading actually works

Helldivers 2 (Bitsquid/Stingray engine) loads assets from numbered
`<hash>.patch_N` / `<hash>.patch_N.stream` archive pairs sitting next to the
base game data — at startup it layers them in ascending `N` order, last one
wins per asset. A mod *is* one of these pairs; there's no in-game mod
loader or manifest to toggle. `h2mm install` copies a mod's patch files into
`data/`, assigns the next free `N` (or whatever `h2mm order` puts it at),
and writes the mapping into `data/mods.csv`.

Disabling a mod doesn't delete or move it out of `data/` — it renames the
files with a `disabled_<timestamp>_` prefix, which no longer matches the
`patch_N` pattern the engine scans for, so it's silently skipped at
startup. Nothing server-side is involved and nothing needs reinstalling to
flip back.

## Swapping between modded and vanilla

- **One mod**: `h2mm disable -n "<name>"` / `h2mm enable -n "<name>"` (or
  `-i <index>` from `h2mm list`).
- **Everything, temporarily** (e.g. before a multiplayer session — HD2 has
  no anti-cheat that bans for mods, but a host/client asset mismatch can
  still cause join failures or visual desync): `h2mm modpack create
  "Vanilla"` while nothing is enabled, then `h2mm modpack switch "Vanilla"`
  to disable every mod at once and `h2mm modpack switch <your modpack>` to
  re-enable them — this just batches `enable`/`disable` over the set
  recorded in the modpack, nothing more.
- **Everything, permanently**: `h2mm reset` deletes every `patch_N` file
  and clears `data/mods.csv` (add `--no-path-reset` to keep the
  `h2path` cache this module pre-seeds; otherwise the next `h2mm`
  invocation falls back to its interactive prompt until the next
  `home-manager switch` reseeds it). Irreversible — mods have to be
  reinstalled from their archives, not just re-enabled.

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
