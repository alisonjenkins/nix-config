{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.modules.subnauticaVR;

  modPackage = pkgs.subnautica-vr-mods.override { inherit (cfg) mode; };

  syncScript = pkgs.writeShellApplication {
    name = "subnautica-vr-mod-sync";
    runtimeInputs = [ pkgs.rsync ];
    text = ''
      game_dir="${cfg.steamLibraryPath}/steamapps/common/Subnautica"

      if [ ! -d "$game_dir" ]; then
        echo "subnautica-vr-mod-sync: Subnautica not found at $game_dir, skipping mod sync" >&2
      else
        # -a from a read-only nix store path: file/dir modes land read-only
        # in $game_dir too, which is fine, BepInEx only ever reads these.
        rsync -a --checksum ${modPackage}/ "$game_dir"/
        echo "subnautica-vr-mod-sync: synced ${cfg.mode} mod payload into $game_dir" >&2
      fi

      # BepInEx.Subnautica's doorstop injects via a winhttp.dll placed in the
      # game dir; Wine only loads it in place of the system DLL when told to
      # via WINEDLLOVERRIDES, and only once, not always (winhttp is also a
      # normal Windows system DLL other overrides may already be listing).
      export WINEDLLOVERRIDES="winhttp=n,b''${WINEDLLOVERRIDES:+,$WINEDLLOVERRIDES}"
      exec "$@"
    '';
  };
in
{
  options.modules.subnauticaVR = {
    enable = lib.mkEnableOption "Subnautica VR mod sync (BepInEx + SubmersedVR/VR Enhancements)";

    mode = lib.mkOption {
      type = lib.types.enum [
        "submersed"
        "enhancements"
      ];
      default = "submersed";
      description = ''
        Which VR mod to layer on top of BepInEx. Upstream-documented as
        mutually exclusive, not stackable:

        - `submersed`: SubmersedVR — real motion-controller support, SteamVR
          only, explicitly WIP/unpolished upstream.
        - `enhancements`: Subnautica VR Enhancements — comfort/QoL fixes
          (HUD, PDA placement, subtitles, cursor, walk speed) for the
          original gamepad/keyboard-driven native VR mode. More polished,
          no motion controllers.
      '';
    };

    steamLibraryPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.local/share/Steam";
      description = ''
        Steam library root containing `steamapps/common/Subnautica`. Override
        for a game installed on a secondary library folder.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ syncScript ];
  };
}
