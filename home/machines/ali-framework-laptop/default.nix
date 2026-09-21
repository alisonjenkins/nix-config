{ pkgs, ... }: {
  imports = [
    ./easyeffects
    ./location-detection
    ./audio-context
  ];

  modules.beatsaber.enable = true;

  home.packages = [
    pkgs.nbt-studio
  ];
}
