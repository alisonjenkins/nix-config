{pkgs, ...}: {
  home.packages = (if pkgs.stdenv.isLinux then with pkgs; [
    brightnessctl
    cpupower-gui
    hyprshade
    playerctl
    swaynotificationcenter
    swww
  ] else []);

  programs.waybar = {
    enable = (if pkgs.stdenv.isLinux then true else false);
    package = pkgs.stable.waybar;
  };

  home.file.".config/waybar" = {
    source = ./configs/new;
    recursive = true;
  };
}
