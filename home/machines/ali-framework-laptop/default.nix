{ pkgs, ... }: {
  imports = [
    ./easyeffects
    ./location-detection
    ./audio-context
  ];

  modules.beatsaber.enable = true;
  modules.helldivers2Mods.enable = true;

  home.packages = [
    pkgs.nbt-studio
  ];
}
