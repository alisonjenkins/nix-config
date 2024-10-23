{
  pkgs,
  lib,
  system,
  inputs,
  ...
}: {
  programs.obs-studio = {
    enable = lib.mkIf pkgs.stdenv.isLinux true;
    plugins = with pkgs.obs-studio-plugins;
      [
        # inputs.nixpkgs.legacyPackages.${system}.obs-studio-plugins.advanced-scene-switcher
        # obs-vkcapture
        droidcam-obs
      ]
      ++ (
        if pkgs.system == "x86_64-linux"
        then [
          inputs.nixpkgs.legacyPackages.${system}.obs-studio-plugins.obs-backgroundremoval
          obs-pipewire-audio-capture
          wlrobs
        ]
        else []
      );
  };
}
