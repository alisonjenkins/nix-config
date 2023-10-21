{ config, pkgs, lib, system, ... }:
{
  services = {
    greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --remember-user-session --sessions /run/booted-system/sw/share/xsessions/:/run/booted-system/sw/share/wayland-sessions/";
        };
      };
    };
  };

  system.activationScripts.makeTuigreetCacheDir = lib.stringAfter [ "var" ] ''
    mkdir -p /var/cache/tuigreet
  '';

  environment.systemPackages = with pkgs; [
    greetd.tuigreet
  ];
}

