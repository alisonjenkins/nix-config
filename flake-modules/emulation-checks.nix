# Bitrot guard for the EmuDeck control configs (audit follow-up #18).
#
# modules/emulation/controls-emudeck.nix references files inside a pinned
# EmuDeck checkout by store path; a bad rev bump would only fail at home-manager
# activation. This check fetches the SAME pin (shared ./emudeck-pin.nix) and
# asserts the referenced config paths exist — so `nix flake check` catches a
# bump that moved/renamed them before it ships.
{ self, ... }:
{
  perSystem = { pkgs, ... }:
    let
      lib = pkgs.lib;
      pin = import (self + "/modules/emulation/emudeck-pin.nix");
      src = pkgs.fetchFromGitHub { inherit (pin) owner repo rev sha256; };
      # Representative subset across all three shipped emulators — enough to
      # catch a rev that reorganised the configs/ tree.
      files = [
        "configs/org.DolphinEmu.dolphin-emu/config/dolphin-emu/GCPadNew.ini"
        "configs/org.DolphinEmu.dolphin-emu/config/dolphin-emu/WiimoteNew.ini"
        "configs/org.DolphinEmu.dolphin-emu/config/dolphin-emu/Hotkeys.ini"
        "configs/org.ppsspp.PPSSPP/config/ppsspp/PSP/SYSTEM/controls.ini"
        "configs/org.flycast.Flycast/config/flycast/mappings/SDL_controller_neptune.cfg"
      ];
    in
    {
      checks.emudeck-config-paths = pkgs.runCommand "emudeck-config-paths" { } ''
        miss=0
        ${lib.concatMapStringsSep "\n" (f: ''
          if [ ! -f ${src}/${f} ]; then echo "MISSING (EmuDeck pin moved?): ${f}" >&2; miss=1; fi
        '') files}
        if [ "$miss" != 0 ]; then
          echo "emudeck-config-paths: pinned config files missing — re-check controls-emudeck.nix paths after the rev bump in emudeck-pin.nix" >&2
          exit 1
        fi
        touch $out
      '';
    };
}
