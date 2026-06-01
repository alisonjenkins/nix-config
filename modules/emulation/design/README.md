# `modules.emulation` — design docs

Design notes for a NixOS module that replicates an **EmuDeck-equivalent** emulation
stack natively on the `ali-steam-deck` host (Jovian-NixOS, 26.05, impermanence,
gamescope gaming mode + Plasma 6 desktop-mode specialisation, x86_64-linux).

**Status: DESIGN ONLY — not yet implemented.** These docs capture verified research
so the context isn't lost before code is written.

## Provenance

Distilled from two multi-agent research passes (web + NixOS package-search MCP,
adversarially verified — claims that were refuted are already corrected here, not
repeated). Run IDs for the transcripts:

- `wf_551b021b-13d` — EmuDeck-on-Nix architecture, emulator matrix, Switch keys,
  mode integration, declarative ROMs, prior art.
- `wf_c0d42924-0fe` — control schemes + Sinden lightgun (incl. border) across
  consoles/arcade.

All nixpkgs attr/version claims were verified against unstable (≈26.05 lineage) on
2026-06-01. **Re-verify attr paths/versions at implementation time** — emulators move fast.

## Documents

| Doc | Covers |
|---|---|
| [01-architecture.md](01-architecture.md) | Replicate-vs-package decision, verified emulator/frontend matrix, Switch emulation + keys/firmware, gaming/desktop integration, persistence, module skeleton |
| [02-content-sync.md](02-content-sync.md) | Declarative **manifest-driven** ROM/BIOS/firmware management from a private Backblaze B2 bucket via `rclone` (exact-state, prune-unlisted, never in the nix store) |
| [03-control-schemes.md](03-control-schemes.md) | Declarative input configs (RetroArch hotkeys/autoconfig/remaps, per-standalone table, the Steam Input imperative gap) |
| [04-sinden-lightgun.md](04-sinden-lightgun.md) | Sinden lightgun + screen border — **experimental**, viability verdict, driver packaging, border methods, per-emulator config, blockers |
| [05-frontend.md](05-frontend.md) | Pretty frontend — prettiness tier list, feature/music matrix, **decision: RetroFE**, integration design, media pipeline |

## Headline decisions

1. **Replicate EmuDeck's end-state natively — do NOT package/run EmuDeck.** It's an
   imperative Flatpak/AppImage installer that fights immutable + impermanent NixOS.
2. **ROMs/BIOS/keys live on the persisted `/home` disk, never the nix store** — fetched
   by an `rclone` sync from a private B2 bucket, driven by an **explicit Nix manifest**
   (listed = present, unlisted = pruned). Keeps multi-GB libraries out of the niks3
   cache push. Sourcing copyrighted content is the user's legal responsibility (own
   dumps only).
3. **Control schemes ship now** (all emulator input configs are plain text → declarative).
   Steam Input per-AppID binding is the one imperative step (steam-rom-manager, one-time);
   per-game Steam Input layouts only work in Gaming Mode, so native config is the
   authoritative layer for desktop mode.
4. **Sinden lightgun is deferred to an experimental sub-module** (`enable = false`):
   no proven Jovian-native success, pointer injection may be X11-only (Wayland blocker),
   dual-gun is X11-only. Safe declarative groundwork (driver package, udev, border assets)
   can land; the end-to-end gun experience is a hardware-in-hand spike.
5. **Frontend: RetroFE** (`pkgs.retrofe`) — prettiest *animated* option that's actually
   packaged + drives our emulators declaratively. Trade-off: weak native per-game music
   (only AttractMode-Plus does that natively, but it's unpackaged + XWayland). Media via
   `skyscraper`, synced from B2 like ROMs. See 05-frontend.md.

## Repo wiring (when implemented)

- Module at `modules/emulation/default.nix` (options pattern: `options.modules.emulation.*`
  / `config = mkIf cfg.enable`).
- Export in `flake-modules/nixos-modules.nix` (`emulation = ./../modules/emulation;`).
- Reference from the host as `self.nixosModules.emulation`; enable in
  `flake-modules/hosts/ali-steam-deck/default.nix`.
- Reuse the host's impermanence pattern; `/home` is already bind-mounted to
  `/persistence/home`, so user-level emulation state persists with no extra config.
