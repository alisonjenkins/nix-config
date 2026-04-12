{ config, lib, pkgs, ... }:
let
  cfg = config.modules.desktop-wm-sway;
in
{
  options.modules.desktop-wm-sway = {
    enable = lib.mkEnableOption "Sway window manager";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      grim
      mako
      slurp
      wl-clipboard
    ];

    programs.sway = {
      enable = true;
      wrapperFeatures.gtk = true;
    };

    security.pam.loginLimits = [
      { domain = "@users"; item = "rtprio"; type = "-"; value = 1; }
    ];
  };
}
