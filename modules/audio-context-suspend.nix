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
        ExecStart = pkgs.writeShellScript "audio-context-resume-system" ''
          export XDG_RUNTIME_DIR=/run/user/$(id -u)
          export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus

          LOCATION=$(${pkgs.detect-location}/bin/detect-location)
          ${pkgs.audio-context-volume}/bin/audio-context-volume --location "$LOCATION"
        '';
      };
    };
  };
}
