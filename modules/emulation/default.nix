# EmuDeck-equivalent emulation stack (native replication, not packaged EmuDeck).
#
# See modules/emulation/design/ for the full rationale. Headline: EmuDeck is an
# imperative Flatpak/AppImage installer that fights immutable + impermanent
# NixOS, so we replicate its *end-state* declaratively — emulators from nixpkgs
# + steam-rom-manager + the ~/Emulation tree, with user state riding the host's
# already-persisted /home (bind-mounted to /persistence/home → zero extra
# persistence config needed).
#
# This file owns the root option namespace + the emulator package set + udev +
# frontend. Content sync (02), control schemes (03) and the Sinden lightgun (04)
# live in the imported sub-files; they extend the SAME options.modules.emulation
# namespace.
#
# Host runs home-manager as a NixOS module, so all user-level state is set via
# config.home-manager.users.${cfg.user}.* — NOT bare home.*.
#
# LEGAL: this module ships NO copyrighted bytes. ROMs, BIOS, prod.keys/title.keys
# and firmware are the user's responsibility (own-console / own-disc dumps only)
# and are synced to the persisted /home disk by content.nix — never the store.
{ config, lib, pkgs, ... }:
let
  cfg = config.modules.emulation;
in
{
  imports = [
    ./content.nix # options.modules.emulation.content.* + B2 manifest sync (02)
    ./controls.nix # options.modules.emulation.controls.* + input configs (03)
    ./sinden.nix # options.modules.emulation.sinden.*  (04, experimental, off)
  ];

  options.modules.emulation = {
    enable = lib.mkEnableOption "EmuDeck-equivalent emulation stack";

    user = lib.mkOption {
      type = lib.types.str;
      default = "ali";
      description = ''
        User that owns the emulation stack. All emulator packages, content-sync
        user services, input configs and Switch keys/firmware are installed into
        this user's home-manager configuration.
      '';
    };

    frontend = lib.mkOption {
      type = lib.types.enum [ "none" "retrodeck-flatpak" ];
      default = "none";
      description = ''
        Console frontend.

        - "none": no dedicated frontend; use Steam ROM Manager + Gaming Mode (the
          simplest, most reliable path on this Jovian host). Desktop mode picks up
          the per-emulator .desktop entries from the nixpkgs packages.
        - "retrodeck-flatpak": install the RetroDeck Flatpak
          (net.retrodeck.retrodeck) via nix-flatpak. ES-DE itself is no longer
          packaged in nixpkgs (removed 2025-10-23 over freeimage CVEs), so the
          Flatpak is the only maintained ES-DE-style frontend. Prefer user-mode
          install (data under ~/.var/app, already persisted).
      '';
    };

    switch = {
      enable = lib.mkEnableOption "Nintendo Switch emulation (keys/firmware are own-dumps only)";

      emulator = lib.mkOption {
        type = lib.types.enum [ "citron" "ryubing" "eden" ];
        default = "citron";
        description = ''
          Which Yuzu-lineage Switch emulator to install (post-Yuzu-DMCA, 2026).

          - "citron":  this repo's overlay derivation (pkgs/citron, built from
                       github.com/citron-neo/emulator). NB: upstream pkgs.citron
                       is an unrelated MIT Rust crate — this only resolves to the
                       emulator because the host applies self.overlays.additions.
          - "ryubing": nixpkgs `ryubing` (MIT Ryujinx community fork). Ships NO
                       udev rule.
          - "eden":    nixpkgs `eden` source build. Ships 72-yuzu-input.rules
                       (Switch-controller HID uaccess), wired via services.udev
                       below.

          Keys/firmware placement differs per fork (Yuzu forks use
          ~/.local/share/<emu>/{keys,nand}; Ryujinx uses ~/.config/Ryujinx/...);
          content.nix handles the symlinking via its `symlinkInto` sets.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # All emulator binaries live in the user's profile (home-manager) so their
    # .desktop entries land in the user's menu and state persists with /home.
    home-manager.users.${cfg.user}.home.packages = with pkgs; [
      # Multi-system via libretro. PS1 is handled here through swanstation (a
      # free DuckStation-fork core) because standalone `duckstation` was removed
      # from nixpkgs (relicensed cc-by-nc-nd, 2026-03-14). snes9x + genesis-plus-gx
      # cover SNES + Genesis/MD; further cores can be added in this lambda.
      (retroarch.withCores (c: with c; [
        swanstation
        snes9x
        genesis-plus-gx
      ]))

      # Standalone emulators (verified nixpkgs attrs — see design/01-architecture.md).
      pcsx2 # PS2          (x86_64-linux only; fine on the Deck)
      dolphin-emu # GC/Wii        (attr is dolphin-emu, NOT dolphin = KDE file mgr)
      rpcs3 # PS3
      cemu # Wii U         (x86_64-linux only)
      xemu # Xbox (OG)
      ppsspp # PSP           (= ppsspp-sdl)
      melonds # DS            (lowercase attr)
      mgba # GBA
      flycast # Dreamcast/Naomi
      mame # Arcade
      azahar # 3DS           (Citra successor; config at ~/.config/azahar-emu/)

      # Steam glue: writes non-Steam shortcuts + artwork into Steam userdata for
      # Gaming Mode. Free (GPL-3.0-only); x86_64-linux only.
      steam-rom-manager
    ]
    # Switch emulator (own-dumps only for keys/firmware; see content.nix).
    ++ lib.optional cfg.switch.enable (
      # pkgs.citron here is this repo's overlay emulator, not upstream's Rust
      # crate — only valid because the host applies self.overlays.additions.
      if cfg.switch.emulator == "citron" then pkgs.citron
      else if cfg.switch.emulator == "ryubing" then pkgs.ryubing
      else pkgs.eden
    );

    # Switch-controller HID uaccess rule. Only `eden`'s package ships a usable
    # udev rule (72-yuzu-input.rules); citron/ryubing ship none, so we always
    # source the rule from pkgs.eden when Switch emulation is enabled regardless
    # of the chosen emulator — the rule is emulator-agnostic (it just grants the
    # logged-in user access to Switch controllers over hidraw). The `input` group
    # (granted on the host) separately governs /dev/input/event*, which is
    # distinct from this HID uaccess.
    services.udev.packages = lib.mkIf cfg.switch.enable [ pkgs.eden ];

    # Optional RetroDeck (ES-DE) frontend via nix-flatpak (already imported by
    # the host). Only added when frontend = "retrodeck-flatpak". User-mode keeps
    # its data under the user's ~/.var/app (persisted with /home); first-run
    # setup + Gaming-Mode shortcut launch remain a one-time manual step.
    services.flatpak = lib.mkIf (cfg.frontend == "retrodeck-flatpak") {
      enable = true;
      packages = [ "net.retrodeck.retrodeck" ];
    };
  };
}
