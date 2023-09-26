{ config, lib, pkgs, ... }:
{
  boot = {
    initrd.systemd.enable = true;
    plymouth = {
      enable = true;
      theme = "breeze";
      themePackages = mkDefault [
        (pkgs.breeze-plymouth.override {
          nixosBranding = true;
          nixosVersion = config.system.nixosRelease;
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
