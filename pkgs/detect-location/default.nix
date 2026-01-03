{
  pkgs,
  lib,
  ...
}:
pkgs.writeShellApplication {
  name = "detect-location";

  runtimeInputs = with pkgs; [
    networkmanager # nmcli for WiFi scanning
    yq-go # YAML parsing
    iw # Wireless tools (backup for WiFi scanning)
    coreutils # sha1sum, cat, grep, etc.
    gawk # awk for parsing
    gnugrep # grep
    gnused # sed
  ];

  text = builtins.readFile ./detect-location.sh;

  meta = {
    description = "Detect current location based on WiFi networks and monitor EDIDs";
    longDescription = ''
      A reusable location detection tool that identifies the current location
      by scanning for visible WiFi networks and hashing connected monitor EDIDs.

      Can be used by other scripts for context-aware automation such as:
      - Volume management
      - Wallpaper switching
      - Browser tab management
      - Application profiles
    '';
    mainProgram = "detect-location";
  };
}
