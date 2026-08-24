{ config, lib, pkgs, ... }:
let
  cfg = config.custom.steamHeadless;

  # gamescope --backend headless renders offscreen and presents no Wayland
  # surface, so there is no desktop behind the game, nothing for a tiling
  # compositor to lay out, and no output whose mode has to be changed. Steam
  # captures gamescope's buffer directly rather than going through a portal
  # ScreenCast of the desktop, which is what makes the game fill the client's
  # frame by construction.
  #
  # This is the documented pattern for Remote Play from a Linux host, and it
  # sidesteps every failure seen while capturing the real session: capture not
  # renegotiating after a mode change, a tiled game not filling a narrowed
  # output, and the flicker produced by the renegotiation churn.
  steam-headless = pkgs.writeShellApplication {
    name = "steam-headless";
    runtimeInputs = with pkgs; [ coreutils procps gamescope ];
    text = ''
      GAMESCOPE_BIN=${lib.escapeShellArg (lib.getExe cfg.gamescopePackage)}

      stop_desktop_steam() {
        if ! pgrep -x steam >/dev/null; then
          return 0
        fi
        echo "steam-headless: shutting down the running Steam client" >&2
        steam -shutdown || true
        for _ in $(seq 1 ${toString cfg.shutdownTimeout}); do
          pgrep -x steam >/dev/null || return 0
          sleep 1
        done
        return 1
      }

      case "''${1:-start}" in
        start)
          # Steam is single-instance: the desktop client and a headless
          # session cannot coexist, so this is a mode switch rather than a
          # service that runs alongside the session.
          if ! stop_desktop_steam; then
            echo "steam-headless: Steam did not exit; aborting" >&2
            exit 1
          fi

          # Unset so gamescope does not try to nest itself in the running niri
          # session. Nesting would reintroduce exactly the desktop-capture
          # problem this exists to avoid.
          unset WAYLAND_DISPLAY DISPLAY

          echo "steam-headless: starting ${toString cfg.width}x${toString cfg.height}@${toString cfg.refresh} headless session" >&2
          exec "$GAMESCOPE_BIN" \
            --backend headless \
            -W ${toString cfg.width} -H ${toString cfg.height} \
            -r ${toString cfg.refresh} \
            -e \
            ${lib.escapeShellArgs cfg.extraGamescopeArgs} \
            -- steam ${lib.escapeShellArgs cfg.steamArgs}
          ;;
        stop)
          stop_desktop_steam || true
          pkill -f "gamescope.*--backend headless" || true
          echo "steam-headless: stopped" >&2
          ;;
        *)
          echo "usage: steam-headless [start|stop]" >&2
          exit 2
          ;;
      esac
    '';
  };
in
{
  options.custom.steamHeadless = {
    enable = lib.mkEnableOption ''
      an on-demand headless gamescope Steam session for Remote Play.

      Deliberately not started automatically: it stops the desktop Steam
      client, because Steam is single-instance
    '';

    width = lib.mkOption {
      type = lib.types.int;
      default = 1280;
      description = ''
        Session width. Match the streaming client's panel — a Steam Deck is
        1280x800. Rendering above the client's resolution only spends GPU and
        bitrate on a downscale.
      '';
    };

    height = lib.mkOption {
      type = lib.types.int;
      default = 800;
      description = "Session height. See width.";
    };

    refresh = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "Session refresh rate in Hz.";
    };

    shutdownTimeout = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Seconds to wait for the desktop Steam client to exit.";
    };

    gamescopePackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.gamescope;
      defaultText = lib.literalExpression "pkgs.gamescope";
      description = ''
        gamescope package to run the session with. Resolved to a store path
        rather than taken from PATH so the steam-command-runner shim at
        ~/.local/bin/gamescope, which exists to rewrite per-game arguments in
        the Steam launch chain, does not intercept the session itself.
      '';
    };

    extraGamescopeArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "--hdr-enabled" ];
      description = "Extra arguments appended to the gamescope invocation.";
    };

    steamArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "-gamepadui" ];
      description = ''
        Arguments for the Steam client inside the session. -gamepadui gives
        Big Picture, which is what a controller-driven streaming client wants.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && pkgs.stdenv.isLinux) {
    home.packages = [ steam-headless ];

    # Manually started: `systemctl --user start steam-headless`, which also
    # makes it reachable over SSH when nobody is at the machine.
    systemd.user.services.steam-headless = {
      Unit = {
        Description = "Headless gamescope Steam session for Remote Play";
      };

      Service = {
        ExecStart = "${lib.getExe steam-headless} start";
        ExecStop = "${lib.getExe steam-headless} stop";
        Restart = "no";
        TimeoutStopSec = 30;
      };
    };
  };
}
