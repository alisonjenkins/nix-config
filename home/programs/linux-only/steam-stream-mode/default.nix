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
      --set-default STREAM_MODE_OUTPUT ${lib.escapeShellArg cfg.output} \
      --set-default STREAM_MODE_NIRI ${lib.getExe cfg.niriPackage}
  '';
in
{
  options.custom.steamStreamMode = {
    enable = lib.mkEnableOption ''
      automatic session supervision for Steam Remote Play.

      Steam is single-instance, so a headless gamescope session and the
      desktop client cannot coexist and something has to decide which runs.
      Streaming wins: when a stream starts against the desktop session, the
      machine flips to headless, and it returns to the desktop client once
      streaming has been idle for a while.

      The flip costs the client one reconnect, because it kills the very Steam
      serving the connection. A client *connection* is deliberately not the
      trigger — a Steam Deck broadcasts on 27036 continuously just by being
      awake, so triggering on that would kill the desktop client at random.

      The former behaviour, which narrowed the output to match the client
      instead, does not work and is not what this enables: the PipeWire
      capture is negotiated when the session starts and does not follow a
      later mode change

      Remote Play captures a whole output rather than a window, so a client
      receives the entire panel scaled into its own screen. On an ultrawide
      most of the client's pixels end up as letterbox — a 5120x1440 panel sent
      to a 1280x800 Steam Deck arrives as 1280x360 of content inside an
      800-line frame.

      Steam exposes no prep-command hook to hang a mode switch on, but it does
      log both ends of a session and the resolution the client asked for. This
      watches that log and matches the output to the client for the duration
      of a session, restoring the previous mode afterwards
    '';

    output = lib.mkOption {
      type = lib.types.str;
      default = "DP-2";
      description = "niri output to switch for the duration of a stream.";
    };

    niriPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.niri;
      defaultText = lib.literalExpression "pkgs.niri";
      description = ''
        niri package supplying `niri msg`. Should match the running
        compositor: the IPC is versioned with it.
      '';
    };

    logPath = lib.mkOption {
      type = lib.types.str;
      default = "%h/.local/share/Steam/logs/streaming_log.txt";
      description = ''
        Steam's host-side streaming log. Read as a systemd specifier, so %h
        expands to the user's home directory.
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
        Description = "Match ${cfg.output} to the Steam Remote Play client";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };

      Service = {
        # The log need not exist yet: the watcher waits for it rather than
        # failing, so a session that has never streamed still starts cleanly.
        Environment = [ "STREAM_MODE_LOG=${cfg.logPath}" ];
        ExecStart = "${lib.getExe stream-mode} watch";
        Restart = "on-failure";
        RestartSec = 5;
      };

      Install.WantedBy = [ "graphical-session.target" ];
    };
    })
  ]);
}
