{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.audacity;
  configFile = "${config.xdg.configHome}/audacity/audacity.cfg";

  # Audacity's own INI convention for booleans is "1"/"0", not "true"/"false"
  # (see e.g. Duplex=1, SWPlaythrough=0 in a real audacity.cfg) -- match it,
  # since crudini writes whatever string it's given verbatim and Audacity's
  # own reader expects this exact form.
  iniValue =
    v:
    if builtins.isBool v then
      (if v then "1" else "0")
    else
      toString v;

  # Each typed option group maps to one INI section. Only non-null values are
  # emitted, so leaving an option unset never touches that key -- the same
  # "only patch what's declared" contract as the freeform `settings` escape
  # hatch below, just with real names and types for the settings this repo
  # has actually needed to tune.
  typedSections = {
    AudioIO = {
      Host = cfg.audioIO.host;
      RecordingDevice = cfg.audioIO.recordingDevice;
      PlaybackDevice = cfg.audioIO.playbackDevice;
      RecordChannels = cfg.audioIO.recordChannels;
      Duplex = cfg.audioIO.duplex;
      SoundActivatedRecord = cfg.audioIO.soundActivatedRecord;
      SilenceLevel = cfg.audioIO.silenceLevel;
      LatencyDuration = cfg.audioIO.latencyDurationMs;
      LatencyCorrection = cfg.audioIO.latencyCorrectionMs;
    };
    Quality = {
      DitherAlgorithmChoice = cfg.quality.ditherAlgorithm;
      HQDitherAlgorithmChoice = cfg.quality.hqDitherAlgorithm;
      LibsoxrHQSampleRateConverterChoice = cfg.quality.sampleRateConverter;
    };
    MidiIO = {
      Host = cfg.midiIO.host;
      PlaybackDevice = cfg.midiIO.playbackDevice;
      SynthLatency = cfg.midiIO.synthLatencyMs;
    };
  };

  # Freeform `settings` is applied after the typed sections and wins on
  # conflict -- it's the escape hatch for anything not modeled above, so a
  # key present in both means the freeform value is the more specific,
  # deliberate override.
  mergedSections = lib.recursiveUpdate typedSections cfg.settings;

  nonNullKeys = lib.filterAttrs (_: v: v != null);

  setCmds = lib.concatLists (
    lib.mapAttrsToList (
      section: keys:
      lib.mapAttrsToList (
        key: value:
        "run ${lib.getExe pkgs.crudini} --set \"$target\" ${lib.escapeShellArg section} ${lib.escapeShellArg key} ${lib.escapeShellArg (iniValue value)}"
      ) (nonNullKeys keys)
    ) mergedSections
  );

  deviceOpt = description: lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    inherit description;
  };
  intOpt = description: lib.mkOption {
    type = lib.types.nullOr lib.types.int;
    default = null;
    inherit description;
  };
  boolOpt = description: lib.mkOption {
    type = lib.types.nullOr lib.types.bool;
    default = null;
    inherit description;
  };
in
{
  options.programs.audacity = {
    enable = lib.mkEnableOption "patching specific keys in Audacity's own audacity.cfg";

    audioIO = {
      host = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "ALSA" "JACK Audio Connection Kit" ]);
        default = null;
        description = ''
          PortAudio host API. This nixpkgs build of Audacity only has ALSA
          and JACK compiled in (no native PulseAudio/PipeWire host) -- JACK
          routes through pipewire-jack, which requires exact buffer/quantum
          agreement with the whole PipeWire graph and can report a false
          "dropout detected" when another app causes a quantum
          renegotiation, with no real PipeWire xrun. ALSA (via
          pipewire-alsa) doesn't have this failure mode.
        '';
      };
      recordingDevice = deviceOpt ''
        ALSA/JACK device name for recording, exactly as Audacity's own
        device picker lists it (e.g. "Easy Effects Source" under the JACK
        host). PipeWire's ALSA plugin only exposes a generic
        "pipewire"/"default" PCM under the ALSA host, not per-app named
        virtual sources -- check `aplay -L` / `arecord -L` for what's
        actually available under whichever host is set before assuming a
        name carries over between hosts.
      '';
      playbackDevice = deviceOpt "ALSA/JACK device name for playback, same caveat as recordingDevice.";
      recordChannels = intOpt "Number of channels to record (1 = mono, 2 = stereo).";
      duplex = boolOpt "Play other tracks while recording a new one.";
      soundActivatedRecord = boolOpt "Only start recording once the input crosses silenceLevel.";
      silenceLevel = intOpt "dB threshold used by soundActivatedRecord.";
      latencyDurationMs = intOpt ''
        "Audio to buffer" in milliseconds -- the audio buffer Audacity
        requests from the host API. Too low increases dropout risk; too
        high adds latency to monitoring.
      '';
      latencyCorrectionMs = intOpt ''
        Recording latency compensation in milliseconds, typically negative
        (shifts recorded audio earlier to align with what was actually
        heard when it was captured).
      '';
    };

    quality = {
      ditherAlgorithm = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "None" "Rectangle" "Triangle" "Shaped" ]);
        default = null;
        description = "Dither used for real-time (non-high-quality) sample rate/format conversion.";
      };
      hqDitherAlgorithm = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "None" "Rectangle" "Triangle" "Shaped" ]);
        default = null;
        description = "Dither used for high-quality (export-time) conversion.";
      };
      sampleRateConverter = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "LowQuality" "MediumQuality" "HighQuality" "BestQuality" ]);
        default = null;
        description = "libsoxr sample rate converter quality for high-quality conversion.";
      };
    };

    midiIO = {
      host = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "PortMidi host API name, e.g. \"ALSA\".";
      };
      playbackDevice = deviceOpt "MIDI playback device name, exactly as Audacity's device picker lists it.";
      synthLatencyMs = intOpt "MIDI synth latency compensation in milliseconds.";
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
      default = { };
      example = {
        GUI = {
          Theme = "dark";
        };
      };
      description = ''
        Escape hatch for audacity.cfg section/key overrides not covered by
        the typed options above -- applied after them and wins on conflict.
        Values here are written to the file verbatim (no bool/int
        conversion), so match Audacity's own INI conventions yourself (e.g.
        "1"/"0" for booleans).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Audacity owns this file -- it rewrites it constantly with window
    # positions, recent-files lists, and other runtime state that has
    # nowhere else to live, so it can't be a plain home-manager symlink (a
    # read-only store link would make Audacity fail to save its own state,
    # the exact problem this module exists to avoid). Instead every
    # declared key is patched in place with `crudini --set` on activation:
    # only the listed section/key pairs are touched, and anything else
    # already in the file -- including keys Audacity itself wrote -- is
    # left alone. A key removed from these options stops being patched, but
    # is not deleted from the file; unlike the Claude Code settings merge
    # elsewhere in this repo, there is no single well-defined
    # "nix-managed keys" set to diff against because the file is never
    # nix-authored in the first place.
    home.activation.audacityConfigPatch = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      target="${configFile}"
      if [ ! -e "$target" ]; then
        run mkdir -p "$(dirname "$target")"
        run touch "$target"
      fi
      ${lib.concatStringsSep "\n      " setCmds}
    '';
  };
}
