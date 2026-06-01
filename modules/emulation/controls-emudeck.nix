# modules/emulation/controls-emudeck.nix
#
# EmuDeck's curated STANDALONE-emulator control schemes, shipped declaratively
# (design/03 headline #3: "standalone per-emulator configs to be sourced from
# EmuDeck templates"). EmuDeck stores these as static config trees under
# configs/<flatpak-id>/ that its install scripts cp into the Flatpak ~/.var/app
# tree; we pin that checkout and symlink the input files into the nixpkgs
# config paths (design/03 §3.2) by populating controls.standalone — so the
# existing read-only home.file plumbing in controls.nix carries them.
#
# WHY ONLY A SUBSET: a config is shipped here only when its INPUT bindings live
# in a DEDICATED file (so a read-only symlink can't clobber unrelated settings):
#   - Dolphin  GCPadNew.ini / WiimoteNew.ini / Hotkeys.ini  (input-only files)
#   - PPSSPP   PSP/SYSTEM/controls.ini                       (input-only file)
#   - Flycast  mappings/<device>.cfg                         (per-device files)
# DEFERRED (input is embedded in a monolithic settings file that also carries
# BIOS/ROM paths + window state + is rewritten on exit → shipping whole would
# clobber):
#   - PCSX2    PCSX2.ini  ([Pad1]/[Hotkeys] inline with [Folders]/[GameList])
#   - melonDS  melonDS.ini (Joy_*/HKKey_* inline with BIOS paths + [Display])
#   - MAME     ctrlr/default.cfg is clean, but needs `-ctrlr default` on the
#              launch line + an uncertain nixpkgs ctrlr search path — left for a
#              follow-up that also wires the RetroFE mame launcher flag.
#
# DEVICE TARGETING: EmuDeck's Dolphin/Flycast profiles target the SDL names
# "Steam Deck Controller" / "Steam Virtual Gamepad" / "controller_neptune" —
# i.e. the Deck's pad and Steam Input's virtual pad. That's exactly our primary
# path (RetroFE launched from Steam → emulators inherit Steam Input's virtual
# xbox360 pad; design/03 §3.3), so these map out-of-the-box there. A pad with a
# different SDL name (external controller, or desktop-direct launch outside
# Steam) won't match and needs its own in-emulator bind step.
#
# Read-only is safe even for emulators that rewrite their config on exit: the
# store symlink target is on a read-only fs, so the write fails gracefully and
# our declarative config stays authoritative (same principle as RetroArch's
# config_save_on_exit=false in controls.nix).
{ config, lib, pkgs, ... }:
let
  cfg = config.modules.emulation;
  ccfg = cfg.controls;

  # Pinned EmuDeck checkout — rev/hash live in ./emudeck-pin.nix (shared with
  # the flake.checks bitrot guard). Bump there + re-verify the configs/<id>
  # paths below.
  emudeckPin = import ./emudeck-pin.nix;
  emudeckSrc = pkgs.fetchFromGitHub { inherit (emudeckPin) owner repo rev sha256; };

  # A platform's backend is active iff the platform is enabled and lists it.
  uses = platform: backend:
    cfg.platforms.${platform}.enable && lib.elem backend cfg.platforms.${platform}.emulators;

  dolphinActive = uses "gamecube" "dolphin" || uses "wii" "dolphin";
  ppssppActive = uses "psp" "ppsspp";
  flycastActive = uses "dreamcast" "flycast";

  dolphinDir = "${emudeckSrc}/configs/org.DolphinEmu.dolphin-emu/config/dolphin-emu";
  ppssppDir = "${emudeckSrc}/configs/org.ppsspp.PPSSPP/config/ppsspp/PSP/SYSTEM";
  flycastMapDir = "${emudeckSrc}/configs/org.flycast.Flycast/config/flycast/mappings";

  flycastMappings = [
    "SDL_Keyboard.cfg"
    "SDL_Keyboard_arcade.cfg"
    "SDL_Microsoft X-Box 360 pad 0.cfg"
    "SDL_controller_neptune.cfg"
    "SDL_controller_neptune_arcade.cfg"
  ];
  sanitize = s: lib.replaceStrings [ " " ] [ "-" ] s;

  dolphinEntries = {
    emudeck-dolphin-gcpad = {
      configFile = "${dolphinDir}/GCPadNew.ini";
      targetPath = ".config/dolphin-emu/GCPadNew.ini";
    };
    emudeck-dolphin-wiimote = {
      configFile = "${dolphinDir}/WiimoteNew.ini";
      targetPath = ".config/dolphin-emu/WiimoteNew.ini";
    };
    emudeck-dolphin-hotkeys = {
      configFile = "${dolphinDir}/Hotkeys.ini";
      targetPath = ".config/dolphin-emu/Hotkeys.ini";
    };
  };

  ppssppEntries = {
    emudeck-ppsspp-controls = {
      configFile = "${ppssppDir}/controls.ini";
      targetPath = ".config/ppsspp/PSP/SYSTEM/controls.ini";
    };
  };

  flycastEntries = lib.listToAttrs (map
    (f: lib.nameValuePair "emudeck-flycast-${sanitize f}" {
      configFile = "${flycastMapDir}/${f}";
      targetPath = ".config/flycast/mappings/${f}";
    })
    flycastMappings);
in
{
  options.modules.emulation.controls.emudeckStandaloneDefaults =
    lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Ship EmuDeck's curated standalone-emulator control schemes (Dolphin,
        PPSSPP, Flycast) for whichever of those backends an enabled platform
        uses, by populating controls.standalone. Requires controls.enable. Set
        false to manage those configs yourself via controls.standalone.
      '';
    };

  config = lib.mkIf (cfg.enable && ccfg.enable && ccfg.emudeckStandaloneDefaults) {
    modules.emulation.controls.standalone = lib.mkMerge [
      (lib.mkIf dolphinActive dolphinEntries)
      (lib.mkIf ppssppActive ppssppEntries)
      (lib.mkIf flycastActive flycastEntries)
    ];
  };
}
