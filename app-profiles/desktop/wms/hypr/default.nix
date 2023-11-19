{ config, lib, pkgs, home, ... }:
{
  environment.systemPackages = with pkgs; [
    grim
    kitty
    slurp
    swaynotificationcenter
    swww
    waybar
    wl-clipboard
    wlogout
    wofi
    xfce.thunar
  ];

  security.pam.services.enableKwallet = true;

  environment.sessionVariables = {
    BROWSER = "firefox";
    CLUTTER_BACKEND = "wayland";
    EDITOR = "nvim";
    NIXOS_OZONE_WL = "1";
    TERMINAL = "alacritty";
    WLR_NO_HARDWARE_CURSORS = "1";
    WLR_RENDERER = "vulkan";
    WLR_RENDERER_ALLOW_SOFTWARE = "1";
    XDG_CURRENT_DESKTOP = "Hyprland";
    XDG_SESSION_DESKTOP = "Hyprland";
    XDG_SESSION_TYPE = "wayland";
    __GL_VRR_ALLOWED = "1";
  };

  programs.hyprland.enable = true;
}

