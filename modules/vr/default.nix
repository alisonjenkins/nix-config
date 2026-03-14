{ config, lib, pkgs, ... }:
let
  cfg = config.modules.vr;

  pactl = "${pkgs.pulseaudio}/bin/pactl";
  pw-link = "${pkgs.pipewire}/bin/pw-link";

  # Script that watches PipeWire for wivrn.sink appearing/disappearing.
  # On connect: links easyeffects_sink monitor to wivrn.sink so audio plays
  #             on both local output and VR headset, and switches default
  #             source to headset mic.
  # On disconnect: removes links, restores default source.
  wivrnAudioScript = pkgs.writeShellScript "wivrn-audio-monitor" ''
    set -euo pipefail

    LINKED=false

    cleanup() {
      if $LINKED; then
        ${pw-link} -d "easyeffects_sink:monitor_FL" "wivrn.sink:playback_FL" 2>/dev/null || true
        ${pw-link} -d "easyeffects_sink:monitor_FR" "wivrn.sink:playback_FR" 2>/dev/null || true
        LINKED=false
      fi
      # Restore default source
      local alsa_source
      alsa_source="$(${pactl} list short sources | grep -m1 'alsa_input\.' | cut -f2)" || true
      if [ -n "$alsa_source" ]; then
        ${pactl} set-default-source "$alsa_source" 2>/dev/null || true
      fi
    }

    trap cleanup EXIT

    setup_vr_audio() {
      echo "Linking easyeffects_sink monitor -> wivrn.sink"

      ${pw-link} "easyeffects_sink:monitor_FL" "wivrn.sink:playback_FL" 2>/dev/null || true
      ${pw-link} "easyeffects_sink:monitor_FR" "wivrn.sink:playback_FR" 2>/dev/null || true
      LINKED=true

      echo "Links created"

      # Switch default source to headset mic if available
      if ${pactl} list short sources | grep -q 'wivrn\.source'; then
        ${pactl} set-default-source wivrn.source
        echo "Set wivrn.source as default microphone"
      fi
    }

    teardown_vr_audio() {
      if $LINKED; then
        ${pw-link} -d "easyeffects_sink:monitor_FL" "wivrn.sink:playback_FL" 2>/dev/null || true
        ${pw-link} -d "easyeffects_sink:monitor_FR" "wivrn.sink:playback_FR" 2>/dev/null || true
        LINKED=false
        echo "Links removed"
      fi
      # Restore default source
      local alsa_source
      alsa_source="$(${pactl} list short sources | grep -m1 'alsa_input\.' | cut -f2)" || true
      if [ -n "$alsa_source" ]; then
        ${pactl} set-default-source "$alsa_source" 2>/dev/null || true
      fi
    }

    # Check if wivrn.sink already exists at startup
    if ${pactl} list short sinks | grep -q 'wivrn\.sink'; then
      echo "WiVRn sink already present, setting up audio"
      sleep 1
      setup_vr_audio
    fi

    # Watch for sink add/remove events
    ${pactl} subscribe | while read -r line; do
      case "$line" in
        *"'new'"*sink*)
          if ${pactl} list short sinks | grep -q 'wivrn\.sink'; then
            if ! $LINKED; then
              echo "WiVRn sink appeared"
              sleep 1
              setup_vr_audio
            fi
          fi
          ;;
        *"'remove'"*sink*)
          if $LINKED; then
            if ! ${pactl} list short sinks | grep -q 'wivrn\.sink'; then
              echo "WiVRn sink disappeared"
              teardown_vr_audio
            fi
          fi
          ;;
        *"'new'"*source*)
          if ${pactl} list short sources | grep -q 'wivrn\.source'; then
            echo "WiVRn source appeared — switching default mic"
            ${pactl} set-default-source wivrn.source
          fi
          ;;
        *"'remove'"*source*)
          if ! ${pactl} list short sources | grep -q 'wivrn\.source'; then
            local alsa_source
            alsa_source="$(${pactl} list short sources | grep -m1 'alsa_input\.' | cut -f2)" || true
            if [ -n "$alsa_source" ]; then
              echo "WiVRn source disappeared — restoring default mic"
              ${pactl} set-default-source "$alsa_source" 2>/dev/null || true
            fi
          fi
          ;;
      esac
    done
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
  };

  config = lib.mkIf (cfg.enable && cfg.enableOpenSourceVR) {
    programs = {
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
        defaultRuntime = true;
        autoStart = true;
        config = {
          enable = true;

          json = {
            # Foveated rendering: render periphery at lower resolution to reduce
            # encoding load and bandwidth while keeping the center sharp
            scale = 0.8;
            # 50 Mb/s — H.265 is efficient enough; lower bitrate reduces Wi-Fi
            # congestion and improves frame consistency
            bitrate = 50000000;
            # Split frame into two slices encoded in parallel to halve encode latency
            encoders = [
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
          };
        };
      };
    };
  };
}
