{ config, lib, pkgs, ... }:
let
  cfg = config.modules.desktop-wm-plasma6;
in
{
  options.modules.desktop-wm-plasma6 = {
    enable = lib.mkEnableOption "KDE Plasma 6 desktop environment";
  };

  config = lib.mkIf cfg.enable {
    environment.sessionVariables = {
      NIX_PROFILES = "${pkgs.lib.concatStringsSep " " (pkgs.lib.reverseList config.environment.profiles)}";
    };

    programs.dconf.enable = true;
    environment.systemPackages = with pkgs; [
      kdePackages.qtbase.out
      kdePackages.plasma-browser-integration
    ];

    services = {
      desktopManager = {
        plasma6 = {
          enable = true;
        };
      };
      displayManager.defaultSession = "plasma";
    };
  };
}
