{ pkgs, system, inputs, ... }:
{
  programs.obs-studio = {
    enable = true;
    plugins = with pkgs.obs-studio-plugins; [
      advanced-scene-switcher
      droidcam-obs
      inputs.nixpkgs_stable.legacyPackages.${system}.obs-studio-plugins.obs-backgroundremoval
      obs-pipewire-audio-capture
      obs-vkcapture
      wlrobs
    ];
  };
}
