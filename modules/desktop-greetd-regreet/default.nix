{ config, lib, pkgs, ... }:
let
  cfg = config.modules.desktop-greetd-regreet;
in
{
  options.modules.desktop-greetd-regreet = {
    enable = lib.mkEnableOption "greetd display manager with regreet GUI";
  };

  config = lib.mkIf cfg.enable {
    # Stylix emits a warning about our custom default_session.command (see
    # below). It's a false positive — stylix themes regreet via
    # programs.regreet.* options, not via the greetd command, so theming
    # works fine. Filtering the warning hits infinite recursion (the filter
    # would have to read options.warnings.definitionsWithLocations while
    # contributing to it), so the warning stays. Cosmetic only.

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
