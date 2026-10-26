{ config, lib, pkgs, ... }:
let
  cfg = config.custom.obsDesktopAudio;

  obs-desktop-audio = pkgs.writers.writePython3Bin "obs-desktop-audio"
    {
      flakeIgnore = [ "E501" ];
    }
    (builtins.readFile ./obs_desktop_audio.py);
in
{
  options.custom.obsDesktopAudio = {
    enable = lib.mkEnableOption ''
      a null sink that carries desktop audio minus the streams matching
      `exclude`, for OBS to record.

      OBS's application capture matches a stream by binary and app name, and
      every browser tab shares those. A stream's `media.name` is the tab
      title, so a service watches the PipeWire graph and links each playing
      stream to the sink unless a rule matches. Streams keep their normal
      links, so what is heard does not change
    '';

    sink = lib.mkOption {
      type = lib.types.str;
      default = "obs-desktop";
      description = ''
        `node.name` of the null sink. Point an OBS audio output capture at
        `<sink>.monitor`.
      '';
    };

    exclude = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.str);
      default = [ ];
      example = [
        { "media.name" = "^Element Call"; }
        { "application.process.binary" = "^\\.Discord-wrapped$"; }
      ];
      description = ''
        Rules for streams to keep out of the sink. Each rule maps a PipeWire
        node property to a regex (searched, not anchored); a stream matches
        when every property in the rule matches. Read the properties of a
        live stream with `pw-dump`. Streams of EasyEffects, OBS and the
        binaural filter chain are always skipped, because they carry a mix of
        the others.
      '';
    };
  };

  config = lib.mkIf (pkgs.stdenv.isLinux && cfg.enable) {
    home.packages = [ obs-desktop-audio ];

    systemd.user.services.obs-desktop-audio = {
      Unit = {
        Description = "Desktop audio sink for OBS, minus excluded streams";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" "pipewire.service" "pipewire-pulse.service" ];
      };

      Service = {
        Environment = [
          "OBS_DESKTOP_AUDIO_PW_DUMP=${lib.getExe' pkgs.pipewire "pw-dump"}"
          "OBS_DESKTOP_AUDIO_PW_LINK=${lib.getExe' pkgs.pipewire "pw-link"}"
          "OBS_DESKTOP_AUDIO_PACTL=${lib.getExe' pkgs.pulseaudio "pactl"}"
        ];
        # Its own variable so the JSON's quotes need no systemd escaping.
        ExecStart = "${pkgs.writeShellScript "obs-desktop-audio-start" ''
          export OBS_DESKTOP_AUDIO_CONFIG=${lib.escapeShellArg (builtins.toJSON {
            inherit (cfg) sink exclude;
          })}
          exec ${lib.getExe obs-desktop-audio}
        ''}";
        Restart = "on-failure";
        RestartSec = 5;
      };

      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
