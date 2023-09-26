{ config, lib, pkgs, ... }:
{
  boot.plymouth.enable = true;
  boot.initrd.systemd.enable = true;
  environment.systemPackages = with pkgs; [
    git
    neovim
  ];
}
