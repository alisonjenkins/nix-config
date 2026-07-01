{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.audio-context-suspend;
in {
  options.services.audio-context-suspend = {
    enable = mkEnableOption "audio context suspend/resume hooks";

    user = mkOption {
      type = types.str;
      description = "User to run audio commands as";
    };

    syncMicMuteLed = mkOption {
      type = types.bool;
      default = false;
      description = "Sync mic mute LED with PipeWire mute state on resume";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.audio-context-pre-suspend = {
      description = "Mute speakers before suspend";
      before = ["sleep.target"];
      wantedBy = ["sleep.target"];

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        ExecStart = pkgs.writeShellScript "audio-context-pre-suspend-system" ''
          export XDG_RUNTIME_DIR=/run/user/$(id -u)
          export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
          ${pkgs.pamixer}/bin/pamixer --set-volume 0
        '';
      };
    };

    systemd.services.audio-context-resume = {
      description = "Apply context-aware volume on resume from suspend";
      after = ["suspend.target" "hibernate.target" "hybrid-sleep.target" "suspend-then-hibernate.target" "NetworkManager.service"];
      wantedBy = ["suspend.target" "hibernate.target" "hybrid-sleep.target" "suspend-then-hibernate.target"];

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
        ExecStart = pkgs.writeShellScript "audio-context-resume-system" (''
          export XDG_RUNTIME_DIR=/run/user/$(id -u)
          export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus

          LOCATION=$(${pkgs.detect-location}/bin/detect-location)
          ${pkgs.audio-context-volume}/bin/audio-context-volume --location "$LOCATION"

          # Recover USB audio devices left in ALSA SUSPENDED state after resume.
          # The kernel suspends the USB playback substream on sleep; PipeWire keeps
          # feeding samples into the still-suspended pcm, so everything downstream
          # looks RUNNING but no sound comes out (seen on the Focusrite Scarlett 2i2
          # on ali-desktop). Cycling the card profile off->back forces PipeWire to
          # tear down and re-prepare the pcm, clearing SUSPENDED. Only touches USB
          # cards, only when a suspended playback substream actually exists, and
          # restores whatever profile was active.
          if ${pkgs.gnugrep}/bin/grep -ql SUSPENDED /proc/asound/card*/pcm*p/sub*/status 2>/dev/null; then
            ${pkgs.pulseaudio}/bin/pactl list short cards | while read -r _ name _; do
              case "$name" in
                alsa_card.usb-*) ;;
                *) continue ;;
              esac
              prof=$(${pkgs.pulseaudio}/bin/pactl list cards \
                | ${pkgs.gawk}/bin/awk -v n="$name" '$0 ~ "Name: "n {f=1} f && /Active Profile:/ {print $3; exit}')
              [ -n "$prof" ] && [ "$prof" != "off" ] || continue
              ${pkgs.pulseaudio}/bin/pactl set-card-profile "$name" off
              ${pkgs.coreutils}/bin/sleep 1
              ${pkgs.pulseaudio}/bin/pactl set-card-profile "$name" "$prof"
            done
          fi
        '' + lib.optionalString cfg.syncMicMuteLed ''

          # Sync mic mute LED with PipeWire state
          if ${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q MUTED; then
            ${pkgs.alsa-utils}/bin/amixer -q -c 0 sset Capture nocap
          else
            ${pkgs.alsa-utils}/bin/amixer -q -c 0 sset Capture cap
          fi
        '');
      };
    };
  };
}
