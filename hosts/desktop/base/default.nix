{ config, lib, pkgs, ... }:
{
  boot = {
    initrd.systemd.enable = true;
    plymouth = {
      enable = true;
      theme = "breeze";
      themePackages = [
        (pkgs.breeze-plymouth.override {
          nixosBranding = true;
        })
      ];
    };
    kernelParams = [ "quiet" ];
  };

  environment.systemPackages = with pkgs; [
    git
    neovim
  ];
}
