{ config, lib, pkgs, ... }:
let
  cfg = config.custom.steamStreamMode;

  raw = pkgs.writers.writePython3Bin "stream-mode"
    {
      flakeIgnore = [ "E501" ];
    }
    (builtins.readFile ./stream_mode.py);

  stream-mode = pkgs.runCommand "stream-mode"
    {
      nativeBuildInputs = [ pkgs.makeWrapper ];
      meta.mainProgram = "stream-mode";
    } ''
    mkdir -p $out/bin
    makeWrapper ${raw}/bin/stream-mode $out/bin/stream-mode \
      --set-default STREAM_MODE_NIRI ${lib.getExe cfg.niriPackage}
  '';
in
{
  options.custom.steamStreamMode = {
    enable = lib.mkEnableOption ''
      a virtual output sized to the Steam Remote Play client.

      Remote Play captures a whole output and asks the portal for MONITOR
      sources only — its picker has no "Window" tab, while other clients'
      pickers on the same portal do — so no window-scoped source can reach it
      and an ultrawide is letterboxed into a fraction of the client's frame.

      Instead a niri virtual output is created at the client's resolution when
      it connects, the streamed game is moved onto it and fullscreened, and it
      is removed once streaming has been idle. The physical display is never
      reconfigured.

      Requires niri patched with virtual output support
      (modules.desktop.niriVirtualOutputs)
    '';

    niriPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.niri;
      defaultText = lib.literalExpression "pkgs.niri";
      description = ''
        niri package supplying `niri msg`. Must be the same build the session
        runs: the IPC is versioned with it, and virtual output support is a
        patch rather than an upstream feature.
      '';
    };

    defaultWidth = lib.mkOption {
      type = lib.types.int;
      default = 1280;
      description = ''
        Width used for a client whose resolution has not been learned yet. The
        real value is recorded from the first session and used from the next
        connect onwards. 1280x800 is the Steam Deck's panel.
      '';
    };

    defaultHeight = lib.mkOption {
      type = lib.types.int;
      default = 800;
      description = "Height used until a client's resolution is learned.";
    };

    refresh = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "Refresh rate advertised by the virtual output.";
    };

    stageTimeout = lib.mkOption {
      type = lib.types.int;
      default = 300;
      description = ''
        Seconds to keep looking for a game's window after Steam reports its
        pid. Generous because the gap is a real wait rather than a race:
        Proton prefix setup, shader compilation and launchers routinely take
        minutes before anything is mapped.
      '';
    };

    removeAfter = lib.mkOption {
      type = lib.types.int;
      default = 120;
      description = ''
        Seconds of no streaming before the virtual output is removed. Long
        enough that a reconnect is not mistaken for the session ending —
        removing it mid-reconnect would drop the capture source the client
        remembers.
      '';
    };

    logPath = lib.mkOption {
      type = lib.types.str;
      default = "%h/.local/share/Steam/logs/streaming_log.txt";
      description = "Steam's host-side streaming log (systemd specifiers).";
    };

    connectionsLogPath = lib.mkOption {
      type = lib.types.str;
      default = "%h/.local/share/Steam/logs/remote_connections.txt";
      description = ''
        Steam's remote connection log. Client connections are logged here
        before streaming negotiates, which is the only hook early enough to
        have the output in place when Steam picks its capture source.
      '';
    };
  };

  config = lib.mkIf pkgs.stdenv.isLinux (lib.mkMerge [
    # The command is useful by hand even where the watcher is not wanted, so
    # it is installed whenever the module is imported.
    { home.packages = [ stream-mode ]; }

    (lib.mkIf cfg.enable {
    systemd.user.services.steam-stream-mode = {
      Unit = {
        Description = "Virtual output for the Steam Remote Play client";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };

      Service = {
        # The log need not exist yet: the watcher waits for it rather than
        # failing, so a session that has never streamed still starts cleanly.
        Environment = [
          "STREAM_MODE_LOG=${cfg.logPath}"
          "STREAM_MODE_CONNECTIONS_LOG=${cfg.connectionsLogPath}"
          "STREAM_MODE_DEFAULT_WIDTH=${toString cfg.defaultWidth}"
          "STREAM_MODE_DEFAULT_HEIGHT=${toString cfg.defaultHeight}"
          "STREAM_MODE_DEFAULT_REFRESH=${toString cfg.refresh}"
          "STREAM_MODE_REMOVE_AFTER=${toString cfg.removeAfter}"
          "STREAM_MODE_STAGE_TIMEOUT=${toString cfg.stageTimeout}"
        ];
        ExecStart = "${lib.getExe stream-mode} watch";
        Restart = "on-failure";
        RestartSec = 5;
      };

      Install.WantedBy = [ "graphical-session.target" ];
    };
    })
  ]);
}
