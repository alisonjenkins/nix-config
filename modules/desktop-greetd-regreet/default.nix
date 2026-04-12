{ config, lib, pkgs, ... }:
let
  cfg = config.modules.desktop-greetd-regreet;
in
{
  options.modules.desktop-greetd-regreet = {
    enable = lib.mkEnableOption "greetd display manager with regreet GUI";
  };

  config = lib.mkIf cfg.enable {
    services = {
      greetd = {
        enable = true;

        # Don't use dbus-run-session (the NixOS module default). It creates a
        # private session bus where xdg-desktop-portal auto-activates and
        # blocks ~25s waiting for org.freedesktop.secrets. gnome-keyring can't
        # start because the greeter's home (/var/empty) is read-only, so D-Bus
        # waits the full timeout before the greeter appears.
        settings.default_session.command = let
          cage = lib.getExe pkgs.cage;
          regreet = lib.getExe pkgs.regreet;
        in lib.mkForce "${pkgs.bash}/bin/bash -c 'exec ${cage} -s -- ${regreet} 2>/dev/null'";
      };
    };

    programs = {
      regreet = {
        enable = true;

        settings = {
          env = {
            STATE_DIR = "/var/lib/regreet";
          };
        };
      };
    };

    security.pam.services.greetd.kwallet.enable = true;

    environment.persistence.${config.modules.base.impermanencePersistencePath}.directories =
      lib.mkIf config.modules.base.enableImpermanence [
        {
          directory = "/var/lib/regreet";
          user = "greeter";
          group = "greeter";
          mode = "u=rwx,g=rx,o=";
        }
      ];
  };
}
