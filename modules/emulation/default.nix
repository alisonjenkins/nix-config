# EmuDeck-equivalent emulation stack (native replication, not packaged EmuDeck).
#
# See modules/emulation/design/ for the full rationale. Headline: EmuDeck is an
# imperative Flatpak/AppImage installer that fights immutable + impermanent
# NixOS, so we replicate its *end-state* declaratively — emulators from nixpkgs
# + steam-rom-manager + the ~/Emulation tree, with user state riding the host's
# already-persisted /home (bind-mounted to /persistence/home → zero extra
# persistence config needed).
#
# This file owns the root option namespace + the per-console model + the
# computed emulator package set + udev + frontend. Content sync (02), control
# schemes (03) and the Sinden lightgun (04) live in the imported sub-files; they
# extend the SAME options.modules.emulation namespace.
#
# PER-CONSOLE MODEL: `consoles.<name>` (names from ./catalogue.nix) each carry a
# single `enable` toggle that gates that console's emulators, its games (content
# sync), and its per-console RetroFE theme together. `emulators` is a LIST so a
# console can install multiple backends (e.g. PS1 via swanstation + beetle-psx).
# The module installs only the union of backends across ENABLED consoles, so the
# closure scales with what you actually turn on.
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
  catalogue = import ./catalogue.nix;

  # Per-console option submodule, generated from each catalogue entry so the
  # `emulators` enum is constrained to that console's valid backends.
  consoleOptions = name: cons: {
    enable = lib.mkEnableOption "the ${name} console (its emulators + games + theme)";

    emulators = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (lib.attrNames cons.backends));
      default = cons.default;
      description = ''
        Backend(s) to install for ${name}. Multiple allowed. Valid keys:
        ${lib.concatStringsSep ", " (lib.attrNames cons.backends)}.
        "retroarch-*" keys pull a libretro core into the shared RetroArch build;
        the rest are standalone emulator packages.
      '';
    };

    games = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Explicit ROM filenames for this console (relative to its B2 prefix
        roms/${cons.romDir}/). Synced to ~/Emulation/roms/${cons.romDir} when the
        console is enabled; the dir is reconciled to exactly this list (unlisted
        files pruned). Requires modules.emulation.content.enable + B2 creds.
      '';
    };

    theme = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Optional per-console RetroFE layout directory. When set, it is dropped
        into the RetroFE layout's collections/${name}/layout/ so this console
        gets its own look (RetroFE resolves a per-collection layout there,
        falling back to the global layout). null = use the global layout.
      '';
    };
  };

  # All enabled consoles, and the union of their chosen backend specs.
  enabledConsoles = lib.filterAttrs (_n: c: c.enable) cfg.consoles;
  chosenSpecs = lib.concatLists (lib.mapAttrsToList
    (name: c: map (e: catalogue.${name}.backends.${e}) c.emulators)
    enabledConsoles);

  standaloneAttrs = lib.unique (map (s: s.pkg) (lib.filter (s: s ? pkg) chosenSpecs));
  retroCores = lib.unique (map (s: s.core) (lib.filter (s: s ? core) chosenSpecs));

  standalonePackages = map (a: pkgs.${a}) standaloneAttrs;
  # Single RetroArch build carrying exactly the cores the enabled consoles use.
  retroarchPackage = lib.optional (retroCores != [ ])
    (pkgs.retroarch.withCores (cores: map (n: cores.${n}) retroCores));

  # Switch console drives the controller udev rule (eden ships the real one).
  switchEnabled = cfg.consoles.switch.enable;
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
        User that owns the emulation stack. Emulator packages, content-sync user
        services, input configs, themes and Switch keys/firmware are installed
        into this user's home-manager configuration.
      '';
    };

    frontend = lib.mkOption {
      type = lib.types.enum [ "none" "retrofe" "retrodeck-flatpak" ];
      default = "none";
      description = ''
        Pretty selection frontend.

        - "none": Steam ROM Manager + Gaming Mode only (desktop picks up the
          per-emulator .desktop entries).
        - "retrofe": RetroFE (chosen frontend — HyperSpin-style animated wheels +
          video; collections derived from enabled consoles, per-console themes
          via consoles.<name>.theme). Wiring lives in the frontend sub-module
          (see design/05-frontend.md); this enum only records the choice for now.
        - "retrodeck-flatpak": RetroDeck (ES-DE) flatpak — not declarative; ES-DE
          is no longer in nixpkgs.
      '';
    };

    consoles = lib.mkOption {
      default = { };
      description = ''
        Per-console configuration. Each console's single `enable` toggle gates
        its emulators, its games (content sync) and its per-console theme. Only
        the union of backends across ENABLED consoles is installed.
      '';
      type = lib.types.submodule {
        options = lib.mapAttrs
          (name: cons: lib.mkOption {
            type = lib.types.submodule { options = consoleOptions name cons; };
            default = { };
            description = "The ${name} console (romDir roms/${cons.romDir}).";
          })
          catalogue;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Emulator binaries live in the user's profile (home-manager) so their
    # .desktop entries land in the user's menu and state persists with /home.
    # Only the union of backends across enabled consoles + steam-rom-manager.
    home-manager.users.${cfg.user}.home.packages =
      standalonePackages
      ++ retroarchPackage
      ++ [ pkgs.steam-rom-manager ];

    # Switch-controller HID uaccess rule. Only eden's package ships a usable rule
    # (72-yuzu-input.rules); citron/ryubing ship none, so source it from eden
    # whenever the Switch console is enabled (the rule is emulator-agnostic — it
    # just grants the seat user access to Switch controllers over hidraw).
    services.udev.packages = lib.mkIf switchEnabled [ pkgs.eden ];

    # Optional RetroDeck (ES-DE) flatpak via nix-flatpak (already imported by the
    # host). RetroFE wiring is handled in the frontend sub-module.
    services.flatpak = lib.mkIf (cfg.frontend == "retrodeck-flatpak") {
      enable = true;
      packages = [ "net.retrodeck.retrodeck" ];
    };
  };
}
