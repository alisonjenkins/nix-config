{
  config,
  pkgs,
  lib,
  ...
}: {
  # Install audio-context-volume package
  home.packages = [pkgs.audio-context-volume];

  # Deploy volume rules configuration
  home.file.".config/audio-context/rules.yaml".text = ''
    # Default microphone volume when location is unknown or no rule matches
    default_mic_volume: 85

    # Exclude these audio sinks from automatic volume adjustment
    # (headphones, bluetooth devices, etc.)
    exclude_sink_patterns:
      - bluez.*              # Bluetooth devices
      - .*headphone.*        # Headphones
      - .*headset.*          # Headsets

    # Per-location volume rules (customize for your work laptop)
    rules:
      - location: work
        output_volume: 40
        mic_volume: 85

      - location: home
        output_volume: 45
        mic_volume: 70
  '';

  # Systemd user services
  systemd.user.services = {
    # Apply volume on boot
    audio-context-boot = {
      Unit = {
        Description = "Apply context-aware volume on boot";
        After = ["pipewire.service" "wireplumber.service" "graphical-session.target"];
        Wants = ["pipewire.service" "wireplumber.service"];
      };
      Service = {
        Type = "oneshot";
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
        ExecStart = lib.getExe' (pkgs.writeShellScript "audio-context-boot" ''
          LOCATION=$(${pkgs.detect-location}/bin/detect-location)
          ${pkgs.audio-context-volume}/bin/audio-context-volume --location "$LOCATION"
        '') "audio-context-boot";
        RemainAfterExit = true;
      };
      Install = {
        WantedBy = ["graphical-session.target"];
      };
    };

    # Mute speakers before suspend
    audio-context-pre-suspend = {
      Unit = {
        Description = "Mute speakers before suspend";
        Before = ["sleep.target"];
      };
      Service = {
        Type = "oneshot";
        # Mute speakers to prevent loud audio on resume in unknown location
        ExecStart = "${pkgs.pamixer}/bin/pamixer --set-volume 0";
      };
      Install = {
        WantedBy = ["sleep.target"];
      };
    };

    # Apply volume on resume from suspend
    audio-context-resume = {
      Unit = {
        Description = "Apply context-aware volume on resume from suspend";
        After = ["suspend.target"];
      };
      Service = {
        Type = "oneshot";
        # Wait for WiFi to be ready, then detect location and set volume
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
        ExecStart = lib.getExe' (pkgs.writeShellScript "audio-context-resume" ''
          LOCATION=$(${pkgs.detect-location}/bin/detect-location)
          ${pkgs.audio-context-volume}/bin/audio-context-volume --location "$LOCATION"
        '') "audio-context-resume";
      };
      Install = {
        WantedBy = ["suspend.target"];
      };
    };
  };
}
