# Declarative Beat Saber mods

Beat Saber mods (BSIPA + everything BeatMods-resolved) are pinned in this repo
and installed by `home-manager switch`, instead of ModAssistant/BSManager
click-through. `.claude/skills/beatsaber-modding/SKILL.md` has the full
repo-editing procedure for Claude; this is the human version — what it does,
how to use it, and the one manual step it can't do for you.

## What's pinned right now

Game version **1.40.8** (Steam beta branch `legacy1.40.8_unity_v2021.3.16f1`),
not the current release — see "Why an old game version" below.

Mods: `BSIPA`, `SongCore`, `BeatSaverDownloader`, `ScoreSaber`, `BeatLeader`,
`PlaylistManager`, `Chroma`, `NoodleExtensions`, `Heck`, `Camera2`,
`HitScoreVisualizer`, `BetterSongList`, `CustomSabersLite`, `GottaGoFast`,
`RandomSongPlayer`, `MenuSelector`, `Enhancements`, plus whatever each of
those pulls in as a dependency. The authoritative list is
`pkgs/beatsaber-mods/wanted-mods.json` (top-level only — dependencies aren't
listed there, they're resolved automatically).

## Setup (once)

1. Beat Saber → right-click in Steam → Properties → Betas → select
   `legacy1.40.8_unity_v2021.3.16f1`. Let it download/update.
2. Launch Beat Saber at least once on that branch (creates its Proton
   prefix), then quit.
3. `just switch` — copies the mod payload into the game's install directory
   (a merge-copy, not a symlink: BSIPA and mods write new files inside that
   same tree at runtime, which doesn't work against a symlink into the
   read-only nix store — copying only overwrites what the payload actually
   ships, your custom songs and other mod state are never touched).
4. Run `beatsaber-patch-mods` once. This is the one step the switch can't do
   for you: BSIPA has to binary-patch the game itself, which means running
   an `.exe` inside its Proton prefix — that's not something a NixOS/
   home-manager activation can safely do unattended (it's slow, external,
   and Proton-version-dependent), so it's a plain command you run by hand.
5. Launch Beat Saber. Mods menu (BSML gear icon) should list everything.

Re-running `just switch` later re-applies the copy (harmless, idempotent).
`beatsaber-patch-mods` only needs re-running if Steam "verifies integrity"
and wipes the game's `winhttp.dll` — it's idempotent too, and tells you if it
skipped because the patch is already there (`--force` to redo it anyway).

## Adding or removing a mod

1. Browse <https://beatmods.com/mods>, pick the game version above, find the
   mod's exact name.
2. Add (or remove) it in `pkgs/beatsaber-mods/wanted-mods.json`.
3. Ask Claude to regenerate `beatsaber-mods.nix` and rebuild (or run
   `generate-mods.py` yourself — needs Python + network, see the skill for
   the exact command).
4. `just switch`.

Dependencies are resolved automatically — you never need to add a library a
mod pulls in yourself.

## Why an old game version

Mod authors lag the live Beat Saber release, often by months. The mod
ecosystem's mainstays — ScoreSaber, BeatLeader, Chroma, NoodleExtensions,
Heck, PlaylistManager — were, at the time this was set up, only verified up
to around version 1.40.x; none of them had caught up to the then-current
release yet. Pinning an older, still-Steam-downloadable version (a "legacy"
beta branch) is normal practice in Beat Saber modding, not a workaround —
staying current usually means losing the mods that make modding worth doing.

If you want to chase the newer game version instead (fewer mods, whatever's
already caught up), that's a config change, not a rewrite — see the
"Bumping the pinned game version" section of the skill.

## Nothing showed up after switch

Check `modules.beatsaber.steamLibraryRoots` for your host (set per-machine in
`home/machines/<host>/default.nix`). Steam can split your games across
multiple library folders (different drives, or just multiple folders on one)
— check Steam → Settings → Storage, or `steamapps/libraryfolders.vdf` in any
Steam install dir, for where Beat Saber (appid `620980`) actually lives, and
make sure that path's parent is in the list. The activation refuses to touch
a matched directory that doesn't already contain `Beat Saber.exe` /
`Beat Saber_Data`, specifically so a wrong or stray empty folder can't get
populated with mod files by mistake — it'll warn instead.
