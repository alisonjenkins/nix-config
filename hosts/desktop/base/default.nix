{ config, lib, pkgs, ... }:
{
  boot = {
    initrd.systemd.enable = true;
    plymouth.enable = true;
    kernelParams = [ "quiet" ];
  };

  environment.systemPackages = with pkgs; [
    git
    neovim
  ];
}
