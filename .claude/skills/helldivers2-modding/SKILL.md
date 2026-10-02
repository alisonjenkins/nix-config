---
name: helldivers2-modding
description: How this repo scaffolds Helldivers 2 modding via pkgs/arsenal
  and home/modules/helldivers2-mods. Use when installing/enabling a
  Helldivers 2 mod, debugging why a mod shows enabled but does nothing
  in-game, bumping arsenal's or hd2-repatcher's pinned version, or
  explaining why mod install itself isn't declarative here.
paths:
  - "pkgs/arsenal/**"
  - "pkgs/hd2-repatcher/**"
  - "home/modules/helldivers2-mods/**"
---

# Helldivers 2 modding

Two pieces:

- `pkgs/arsenal`: packages `hd2arsenal` (rsnl-gg/HD2Arsenal), the current
  Linux-native mod manager, GUI. Upstream ships an electron-builder `.deb`
  zipped (no AppImage/tarball) — the package `fetchurl`s the zip,
  `dpkg-deb -x`s the `.deb` inside it, then `autoPatchelf`s the bundled
  (not nixpkgs') Electron binary and its native node addons
  (`better-sqlite3`, `sharp`, `active-win`) against nixpkgs libs. Pinned by
  version + content hash from the GitHub release's `digest` field.
- `pkgs/hd2-repatcher`: packages `hd2-repatcher-cli` (RaidingForPants/
  hd2-repatcher), which resyncs a mod's `.patch` files' unit resource IDs
  against the currently-installed game data after an Arrowhead update
  desyncs them (see Debugging below). Pinned by commit rev — upstream's
  `pyproject.toml` version trails its latest tag, so there's no tag to pin
  to. CLI-only build: `gui.py` needs tkinter and is deliberately excluded
  from the closure (see the package's header comment).
- `home/modules/helldivers2-mods`: installs `arsenal` + `hd2-repatcher`
  and, on every `home-manager switch`, searches `steamLibraryRoots` for
  the game and `jq`-merges the result into Arsenal's `userGameDir` setting
  (`~/.config/hd2arsenal/hd2a_data.json`'s `userGameDir` key — the game's
  **root** dir, not `data/`, unlike h2mm-cli/hd2-repatcher). A merge, not
  a wholesale overwrite, since that file also holds Arsenal's own live
  state (mod list, deploy flags, UI prefs) that activation must not
  clobber. Warns on stderr instead if no install is found. That's **all**
  it automates.

## Incident: h2mm-cli silently not deploying mods (2026-10-02)

Symptom: `h2mm list` showed all 5 installed mods `ENABLED`, `data/mods.csv`
and the numbered `.patch_N` files were correctly placed with real
(nonzero) content, the game's library path and `h2path` cache were
correct, and a full machine reboot didn't change anything — yet **none**
of the mods, including the simplest pure-overlay one (Mod Lag Watchdog),
had any visible effect in-game.

Every config/file-placement layer checked out; the fault was upstream.
`h2mm-cli`'s own git history shows:

```
commit 9bfa892 "chore: deprecate" (2025-09-30):
> This project is deprecated as of 30/09/2025 in favor of Arsenal's
> 0.30.0 release, a GUI mod manager that supports every feature of
> Helldivers 2 Mod Manager CLI and more, on Linux.
```

and [upstream issue #96 "Doesn't deploy mods"](https://github.com/v4n00/h2mm-cli/issues/96)
(filed 2026-04-17, after the deprecation, never fixed) reproduces the
exact symptom: mods show `ENABLED` but have zero effect, confirmed to be
an h2mm-cli bug by testing the same mod with Arsenal instead, where it
works. The repo had no code commits after the deprecation commit, so the
bug was never going to be fixed. `hd2-repatcher` was a red herring here —
run against each mod's isolated original zip contents, it found 4 of 5
mods weren't even "unit resource" mods (out of its scope entirely) and the
5th was flagged corrupted, not just stale; repatching doesn't fix an
h2mm-cli deployment bug.

Fix: migrated the module from `h2mm-cli` to `pkgs/arsenal` (this skill's
current state). If this symptom resurfaces with Arsenal, it's a new bug —
don't assume it's the same root cause.

## What this module deliberately does NOT do

Installing or enabling a mod is a manual, imperative step you run by hand —
not activation. Two reasons:

1. **Mod archives can't be nix-fetched.** Nexus gates Helldivers 2 mods'
   scripted/API downloads behind a Premium account (e.g.
   <https://www.nexusmods.com/helldivers2/mods/16493> for DiverKit), unlike
   `pkgs/beatsaber-mods`, which fetches straight from the BeatMods API by
   content hash.
2. **Deploying a mod mutates live game state** — numbered `.patch_N`
   archives and a `mods.csv` ledger inside the game's `data/` directory.
   Running that unattended on every switch risks corrupting it, the same
   reason `beatsaber-patch-mods`'s `IPA.exe` patch step is kept off
   activation (see the `beatsaber-modding` skill).

## How mod loading actually works

Helldivers 2 (Bitsquid/Stingray engine) loads assets from numbered
`<hash>.patch_N` / `<hash>.patch_N.stream` archive pairs sitting next to the
base game data — at startup it layers them in ascending `N` order, last one
wins per asset. A mod *is* one of these pairs; there's no in-game mod
loader or manifest to toggle. The mod manager copies a mod's patch files
into `data/`, assigns the next free `N`, and writes the mapping into
`data/mods.csv`.

Disabling a mod doesn't delete or move it out of `data/` — it renames the
files with a `disabled_<timestamp>_` prefix, which no longer matches the
`patch_N` pattern the engine scans for, so it's silently skipped at
startup. Nothing server-side is involved and nothing needs reinstalling to
flip back.

## Installing a mod

1. Download the mod's zip from Nexus by hand into
   `modules.helldivers2Mods.modsDir` (default `~/mods/helldivers2`,
   created by activation).
2. Add it through Arsenal's own UI and deploy it.

## Debugging

- **Activation warns "no Helldivers 2 install found under: ..."**: none of
  `modules.helldivers2Mods.steamLibraryRoots` (default
  `~/.local/share/Steam`) contains a `steamapps/common/Helldivers 2` with
  both a `data/` dir and `bin/helldivers2.exe` — the latter check exists so
  an empty Steam-created placeholder dir (hit once with the beatsaber
  module) doesn't get treated as a real install. Check
  `steamapps/libraryfolders.vdf` under any Steam install for where appid
  `553850` actually lives, and add that root to the host's
  `steamLibraryRoots`. Without this, Arsenal's `userGameDir` won't get
  pre-seeded and it'll prompt for the path itself on first launch instead.
- **A mod is installed/enabled correctly (mod manager shows it enabled,
  patch files present on disk with real content) but has zero effect
  in-game**: see the Incident section above before assuming it's a stale
  unit-ID issue — check which mod manager is in use first, since this
  exact symptom was an unfixed h2mm-cli bug. If using Arsenal and it
  recurs, then check `hd2-repatcher-cli --game "<data dir>" <mod patch
  folder>` per mod (the patch folder is the mod's original extracted zip
  contents, not the live mixed `data/` dir — scanning the whole data dir
  risks false "corrupted" verdicts on unrelated vanilla patch files).
  Confirmed via <https://github.com/RaidingForPants/hd2-repatcher> and
  <https://steamcommunity.com/app/553850/discussions/0/732532498321661503/>.
- Steam library lookup here, in `home/modules/beatsaber`, and in
  `home/modules/subnautica-vr` are three separate implementations with
  different validation shapes (see the cross-reference comments in each) —
  a Flatpak-Steam-paths fix or similar needs to be applied to all three by
  hand.

## Bumping arsenal's pinned version

No tags, releases only, via <https://github.com/leguteape/hd2arsenal-release/releases/latest>
(mirrors rsnl.gg's builds). Bump `version` in `pkgs/arsenal/default.nix`
and get the new hash from the release asset's `digest` field (`gh api
repos/leguteape/hd2arsenal-release/releases/latest -q
.assets[0].digest`, strip the `sha256:` prefix, `nix hash convert
--hash-algo sha256 --to sri <hex>`) — don't `fetchurl` blind, GitHub's API
digest is already a verified checksum. If the deb filename pattern
(`hd2arsenal_<version>_amd64.deb`) changes, update the `dpkg-deb -x` line
in `installPhase` too.
