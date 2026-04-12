{ config, lib, pkgs, ... }:
let
  cfg = config.modules.hardware-touchpad;
in
{
  options.modules.hardware-touchpad = {
    enable = lib.mkEnableOption "touchpad support with libinput gestures";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      libinput-gestures
    ];

    services.libinput.touchpad = {
      tapping = true;
    };
  };
}
