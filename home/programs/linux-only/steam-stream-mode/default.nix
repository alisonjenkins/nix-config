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
      putting the streamed game alone on the captured output for Steam
      Remote Play.

      Remote Play captures a whole output, so a client otherwise receives
      whatever is on screen rather than the game. niri's dynamic cast target
      would be the better mechanism, but Steam's ScreenCast request asks for
      MONITOR sources only — its picker has no "Window" tab, while other
      clients' pickers do — so no window-scoped source can reach it.

      Instead the game window is fullscreened on the streamed output when
      Steam logs it, identified from the pid Steam reports, so nothing has to
      be clicked on the host
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
        Description = "Fullscreen the streamed game for Steam Remote Play";
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
