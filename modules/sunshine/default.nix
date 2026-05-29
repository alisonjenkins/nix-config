{ config, lib, pkgs, ... }:
let
  cfg = config.modules.sunshine;
in
{
  options.modules.sunshine = {
    enable = lib.mkEnableOption "Sunshine remote desktop/game streaming host";

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Start Sunshine automatically with the user session";
    };

    capSysAdmin = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Grant CAP_SYS_ADMIN to the Sunshine binary (needed for KMS capture on Wayland)";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall ports Sunshine uses";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.unstable.sunshine;
      defaultText = lib.literalExpression "pkgs.unstable.sunshine";
      description = "The Sunshine package to use";
    };

    applications = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Sunshine applications configuration (env + apps) passed through to services.sunshine.applications";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Extra settings passed through to services.sunshine.settings";
    };
  };

  config = lib.mkIf cfg.enable {
    services.sunshine = {
      enable = true;
      inherit (cfg) autoStart capSysAdmin openFirewall package applications settings;
    };
  };
}
