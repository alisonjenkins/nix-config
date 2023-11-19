{ config, lib, pkgs, ... }:

{
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
    };

    home.file.".config/waybar" = {
      source = ./configs/new;
      recursive = true;
    };
}
