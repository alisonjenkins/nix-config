{ pkgs, ... }: {
  imports = [
    ./easyeffects
    # Disabled location-based audio settings (desktop doesn't move)
    # ./location-detection
    # ./audio-context
  ];

  modules.vr.enableOpenSourceVR = true;

  home.packages = [
    pkgs.nbt-studio
  ];
}
