{ config, lib, pkgs, ... }:
{
  services = {
    greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.greetd.tuigreet}/bin/tuigreet";
        };
      };
    };
  };

  programs.greetd.tuigreet = {
    enable = true;
  };
}
