{ config, lib, pkgs, ... }:
{
  boot = {
    initrd.systemd.enable = true;
    plymouth = {
      enable = true;
      themePackages = [ pkgs.plymouthThemes.solar ];
    };
    kernelParams = [ "quiet" ];
  };

  environment.systemPackages = with pkgs; [
    git
    neovim
  ];
}
