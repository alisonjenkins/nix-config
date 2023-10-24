{ config, pkgs, lib, system, ... }:
{
  services = {
    xserver = {
      displayManager = {
        lightdm = {
          enable = true;
          greeters.slick.enable = true;
        };
      };
    };
  };
}
