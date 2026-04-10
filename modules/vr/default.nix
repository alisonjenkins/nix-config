{ config, lib, pkgs, ... }:
let
  cfg = config.modules.vr;

  pactl = "${pkgs.pulseaudio}/bin/pactl";
  pw-link = "${pkgs.pipewire}/bin/pw-link";

  # Script that watches PipeWire for wivrn.sink appearing/disappearing.
  # On connect: links the audio sink's monitor to wivrn.sink so audio plays
  #             on both local output and VR headset, and switches default
  #             source to headset mic.
  #             Prefers easyeffects_sink if available, otherwise uses default sink.
  # On disconnect: removes links, restores default source.
  wivrnAudioScript = pkgs.writeShellScript "wivrn-audio-monitor" ''
    LINKED=false
    AUDIO_SINK=""

    has_wivrn_sink() {
      ${pactl} list short sinks 2>/dev/null | grep -q 'wivrn\.sink'
    }

    has_wivrn_source() {
      ${pactl} list short sources 2>/dev/null | grep -q 'wivrn\.source'
    }

    # Find the best sink to link: prefer easyeffects_sink, fall back to default
    find_audio_sink() {
      if ${pw-link} -o 2>/dev/null | grep -q '^easyeffects_sink:monitor_'; then
        echo "easyeffects_sink"
      else
        ${pactl} get-default-sink 2>/dev/null
      fi
    }

    cleanup() {
      if $LINKED && [ -n "$AUDIO_SINK" ]; then
        ${pw-link} -d "$AUDIO_SINK:monitor_FL" "wivrn.sink:playback_FL" 2>/dev/null || true
        ${pw-link} -d "$AUDIO_SINK:monitor_FR" "wivrn.sink:playback_FR" 2>/dev/null || true
        LINKED=false
      fi
      local alsa_source
      alsa_source="$(${pactl} list short sources 2>/dev/null | grep -m1 'alsa_input\.' | cut -f2)" || true
      if [ -n "''${alsa_source:-}" ]; then
        ${pactl} set-default-source "$alsa_source" 2>/dev/null || true
      fi
    }

    trap cleanup EXIT

    setup_vr_audio() {
      AUDIO_SINK="$(find_audio_sink)"
      if [ -z "$AUDIO_SINK" ]; then
        echo "No audio sink found, skipping link setup"
        return
      fi
      echo "Linking $AUDIO_SINK monitor -> wivrn.sink"
      ${pw-link} "$AUDIO_SINK:monitor_FL" "wivrn.sink:playback_FL" 2>/dev/null || true
      ${pw-link} "$AUDIO_SINK:monitor_FR" "wivrn.sink:playback_FR" 2>/dev/null || true
      LINKED=true
      echo "Links created"

      if has_wivrn_source; then
        ${pactl} set-default-source wivrn.source 2>/dev/null || true
        echo "Set wivrn.source as default microphone"
      fi
    }

    teardown_vr_audio() {
      if $LINKED && [ -n "$AUDIO_SINK" ]; then
        ${pw-link} -d "$AUDIO_SINK:monitor_FL" "wivrn.sink:playback_FL" 2>/dev/null || true
        ${pw-link} -d "$AUDIO_SINK:monitor_FR" "wivrn.sink:playback_FR" 2>/dev/null || true
        LINKED=false
        AUDIO_SINK=""
        echo "Links removed"
      fi
      local alsa_source
      alsa_source="$(${pactl} list short sources 2>/dev/null | grep -m1 'alsa_input\.' | cut -f2)" || true
      if [ -n "''${alsa_source:-}" ]; then
        ${pactl} set-default-source "$alsa_source" 2>/dev/null || true
      fi
    }

    # Check if wivrn.sink already exists at startup
    if has_wivrn_sink; then
      echo "WiVRn sink already present, setting up audio"
      sleep 1
      setup_vr_audio
    fi

    # Read events from pactl subscribe using process substitution
    # so the while loop runs in the main shell (preserving LINKED state)
    while read -r line; do
      case "$line" in
        *"'new'"*sink*)
          if has_wivrn_sink && ! $LINKED; then
            echo "WiVRn sink appeared"
            sleep 1
            setup_vr_audio
          fi
          ;;
        *"'remove'"*sink*)
          if $LINKED && ! has_wivrn_sink; then
            echo "WiVRn sink disappeared"
            teardown_vr_audio
          fi
          ;;
        *"'new'"*source*)
          if has_wivrn_source; then
            echo "WiVRn source appeared — switching default mic"
            ${pactl} set-default-source wivrn.source 2>/dev/null || true
          fi
          ;;
        *"'remove'"*source*)
          if ! has_wivrn_source; then
            local alsa_source
            alsa_source="$(${pactl} list short sources 2>/dev/null | grep -m1 'alsa_input\.' | cut -f2)" || true
            if [ -n "''${alsa_source:-}" ]; then
              echo "WiVRn source disappeared — restoring default mic"
              ${pactl} set-default-source "$alsa_source" 2>/dev/null || true
            fi
          fi
          ;;
      esac
    done < <(${pactl} subscribe 2>/dev/null)
  '';
in
{
  options.modules.vr = {
    enable = lib.mkEnableOption "VR support";
    enableOpenSourceVR = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable open source VR stack (Envision + WiVRn)";
    };
    enableEnvision = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Envision GUI for managing OpenXR/Monado (large closure, not required for WiVRn)";
    };
    scale = lib.mkOption {
      type = lib.types.float;
      default = 0.8;
      description = "Foveated rendering scale (lower = less GPU load, reduced peripheral clarity)";
    };
    bitrate = lib.mkOption {
      type = lib.types.int;
      default = 50000000;
      description = "Streaming bitrate in bits per second";
    };
    codec = lib.mkOption {
      type = lib.types.enum [ "h264" "h265" "av1" ];
      default = "h265";
      description = "Video codec for streaming (av1 is more efficient but requires RDNA 3+)";
    };
    encoders = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
      default = [
        {
          encoder = "vaapi";
          codec = "h265";
          width = 1.0;
          height = 0.5;
          offset_x = 0.0;
          offset_y = 0.0;
        }
        {
          encoder = "vaapi";
          codec = "h265";
          width = 1.0;
          height = 0.5;
          offset_x = 0.0;
          offset_y = 0.5;
        }
      ];
      description = "Encoder configuration (split into slices for parallel encoding)";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      environment.systemPackages = [
        pkgs.unstable.bs-manager
        pkgs.unstable.wayvr
        pkgs.xr-video-player
      ];
    })

    (lib.mkIf (cfg.enable && cfg.enableOpenSourceVR) {
    programs = lib.mkIf cfg.enableEnvision {
      envision = {
        enable = true;
        openFirewall = true;
      };
    };

    # User service that monitors for WiVRn sink and manages audio routing
    systemd.user.services.wivrn-audio = {
      description = "WiVRn audio routing (combine-sink + mic switching)";
      wantedBy = [ "graphical-session.target" ];
      after = [ "pipewire.service" "wireplumber.service" ];
      bindsTo = [ "pipewire.service" ];
      serviceConfig = {
        ExecStart = wivrnAudioScript;
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    services = {
      wivrn = {
        enable = true;
        openFirewall = true;
        autoStart = true;
        config = {
          enable = true;

          json = {
            scale = cfg.scale;
            bitrate = cfg.bitrate;
            encoders = cfg.encoders;
          };
        };
      };
    };
  })
  ];
}
