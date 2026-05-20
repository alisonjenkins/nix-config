{ lib, config, ... }:

let
  cfg = config.programs.scopebuddy;
in
{
  options.programs.scopebuddy = {
    enable = lib.mkEnableOption "ScopeBuddy gamescope wrapper config";

    gamescopeArgs = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "-W 2560 -H 1440 -w 2560 -h 1440 -b";
      description = ''
        Value for SCB_GAMESCOPE_ARGS. Passed to every gamescope launch
        unless overridden by a per-game config in ~/.config/scopebuddy/AppID/.
      '';
    };

    autoRes = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Auto-detect display resolution and set -W/-H.";
    };

    autoHdr = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Auto-enable HDR if the primary display supports it.";
    };

    autoVrr = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Auto-enable adaptive sync if VRR is active on the display.";
    };

    autoRefresh = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Auto-set explicit refresh rate (-r) to monitor's. Conflicts with VRR.";
    };

    autoFrameLimit = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Auto-set --framerate-limit to monitor refresh. Conflicts with VRR.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra bash appended to scb.conf.";
    };
  };

  config = lib.mkIf cfg.enable {
    xdg.configFile."scopebuddy/scb.conf".text = ''
      # Managed by home-manager — programs.scopebuddy
    '' + lib.optionalString (cfg.gamescopeArgs != "") ''
      export SCB_GAMESCOPE_ARGS="${cfg.gamescopeArgs}"
    '' + lib.optionalString cfg.autoRes "SCB_AUTO_RES=1\n"
      + lib.optionalString cfg.autoHdr "SCB_AUTO_HDR=1\n"
      + lib.optionalString cfg.autoVrr "SCB_AUTO_VRR=1\n"
      + lib.optionalString cfg.autoRefresh "SCB_AUTO_REFRESH=1\n"
      + lib.optionalString cfg.autoFrameLimit "SCB_AUTO_FRAME_LIMIT=1\n"
      + cfg.extraConfig;
  };
}
