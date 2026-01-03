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
        ExecStart = "${pkgs.writeShellScript "audio-context-boot" ''
          LOCATION=$(${pkgs.detect-location}/bin/detect-location)
          ${pkgs.audio-context-volume}/bin/audio-context-volume --location "$LOCATION"
        ''}";
        RemainAfterExit = true;
      };
      Install = {
        WantedBy = ["graphical-session.target"];
      };
    };
  };
}
