{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.fx-cast;
in
{
  options.services.fx-cast = {
    enable = mkEnableOption (mdDoc "the fx_cast_bridge for Chromecast support in Firefox");

    package = mkOption {
      type = types.package;
      default = pkgs.fx-cast-bridge;
      defaultText = literalExpression "pkgs.fx-cast-bridge";
      description = mdDoc "The fx_cast-bridge package to use.";
    };

    user = mkOption {
      description = mdDoc "The user account under which the fx-cast-bridge service will run.";
      example = "jane";
      type = types.str;
    };
  };

  config = mkIf cfg.enable {
    systemd.services.fx-cast-bridge = {
      after = [ "network.target" ];
      description = "fx_cast_bridge for Chromecast support in Firefox";
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        # Environment = "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/%U/bus";
        ExecStart = "${cfg.package}/bin/fx_cast_bridge -d";
        Restart = "on-failure";
        RestartSec = "5s";
        Type = "simple";
        User = cfg.user;
      };
    };
  };
}
