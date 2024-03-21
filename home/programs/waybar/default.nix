{pkgs, ...}: {
  home.packages = with pkgs; [
    brightnessctl
    cpupower-gui
    hyprshade
    playerctl
    swaynotificationcenter
    swww
  ];

  programs.waybar = {
    enable = true;
    package = pkgs.stable.waybar;
  };

  home.file.".config/waybar" = {
    source = ./configs/new;
    recursive = true;
  };
}
