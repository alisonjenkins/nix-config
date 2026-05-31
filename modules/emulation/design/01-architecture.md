# 01 — Architecture

## Decision: replicate natively, do NOT package EmuDeck

EmuDeck is not an app — it's a collection of Bash scripts that at *runtime* download
emulators from Flathub/GitHub AppImage hosts and write opinionated configs. Its value
is the config templating + folder convention + Steam ROM Manager (SRM) parsers (all
*data* we can express declaratively); its delivery mechanism (Flatpak + `$HOME/Applications`
AppImages + in-place self-update) is exactly what breaks on immutable + impermanent NixOS:

1. Flatpak/Flathub installs are imperative and version-drift.
2. AppImages assume glibc FHS + FUSE; EmuDeck's launch scripts don't wrap them.
3. In-place self-updates write to non-persisted `$HOME` paths → wiped by the tmpfs root.
4. SRM parsers hardcode Flatpak/AppImage launch commands that won't match `/nix/store`.

Only prior-art packaging — `alyraffauf/bazznix` (`appimageTools.wrapType2` of EmuDeck) —
is self-described "extremely limited, proof-of-concept, SRM won't work, expect issues."

**→ Replicate the end-state declaratively:** emulators from nixpkgs + SRM + the
`~/Emulation` tree + persistence wiring. ~15 emulators + `steam-rom-manager` are packaged.
`/home` is bind-mounted to `/persistence/home`, so all user emulation state
(`~/Emulation`, `~/.config/<emu>`, `~/.local/share/<emu>`, Steam `userdata`) persists
across the impermanence wipe with **zero extra config**.

## Emulator + frontend matrix (verified vs nixpkgs unstable, 2026-06-01)

### Packaged — declare these

| System | Attr | Version | Notes |
|---|---|---|---|
| Multi (libretro) | `retroarch` (= `retroarch-with-cores`) | 1.22.2 | cores via `retroarch.withCores (c: …)` / `libretro.*`; `retroarch-full` exists |
| PS2 | `pcsx2` | 2.6.3 | x86_64-linux only (fine on Deck) |
| GC/Wii | `dolphin-emu` | 2603a | NB attr is `dolphin-emu`, **not** `dolphin` (KDE file mgr). `dolphin-emu-primehack` sibling |
| PS3 | `rpcs3` | 0.0.39-unstable | |
| Wii U | `cemu` | 2.6 | x86_64-linux only |
| Xbox (OG) | `xemu` | 0.8.134 | |
| PSP | `ppsspp` (= `ppsspp-sdl`) | 1.20.3 | consider `ppsspp-sdl-wayland` for Plasma |
| DS | `melonds` (lowercase) | 1.1-unstable | alt `desmume` |
| GBA | `mgba` | 0.10.5 | |
| Dreamcast/Naomi | `flycast` | 2.5 | |
| 3DS | `azahar` | 2125.0.1 | Citra successor; **confirmed present**. Config at `~/.config/azahar-emu/` |
| Arcade | `mame` | — | verify version at build |
| Multi/N64/ScummVM | `ares`, `mupen64plus`, `scummvm` | — | verify at build |
| PS4 | `shadps4` | 0.13.0 | fast-moving, verify |
| Steam glue | `steam-rom-manager` | 2.5.34 | **free, GPL-3.0-only** (earlier "unfree?" was a misread); x86_64-linux only |

### Gaps — not in nixpkgs (external-source or drop)

| Piece | Status | Handling |
|---|---|---|
| **PS1 / DuckStation** | `duckstation` **removed** 2026-03-14 (relicensed cc-by-nc-nd) | PS1 via `retroarch` + `libretro.swanstation` (free DuckStation-fork core); or `libretro.pcsx_rearmed` |
| **ES-DE frontend** | `emulationstation-de` + `emulationstation` **removed** 2025-10-23 (freeimage CVEs); both throw on eval | RetroDeck Flatpak `net.retrodeck.retrodeck` (via `nix-flatpak`, already imported); or ES-DE AppImage; or **skip a frontend** and use SRM + Gaming Mode (simplest). `pegasus-frontend` is a packaged alternative |
| **PS Vita / vita3k** | not in nixpkgs | AppImage-wrap or drop |
| **Xbox 360 / Xenia** | Windows-only | Proton or drop |

### nixpkgs trap — `citron`

Upstream `pkgs.citron` (`pkgs/by-name/ci/citron`) is an **MIT Rust crate**, NOT the
Switch emulator. On this host it resolves to the *emulator* only because this repo's
`overlays.additions` shadows it with `pkgs/citron/default.nix` (built from
`github.com/citron-neo/emulator`). Any module referencing `pkgs.citron` must run with
this repo's overlays applied.

## Switch emulation + keys/firmware

Three viable Yuzu-lineage options in 2026 (post-Yuzu-DMCA):

- **`citron`** — this repo's overlay derivation (Qt6/SDL2/Vulkan). Already in the host's
  user packages.
- **`eden`** — repo overlay (AppImage) or nixpkgs `eden` source build.
- **`ryubing`** — nixpkgs `ryubing` 1.3.3 (MIT; Ryujinx community fork). `ryujinx` itself
  is **not** in nixpkgs.
- `suyu`/`sudachi` do **not** exist as emulators in nixpkgs and are dead upstream.

**Config-dir layout (keys/firmware go here; all under persisted `/home`):**

- Yuzu forks (citron/eden): keys → `~/.local/share/<emu>/keys/prod.keys` (+ `title.keys`);
  firmware `.nca` → `~/.local/share/<emu>/nand/system/Contents/registered/`.
- Ryubing/Ryujinx: keys → `~/.config/Ryujinx/system/prod.keys`; firmware →
  `~/.config/Ryujinx/bis/system/Contents/registered/`.

**Key/firmware delivery (legal + technical):** `prod.keys`, `title.keys`, firmware are
console-unique + copyrighted. **Never `fetchurl`** them. Own-console dump only
(Lockpick_RCM / nxdumptool). In this design they ride the same B2 manifest-sync as ROMs
(see [02-content-sync.md](02-content-sync.md)) into 0700 dirs, then are symlinked into
each emulator's expected path — nothing copyrighted touches the nix store. (sops-nix is an
alternative for the small key files if you'd rather not put them in B2.)

**udev:** `eden`'s `package.nix` ships `72-yuzu-input.rules` (Switch-controller HID via
`hidraw*` + `uaccess`) → `services.udev.packages = [ pkgs.eden ]`. `ryubing` ships **no**
udev rule (so `services.udev.packages = [ pkgs.ryubing ]` is a no-op). The `input` group
(already granted) governs `/dev/input/event*`, which is **distinct** from the HID `uaccess`.

## Gaming-mode + desktop-mode integration

- **Frontend launch:** ES-DE is gone from nixpkgs → RetroDeck Flatpak (prefer **user-mode**,
  data in `~/.var/app`, already persisted) or skip a console frontend. `nix-flatpak` is
  already imported by the host.
- **Steam ROM Manager** is the gaming-mode glue: writes non-Steam shortcuts to
  `~/.local/share/Steam/userdata/<id>/config/shortcuts.vdf` + artwork to `…/grid/` (both
  persisted). It has a headless CLI (`add`/`remove`/`enable`…; Steam must be exited for
  `add`), but parser config + SteamGridDB auth + artwork selection is a **one-time GUI**
  step. `userData` JSON can be templated declaratively (see `mjallen18/nix-steam-rom-manager`).
- **Desktop mode** needs nothing special: nixpkgs emulators ship `.desktop` entries into
  the Plasma menu. Do **not** repurpose the existing `steam-desktop` user service (it only
  runs `steam -silent` for the STEAM+X OSK).
- **ES-DE config path** (if used): ES-DE 3.0+ (Feb 2024) renamed `~/.emulationstation` →
  **`~/ES-DE`** (single migration; not coexisting). ROMs/BIOS/saves stay under
  `~/Emulation/{roms,bios,saves,storage,tools}`.

### Unavoidably imperative (be honest in module docs)

- SRM parser config + SteamGridDB auth + per-game art (one-time GUI; mitigated by templating
  `userData`).
- Generating `shortcuts.vdf` (`srm add` with Steam stopped — a desktop-mode/maintenance action).
- BIOS/keys/ROM **sourcing** (own dumps; placed via the B2 manifest).
- ES-DE first-run scraping (persist `~/ES-DE`, one-time).

## Module skeleton (conventions)

`options.modules.emulation.*` / `config = mkIf cfg.enable`, at `modules/emulation/default.nix`,
exported in `flake-modules/nixos-modules.nix`, referenced as `self.nixosModules.emulation`.

```nix
# modules/emulation/default.nix
{ config, lib, pkgs, ... }:
let cfg = config.modules.emulation; in {
  options.modules.emulation = {
    enable   = lib.mkEnableOption "EmuDeck-equivalent emulation stack";
    user     = lib.mkOption { type = lib.types.str; default = "ali"; };
    # emulators, frontend, switch.*, content.* (02), controls.* (03), sinden.* (04)
  };

  config = lib.mkIf cfg.enable {
    # PS1 via RetroArch+swanstation, NOT duckstation
    users.users.${cfg.user}.packages = with pkgs; [
      (retroarch.withCores (c: with c; [ swanstation snes9x genesis-plus-gx ]))
      pcsx2 dolphin-emu rpcs3 cemu xemu ppsspp melonds mgba flycast mame ares scummvm azahar
      steam-rom-manager
      # Switch: citron (repo overlay) / ryubing / eden
    ];
    services.udev.packages = lib.mkIf cfg.switch.enable [ pkgs.eden ]; # ships the real rule
    # frontend (RetroDeck flatpak) optional; content sync (02); controls (03); sinden (04)
    # NO extra environment.persistence needed unless system-mode flatpaks are used.
  };
}
```

**Plug-in (host `ali-steam-deck/default.nix`):** add `self.nixosModules.emulation` to
`modules`; set `modules.emulation = { enable = true; switch.enable = true; … };`; remove
`citron` from `users.users.ali.packages` once the module owns it.

## Open questions / hands-on testing

- Confirm `ares`/`scummvm`/`shadps4`/`mupen64plus`/`mame` versions live at build (`nix eval`).
- Verify `retroarch.withCores` core names (`libretro.swanstation`, `snes9x`, `genesis-plus-gx`).
- SRM `userData` JSON key-ordering stability across version bumps (pin carefully).
- RetroDeck Flatpak first-run + Gaming-Mode shortcut launch path on this Jovian/26.05 build.
- Switch keys/firmware placement end-to-end (which path the chosen fork reads).
- `pkgs.eden` source build vs repo AppImage overlay — only the source build was verified to
  ship `72-yuzu-input.rules`; an AppImage-wrapped eden may not.
