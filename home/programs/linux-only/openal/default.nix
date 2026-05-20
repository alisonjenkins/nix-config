{ lib, config, ... }:

# Writes ~/.config/alsoft.conf for OpenAL Soft.
#
# Default settings work around an OpenAL Soft <= 1.24.x bug where the
# PulseAudio backend falls back to a mono output when the target sink uses
# an unrecognized channel map (e.g. aux0,aux1 — what PipeWire's pro-audio
# profile exposes for class-compliant USB interfaces like the Scarlett 2i2).
# Mono fallback collapses 3D-positioned sources into one channel; with sound-
# heavy games (Minecraft + Create-family modpacks) the summed signal hits the
# limiter constantly → audible crackle/pumping.
#
# Forcing channels=stereo and preferring the native pipewire backend produces
# a proper stereo OpenAL stream regardless of how the sink presents itself.

let
  cfg = config.programs.openal;
in
{
  options.programs.openal = {
    enable = lib.mkEnableOption "OpenAL Soft client config (alsoft.conf)";

    drivers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "pipewire" "pulse" ];
      example = [ "pipewire" ];
      description = ''
        Ordered backend preference. OpenAL Soft tries each in turn.
        Listing pipewire first uses its native PipeWire backend, which
        handles pro-audio channel maps correctly. pulse is a fallback for
        hosts without a working PipeWire backend.
      '';
    };

    channels = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [
        "mono" "stereo" "quad" "surround51" "surround61" "surround71"
        "ambi1" "ambi2" "ambi3"
      ]);
      default = "stereo";
      description = ''
        Force a specific output channel configuration. Set to null to let
        OpenAL Soft auto-detect from the sink. Defaults to stereo to avoid
        the mono-fallback bug on pro-audio sinks (see module header).
      '';
    };

    frequency = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = 48000;
      description = ''
        Output sample rate in Hz. Match the system mixer rate (PipeWire
        default 48000) to skip a resample stage.
      '';
    };

    hrtf = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = ''
        Force HRTF on/off. null = OpenAL default (auto, on for stereo
        headphones via PulseAudio hint). HRTF only meaningful with stereo.
      '';
    };

    periodSize = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      example = 1024;
      description = "Buffer period size in samples. null = backend default.";
    };

    periods = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      example = 4;
      description = "Number of buffer periods. null = backend default.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra INI content appended to alsoft.conf.";
    };
  };

  config = lib.mkIf cfg.enable {
    xdg.configFile."alsoft.conf".text = lib.concatStringsSep "\n" (
      [ "# Managed by home-manager — programs.openal" "[general]" ]
      ++ lib.optional (cfg.drivers != [ ])
        "drivers = ${lib.concatStringsSep "," cfg.drivers}"
      ++ lib.optional (cfg.channels != null) "channels = ${cfg.channels}"
      ++ lib.optional (cfg.frequency != null)
        "frequency = ${toString cfg.frequency}"
      ++ lib.optional (cfg.hrtf != null)
        "hrtf = ${if cfg.hrtf then "true" else "false"}"
      ++ lib.optional (cfg.periodSize != null)
        "period_size = ${toString cfg.periodSize}"
      ++ lib.optional (cfg.periods != null)
        "periods = ${toString cfg.periods}"
      ++ lib.optional (cfg.extraConfig != "") cfg.extraConfig
      ++ [ "" ]
    );
  };
}
