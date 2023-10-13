{ config, lib, pkgs, ... }:
{
  services = {
    greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.greetd.tuigreet}/bin/tuigreet --remember --remember-user-session";
        };
      };
    };
  };

  programs.greetd.tuigreet = {
    enable = true;
  };
}
