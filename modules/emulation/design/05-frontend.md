# 05 — Frontend (the pretty interface)

**Decision: RetroFE** (`pkgs.retrofe`). Chosen for prettiness + animation while staying
a native nixpkgs package that drives our emulators declaratively. The known cost is **weak
per-game music** (see §Music) — accepted, with an optional external-BGM mitigation.

Provenance: research run `wf_88a8e340-825` (web + NixOS package MCP, adversarially verified).

## Prettiness tier list (Linux-compatible)

Prettiness is **theme-driven** for every engine — bare engine + good theme + scraped media.

| Tier | Frontend | Why |
|---|---|---|
| **S** | **RetroFE** (`retrofe`, Linux-only) | HyperSpin-style animated scrolling wheels, transitions, per-game video-with-audio. Prettiest *animated* option that's actually packaged. |
| **S** | ES-DE (RetroDeck flatpak) | ~80 curated themes, carousel/grid engine, video previews. **Not in nixpkgs**; flatpak-only. |
| **A** | Pegasus (`pegasus-frontend`) | Modern GPU QtQuick carousels + video. Native, fully declarative. |
| **A** | AttractMode / AttractMode-Plus | Arcade wheels + video + **the only native music**. Plus fork unpackaged. |
| **C** | Steam Big Picture + SRM | Native gamescope, SteamGridDB art — **no video/music**. |
| **C** | Kodi+IAGL, Lutris/GameHub | Media-center / app-launchers; no arcade wheel. |
| ref | LaunchBox/BigBox, HyperSpin, Playnite | Prettiest overall but **Windows-only** — not viable on Jovian/Wayland. |

## Music verdict (the deciding feature)

Video snaps + animated wheels are common; real **per-game/theme music is rare**:

- **AttractMode-Plus** — only clear native YES (FeMusic+FFmpeg, per-display BGM).
- **Pegasus** — engine supports it, but **theme-DIY** (gameOS ships none).
- **RetroFE** — only a `reloadableAudio` selection hack that **conflicts with video-snap audio**; no jukebox.
- **ES-DE** — **none** native (external scripts; on roadmap).

RetroFE was chosen despite this — music is a nice-to-have here, prettiness+animation+native-package won. **Mitigation if wanted:** a small external background-music player (systemd user service playing per-system playlists), independent of RetroFE's selection events.

## RetroFE integration design

- **Package:** `pkgs.retrofe` (0.10.31, phulshof fork; SDL2 + GStreamer/`gst-libav` for video+audio). Linux-native → runs under gamescope like the emulators (SDL2/XWayland) and on Plasma.
- **Writable config (`RETROFE_PATH`):** the store binary is read-only, but RetroFE needs a writable tree (`settings.conf`, `layouts/`, `collections/`, `meta/`). Pattern: home-manager renders the declarative config into a **persisted writable dir** under `~` (e.g. `~/.config/retrofe` or `~/Emulation/retrofe`), `RETROFE_PATH` points there. Ship `settings.conf` + per-collection launchers + the theme as managed files; leave scraped media + any runtime state writable.
- **Per-collection launchers → emulators:** each console = a RetroFE *collection* with a launcher `.conf` whose executable/args point at the **nixpkgs emulator store paths** (token substitution for the ROM). This is where the `consoles` catalogue (doc 01/refactor) feeds in: collection name = console, launcher = the console's chosen emulator(s), ROM dir = the console's content-sync dest.
- **Themes:** `fetchFromGitHub` a HyperSpin-style theme (e.g. GLaDOS-16x9, CORE/Core Type R, ICONIC) into the config tree, declaratively. HyperSpin packs are **not** drop-in.
- **Launch surfaces:** Gaming Mode = add wrapped `retrofe` as a non-Steam shortcut (via Steam ROM Manager); Plasma = `.desktop` entry. Validate gamescope fullscreen + controller focus (open question).

## Media pipeline (feeds RetroFE)

RetroFE doesn't scrape. Use **`skyscraper`** (✅ nixpkgs) for box art / wheels / marquees /
video snaps / metadata; point RetroFE's per-collection artwork/video paths at the scraped
tree. Alternative video source: EmuMovies packs (ship audio). **Strategy that fits this repo:**
scrape **once out-of-band**, then **sync the media from B2 alongside ROMs** (same rclone
manifest engine, doc 02) — so media is declarative-managed data on the persisted disk, never
the store, and not re-scraped per rebuild. Music files (per-system playlists) are
user-supplied, synced the same way.

## Option surface (proposed)

Replace the `frontend` enum's emphasis with RetroFE first-class:

```nix
modules.emulation.frontend = {
  retrofe = {
    enable      = lib.mkEnableOption "RetroFE frontend";
    theme       = lib.mkOption { type = lib.types.nullOr lib.types.path; default = null; }; # fetched theme dir
    configDir   = lib.mkOption { type = lib.types.str; default = "~/.config/retrofe"; };
    steamShortcut = lib.mkEnableOption "add RetroFE as a non-Steam shortcut (gaming mode)";
    backgroundMusic = lib.mkEnableOption "external per-system BGM player (mitigates RetroFE's weak native music)";
  };
  retrodeckFlatpak.enable = lib.mkEnableOption "RetroDeck (ES-DE) flatpak instead (not declarative)";
};
```

Collections/launchers are **derived from `consoles`** (doc 01 refactor): each enabled console
emits a RetroFE collection pointing at its emulator(s) + its content-sync ROM dir.

## Open questions / hands-on testing

1. **gamescope nesting** — RetroFE (SDL2/XWayland) fullscreen sizing + controller-focus grab nested in gamescope (may need `-f`/scopebuddy tuning, like the host's other gamescope tweaks).
2. **`RETROFE_PATH` writable pattern** — confirm home-manager can render `settings.conf`/launchers/collections into a mutable persisted dir while the store binary stays read-only, surviving generation switches.
3. **Music** — if the `reloadableAudio` hack is unacceptable, validate the external-BGM-player mitigation (per-system playlists, doesn't fight snap audio).
4. **Switch fork launch args** (citron/ryubing/eden) slot into a RetroFE launcher `.conf` cleanly.
5. **Theme + scraped-media paths** — confirm the chosen theme's expected art/video/wheel layout matches Skyscraper's output structure.
