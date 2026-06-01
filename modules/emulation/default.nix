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
# PER-PLATFORM MODEL: `platforms.<name>` (names from ./catalogue.nix; "platform"
# not "console" since the set includes arcade, handhelds, PC-ish targets) each
# carry a single `enable` toggle that gates that platform's emulators, its games
# (content sync), and its per-platform RetroFE theme together. `emulators` is a
# LIST so a platform can install multiple backends (e.g. PS1 via swanstation +
# beetle-psx). Individual games may override which of those emulators launches
# them (games = [ "x.chd" { file = "y.chd"; emulator = "..."; } ]). The module
# installs only the union of backends across ENABLED platforms, so the closure
# scales with what you actually turn on.
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

  # Per-platform option submodule, generated from each catalogue entry so the
  # `emulators` enum (and the per-game emulator override) is constrained to that
  # platform's valid backends.
  platformOptions = name: plat: {
    enable = lib.mkEnableOption "the ${name} platform (its emulators + games + theme)";

    emulators = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (lib.attrNames plat.backends));
      default = plat.default;
      description = ''
        Backend(s) to install for ${name}. Multiple allowed. Valid keys:
        ${lib.concatStringsSep ", " (lib.attrNames plat.backends)}.
        "retroarch-*" keys pull a libretro core into the shared RetroArch build;
        the rest are standalone emulator packages. The first entry is the
        platform's PRIMARY emulator (used for games that don't override it).
      '';
    };

    games = lib.mkOption {
      type = lib.types.listOf (lib.types.either lib.types.str (lib.types.submodule {
        options = {
          file = lib.mkOption {
            type = lib.types.str;
            description = "ROM filename relative to roms/${plat.romDir}/ in the B2 bucket.";
          };
          emulator = lib.mkOption {
            type = lib.types.nullOr (lib.types.enum (lib.attrNames plat.backends));
            default = null;
            description = ''
              Override which of this platform's emulators launches this game
              (one of: ${lib.concatStringsSep ", " (lib.attrNames plat.backends)}).
              null = the platform's primary (first `emulators`) backend. Consumed
              by the RetroFE per-game launcher wiring; content sync only uses the
              filename.
            '';
          };
        };
      }));
      default = [ ];
      description = ''
        Games for this platform. Either a bare ROM filename (uses the platform's
        primary emulator) or { file; emulator; } to pick a specific installed
        emulator for that game. Filenames are relative to the B2 prefix
        roms/${plat.romDir}/. Synced to ~/Emulation/roms/${plat.romDir} when the
        platform is enabled; the dir is reconciled to exactly this list (unlisted
        pruned). Requires modules.emulation.content.enable + B2 creds.
      '';
    };

    theme = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Optional per-platform RetroFE layout directory. When set, it is dropped
        into the RetroFE layout's collections/${name}/layout/ so this platform
        gets its own look (RetroFE resolves a per-collection layout there,
        falling back to the global layout). null = use the global layout.
      '';
    };
  };

  # All enabled platforms, and the union of their chosen backend specs.
  enabledPlatforms = lib.filterAttrs (_n: p: p.enable) cfg.platforms;
  chosenSpecs = lib.concatLists (lib.mapAttrsToList
    (name: p: map (e: catalogue.${name}.backends.${e}) p.emulators)
    enabledPlatforms);

  standaloneAttrs = lib.unique (map (s: s.pkg) (lib.filter (s: s ? pkg) chosenSpecs));
  retroCores = lib.unique (map (s: s.core) (lib.filter (s: s ? core) chosenSpecs));

  standalonePackages = map (a: pkgs.${a}) standaloneAttrs;
  # Single RetroArch build carrying exactly the cores the enabled consoles use.
  retroarchPackage = lib.optional (retroCores != [ ])
    (pkgs.retroarch.withCores (cores: map (n: cores.${n}) retroCores));

  # Switch platform drives the controller udev rule (eden ships the real one).
  switchEnabled = cfg.platforms.switch.enable;
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

    platforms = lib.mkOption {
      default = { };
      description = ''
        Per-platform configuration. Each platform's single `enable` toggle gates
        its emulators, its games (content sync) and its per-platform theme. Only
        the union of backends across ENABLED platforms is installed. Platform
        names (nes, snes, arcade, switch, ...) come from ./catalogue.nix.
      '';
      type = lib.types.submodule {
        options = lib.mapAttrs
          (name: plat: lib.mkOption {
            type = lib.types.submodule { options = platformOptions name plat; };
            default = { };
            description = "The ${name} platform (romDir roms/${plat.romDir}).";
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
