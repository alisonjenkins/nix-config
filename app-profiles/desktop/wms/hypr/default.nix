{
  config,
  lib,
  pkgs,
  inputs,
  system,
  home,
  ...
}: {
  environment.systemPackages = with pkgs; [
    grim
    kitty
    kwallet-pam
    slurp
    swaynotificationcenter
    swww
    wl-clipboard
    wlogout
    wofi
    xfce.thunar
  ];

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
  programs.hyprland.package = inputs.hyprland.packages.${system}.hyprland;
}
