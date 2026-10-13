{ config, lib, pkgs, ... }:
let
  cfg = config.modules.desktop-greetd-regreet;
in
{
  options.modules.desktop-greetd-regreet = {
    enable = lib.mkEnableOption "greetd display manager with regreet GUI";

    remoteAccess = {
      enable = lib.mkEnableOption "a wayvnc server inside the greeter, so the login screen can be reached over an SSH tunnel";

      port = lib.mkOption {
        type = lib.types.port;
        default = 5900;
        description = "TCP port wayvnc listens on, on 127.0.0.1 only.";
      };
    };
  };

  # Drop one stylix warning, which is a false positive here.
  #
  # stylix/modules/regreet/nixos.nix warns whenever
  # services.greetd.settings.default_session.command differs at all from
  # nixpkgs' default, `dbus-run-session cage <cageArgs> -- regreet`. Dropping
  # dbus-run-session is the entire point of the override below, so the warning
  # fires by construction and cannot be satisfied without reintroducing the
  # ~25s greeter delay.
  #
  # Theming is unaffected either way: stylix applies it through
  # programs.regreet.* — adw-gtk3, GTK css generated from the scheme, the dark
  # preference and the wallpaper — never through the greetd command. Disabling
  # the target would silence the warning and lose all of that, so filter the
  # message instead.
  #
  # `apply` transforms the merged list rather than reading config.warnings from
  # a definition, which is what would recurse. It matches the full message
  # prefix so a different regreet warning would still surface, and if stylix
  # rewords this one the filter stops matching and the warning comes back —
  # both failure modes are safe.
  options.warnings = lib.mkOption {
    apply = builtins.filter (
      warning:
      !lib.hasPrefix
        "stylix: regreet: custom services.greetd.settings.default_session.command"
        warning
    );
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

          # cage exports WAYLAND_DISPLAY to its child, and wayvnc exits when
          # cage does, so no cleanup is needed. Bound to loopback: reach it
          # with `ssh -L`. Any local account can also connect while the
          # greeter is up.
          greeter =
            if cfg.remoteAccess.enable then
              lib.getExe (pkgs.writeShellApplication {
                name = "greeter-with-vnc";
                runtimeInputs = [ pkgs.wayvnc ];
                text = ''
                  wayvnc 127.0.0.1 ${toString cfg.remoteAccess.port} &
                  exec ${regreet}
                '';
              })
            else
              regreet;
        in lib.mkForce "${pkgs.bash}/bin/bash -c 'exec ${cage} -s -- ${greeter} 2>/dev/null'";
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
