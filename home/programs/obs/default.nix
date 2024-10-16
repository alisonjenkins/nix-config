{
  pkgs,
  lib,
  system,
  inputs,
  ...
}: {
  programs.obs-studio = {
    enable = lib.mkIf pkgs.stdenv.isLinux true;
    plugins = with pkgs.obs-studio-plugins; [
      # inputs.nixpkgs.legacyPackages.${system}.obs-studio-plugins.advanced-scene-switcher
      droidcam-obs
      inputs.nixpkgs.legacyPackages.${system}.obs-studio-plugins.obs-backgroundremoval
      obs-pipewire-audio-capture
      # obs-vkcapture
      wlrobs
    ];
  };
}
