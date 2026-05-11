{ pkgs, ... }: {
  imports = [
    ./easyeffects
    # Disabled location-based audio settings (desktop doesn't move)
    # ./location-detection
    # ./audio-context
  ];

  home.packages = [
    pkgs.nbt-studio
  ];
}
