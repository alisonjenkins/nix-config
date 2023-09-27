{ config, lib, pkgs, ... }:
{
  imports = [
    ./base
    ./fonts
    ./media
    ./virtualisation
  ];

  programs.regreet.enable = true;
  services.greetd = {
    enable = true;
    settings = {
      initial_session = {
        user = "ali";
        command = "$SHELL -l";
      };
    };
  };

  programs.dconf.enable = true;

  xdg.portal = {
    enable = true;
    wlr.enable = true;
  };
}
