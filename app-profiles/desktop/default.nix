{ config, lib, pkgs, ... }:
{
  imports = [
    ./base
    ./fonts
    ./media
    ./virtualisation
  ];

  programs.dconf.enable = true;

  xdg.portal = {
    enable = true;
    wlr.enable = true;
  };
}
