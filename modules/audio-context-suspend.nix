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
