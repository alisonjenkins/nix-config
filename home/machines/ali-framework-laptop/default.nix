{ pkgs, ... }: {
  imports = [
    ./easyeffects
    ./location-detection
    ./audio-context
  ];

  home.packages = [
    pkgs.nbt-studio
  ];
}
