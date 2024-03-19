{ config, lib, pkgs, ... }:

{
    home.packages = (lib.mkIf pkgs.stdenv.isLinux (with pkgs; [
        brightnessctl
        cpupower-gui
        hyprshade
        playerctl
        swaynotificationcenter
        swww
    ]) []) ;

    programs.waybar = (lib.mkIf pkgs.stdenv.isLinux {
      enable = true;
    } {});

    home.file.".config/waybar" = {
      source = ./configs/new;
      recursive = true;
    };
}
