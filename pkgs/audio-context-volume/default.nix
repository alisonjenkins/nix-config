{
  pkgs,
  lib,
  ...
}:
pkgs.writeShellApplication {
  name = "audio-context-volume";

  runtimeInputs = with pkgs; [
    pulseaudio # pactl (legacy, if needed)
    wireplumber # wpctl for PipeWire device management
    pamixer # Volume control (supports both output and input)
    yq-go # YAML parsing
    coreutils # General utilities
    gawk # awk for parsing
    gnugrep # grep for pattern matching
    pkgs.detect-location # Our location detection script
  ];

  text = builtins.readFile ./audio-context-volume.sh;

  meta = {
    description = "Context-aware audio volume management based on location";
    longDescription = ''
      Automatically adjusts speaker and microphone volumes based on detected location.

      Features:
      - Detects location using detect-location script
      - Applies per-location volume rules from YAML configuration
      - Excludes headphones/bluetooth devices from automatic adjustment
      - Mutes speakers in unknown locations for safety
      - Sets microphone to default volume in unknown locations
      - Designed for use with systemd services on boot/resume
    '';
    mainProgram = "audio-context-volume";
  };
}
