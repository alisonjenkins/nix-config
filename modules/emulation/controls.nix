# Declarative emulator control schemes (per design/03-control-schemes.md).
#
# Controls are the *strong* declarative case for this stack: every targeted
# emulator stores its input bindings as plain text, so we ship them verbatim
# via home-manager `home.file`. The one genuinely non-declarative dependency is
# Steam Input (§3.3) — the template `.vdf` files ARE declarable, but the
# per-shortcut template->AppID *assignment* lives under Steam's `userdata/`
# keyed by the runtime AppID + SteamID3 and is written by steam-rom-manager
# after a shortcut is imported. We ship the templates and let SRM do the apply;
# we never hand-write the assignment in Nix.
#
# IMPORTANT (host runs home-manager as a NixOS module): all user-level state
# MUST go through `config.home-manager.users.${cfg.user}`, never a bare
# `home.file`. This file is a standalone NixOS module extending the shared
# `options.modules.emulation.*` namespace.
{ config, lib, pkgs, ... }:
let
  cfg = config.modules.emulation;
  ccfg = cfg.controls;
  rcfg = ccfg.retroarch;

  # ── RetroArch unified hotkey block (EmuDeck values) ──────────────────────
  #
  # Verbatim from EmuDeck's `functions/EmuScripts/RetroArch_maincfg.sh`,
  # rewritten for the nixpkgs `retroarch` paths (EmuDeck targets the Flatpak
  # `~/.var/app/org.libretro.RetroArch/...` tree; nixpkgs uses
  # `~/.config/retroarch/`).
  #
  #   input_enable_hotkey_btn = "4"  -> Select (hold to arm hotkeys)
  #   input_save_state_btn    = "10" -> R1
  #   input_load_state_btn    = "9"  -> L1
  #   input_pause_toggle_btn  = "0"  -> B
  #
  # Menu/quit use *combos* (no single hotkey button) — the combo enum is
  # POSITIONAL and confirmed against RetroArch source `input/input_defines.h`
  # (`enum input_combo_type`, tag v1.22.0 == nixpkgs 1.22.2):
  #   0=NONE  1=DOWN_Y_L_R  2=L3_R3  3=L1_R1_START_SELECT  4=START_SELECT ...
  # It is append-only historically but positional — RE-VERIFY ON ANY RETROARCH
  # BUMP. We pin:
  #   input_menu_toggle_gamepad_combo = "2"  -> L3+R3
  #   input_quit_gamepad_combo        = "4"  -> Select+Start
  # and disable the single-button menu/exit so the combos are authoritative.
  #
  # `config_save_on_exit = "false"` is MANDATORY (§3.4): RetroArch rewrites
  # retroarch.cfg on exit, which would clobber our read-only home.file symlink.
  # With it off the file we ship stays authoritative.
  hotkeyBlock = ''
    config_save_on_exit = "false"
    notification_show_autoconfig = "false"
    menu_swap_ok_cancel_buttons = "true"
    rewind_enable = "false"
    input_hotkey_block_delay = "5"
    input_joypad_driver = "udev"

    input_enable_hotkey_btn = "4"
    input_save_state_btn = "10"
    input_load_state_btn = "9"
    input_pause_toggle_btn = "0"

    input_menu_toggle_gamepad_combo = "2"
    input_quit_gamepad_combo = "4"
    input_exit_emulator_btn = "nul"
    input_menu_toggle_btn = "nul"

    input_menu_toggle = "f1"
    input_exit_emulator = "escape"
    input_save_state = "f2"
    input_load_state = "f4"
    input_state_slot_increase = "f7"
    input_state_slot_decrease = "f6"
    input_toggle_fast_forward = "space"
    input_pause_toggle = "p"
  '';

  # ── Device reservation lines (PR #16647) ─────────────────────────────────
  #
  # We deliberately DO NOT emit `input_player<N>_joypad_index`: that index
  # reflects volatile OS enumeration order and reshuffles on
  # connect/disconnect/dock (RetroArch issues #13294 / #13180). EmuDeck writes
  # the identity mapping (== RetroArch's own default), so omitting it changes
  # nothing for the single internal-pad case.
  #
  # For multi-pad / docked setups, device reservation is the stable primitive:
  #   input_player<N>_reserved_device  = "<name>"
  #   input_player<N>_vendor_id        = "<int>"   (optional)
  #   input_player<N>_product_id       = "<int>"   (optional)
  #   input_player<N>_device_reservation_type = "reserved" | "preferred"
  reservationLine = r:
    ''
      input_player${toString r.player}_reserved_device = "${r.deviceName}"
      input_player${toString r.player}_device_reservation_type = "${r.reservation}"
    ''
    + lib.optionalString (r.vendorId != null) ''
      input_player${toString r.player}_vendor_id = "${toString r.vendorId}"
    ''
    + lib.optionalString (r.productId != null) ''
      input_player${toString r.player}_product_id = "${toString r.productId}"
    '';

  reservationBlock = lib.concatStringsSep "" (map reservationLine rcfg.deviceReservations);

  # Full retroarch.cfg text. Only emitted when the EmuDeck scheme is selected;
  # `hotkeyScheme = "none"` ships nothing (lets the user keep RetroArch's own
  # config writable).
  retroarchCfgText = hotkeyBlock + reservationBlock;

  # ── home.file aggregation ────────────────────────────────────────────────
  #
  # Everything is assembled into a single attrset keyed by HOME-relative path
  # and merged into the user's home.file. Read-only entries are plain
  # `source = <store path>` symlinks (home-manager's default), which is exactly
  # what §3.4 calls "read-only" — the emulators only rewrite these on an
  # explicit in-GUI save, so a store symlink is safe.

  # 1. retroarch.cfg (only for the emudeck scheme).
  retroarchFiles = lib.optionalAttrs (rcfg.enable && rcfg.hotkeyScheme == "emudeck") {
    ".config/retroarch/retroarch.cfg".text = retroarchCfgText;
  };

  # 2. autoconfig profiles -> autoconfig/udev/<name>.cfg
  #    Auto-bound by RetroArch's udev joypad driver via vid:pid + name. The
  #    `udev` subdir matches `input_joypad_driver = "udev"` above.
  autoconfigFiles = lib.optionalAttrs rcfg.enable (
    lib.mapAttrs' (
      name: src:
      lib.nameValuePair ".config/retroarch/autoconfig/udev/${name}.cfg" { source = src; }
    ) rcfg.autoconfigProfiles
  );

  # 3. remaps -> config/remaps/<core>/<core>.rmp
  #    The attr name is the HOME-relative tail under config/remaps/ (e.g.
  #    "Beetle PSX/Beetle PSX.rmp"), so per-core/per-content layouts both work.
  remapFiles = lib.optionalAttrs rcfg.enable (
    lib.mapAttrs' (
      name: src:
      lib.nameValuePair ".config/retroarch/config/remaps/${name}" { source = src; }
    ) rcfg.remaps
  );

  # 4. standalone per-emulator config files shipped verbatim at targetPath.
  #    home.file symlinks are read-only by construction; `readOnly = false`
  #    copies the file into $HOME and makes it writable (`mutable`) so the
  #    emulator can rewrite it — used for the rare emulator that insists on
  #    writing UI state back into the same file we seed.
  standaloneFiles = lib.mapAttrs' (
    _name: spec:
    lib.nameValuePair spec.targetPath (
      { source = spec.configFile; } // lib.optionalAttrs (!spec.readOnly) { mutable = true; }
    )
  ) (lib.filterAttrs (_n: spec: spec.configFile != null) ccfg.standalone);

  # 5. Steam Input templates -> controller_base/templates/<name>.vdf
  #    Plain-text .vdf, keep the extension. The per-AppID assignment is NOT
  #    declared here (see header) — SRM writes it after shortcut import. Only
  #    applies in Gaming Mode / gamescope; in Plasma the emulator-native input
  #    configs above are the authoritative layer (steam-for-linux #8904).
  steamInputFiles = lib.optionalAttrs ccfg.steamInput.enable (
    lib.mapAttrs' (
      name: src:
      lib.nameValuePair ".local/share/Steam/controller_base/templates/${name}.vdf" {
        source = src;
      }
    ) ccfg.steamInput.templates
  );

  allHomeFiles =
    retroarchFiles // autoconfigFiles // remapFiles // standaloneFiles // steamInputFiles;
in
{
  options.modules.emulation.controls = {
    enable = lib.mkEnableOption "declarative emulator control schemes";

    retroarch = {
      enable = lib.mkEnableOption "RetroArch unified hotkeys + autoconfig + remaps";

      hotkeyScheme = lib.mkOption {
        type = lib.types.enum [ "emudeck" "none" ];
        default = "emudeck";
        description = ''
          Hotkey block to ship in retroarch.cfg. "emudeck" writes the EmuDeck
          unified hotkey layout (Select-armed hotkeys, L3+R3 menu, Select+Start
          quit) plus `config_save_on_exit = "false"` so the shipped read-only
          config is authoritative. "none" ships no retroarch.cfg.
        '';
      };

      autoconfigProfiles = lib.mkOption {
        type = lib.types.attrsOf lib.types.path;
        default = { };
        example = lib.literalExpression ''
          { "Steam Deck Controller" = ./profiles/steam-deck.cfg; }
        '';
        description = ''
          Per-controller autoconfig profiles, placed read-only at
          `~/.config/retroarch/autoconfig/udev/<name>.cfg`. Auto-bound by the
          udev joypad driver via vid:pid + name. Source these from
          `libretro/retroarch-joypad-autoconfig`.
        '';
      };

      remaps = lib.mkOption {
        type = lib.types.attrsOf lib.types.path;
        default = { };
        example = lib.literalExpression ''
          { "Beetle PSX/Beetle PSX.rmp" = ./remaps/beetle-psx.rmp; }
        '';
        description = ''
          Per-core (or per-content) input remaps. The attr name is the
          HOME-relative tail under `~/.config/retroarch/config/remaps/`
          (e.g. "<core>/<core>.rmp"). Read-only — RetroArch rewrites these only
          on an explicit in-GUI save.
        '';
      };

      deviceReservations = lib.mkOption {
        # PR #16647 device reservation — NOT joypad_index (volatile OS
        # enumeration order; issues #13294 / #13180). Leave empty for a single
        # internal pad.
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              player = lib.mkOption {
                type = lib.types.ints.positive;
                description = "RetroArch player slot (1-based).";
              };
              deviceName = lib.mkOption {
                type = lib.types.str;
                description = "Controller name to reserve for this player slot.";
              };
              vendorId = lib.mkOption {
                type = lib.types.nullOr lib.types.int;
                default = null;
                description = "Optional USB vendor id to disambiguate identical names.";
              };
              productId = lib.mkOption {
                type = lib.types.nullOr lib.types.int;
                default = null;
                description = "Optional USB product id to disambiguate identical names.";
              };
              reservation = lib.mkOption {
                type = lib.types.enum [ "reserved" "preferred" ];
                default = "reserved";
                description = ''
                  "reserved" pins the slot to this device only; "preferred"
                  prefers it but allows fallback.
                '';
              };
            };
          }
        );
        default = [ ];
        description = ''
          Stable per-player device reservations (PR #16647). Emits
          `input_player<N>_reserved_device` (+ optional vendor/product id) and
          `input_player<N>_device_reservation_type`. Use this instead of
          joypad_index for multi-pad / docked setups.
        '';
      };
    };

    standalone = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            configFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = ''
                Input config file shipped verbatim. null disables this entry
                (the option still evaluates).
              '';
            };
            targetPath = lib.mkOption {
              type = lib.types.str;
              example = ".config/azahar-emu/qt-config.ini";
              description = "HOME-relative destination path for the config file.";
            };
            readOnly = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = ''
                When true (default) the file is a read-only store symlink —
                safe for configs the emulator only rewrites on explicit save.
                Set false to copy a writable (mutable) file into $HOME for the
                rare emulator that rewrites the same file it reads from.
              '';
            };
          };
        }
      );
      default = { };
      example = lib.literalExpression ''
        {
          azahar = {
            configFile = ./standalone/azahar-qt-config.ini;
            targetPath = ".config/azahar-emu/qt-config.ini";
          };
        }
      '';
      description = ''
        Per-emulator standalone input config files shipped verbatim to
        `targetPath`. See the matrix in design/03-control-schemes.md §3.2 for
        each emulator's config path + format.
      '';
    };

    steamInput = {
      enable = lib.mkEnableOption "ship Steam Input templates (Gaming Mode only)";

      templates = lib.mkOption {
        type = lib.types.attrsOf lib.types.path;
        default = { };
        example = lib.literalExpression ''
          { "emudeck_retroarch" = ./steam-input/retroarch.vdf; }
        '';
        description = ''
          Steam Input controller template `.vdf` files, placed at
          `~/.local/share/Steam/controller_base/templates/<name>.vdf`. The
          per-shortcut template->AppID *assignment* is written imperatively by
          steam-rom-manager after a non-Steam shortcut is imported (keyed by
          Steam's runtime AppID + SteamID3 under userdata/) — it is NOT declared
          here. NB (steam-for-linux #8904): per-game layouts apply only in
          Gaming Mode / gamescope, not in Plasma desktop mode.
        '';
      };
    };
  };

  config = lib.mkIf (cfg.enable && ccfg.enable) {
    home-manager.users.${cfg.user}.home.file = allHomeFiles;
  };
}
