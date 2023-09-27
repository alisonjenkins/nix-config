{ config, pkgs, ... }:

{
  home = {
    sessionVariables = {
      BROWSER = "firefox";
      CLUTTER_BACKEND = "wayland";
      EDITOR = "nvim";
      TERMINAL = "alacritty";
      WLR_NO_HARDWARE_CURSORS = "1";
      WLR_RENDERER = "vulkan";
      WLR_RENDERER_ALLOW_SOFTWARE = "1";
      XDG_CURRENT_DESKTOP = "Hyprland";
      XDG_SESSION_DESKTOP = "Hyprland";
      XDG_SESSION_TYPE = "wayland";
      __GL_VRR_ALLOWED = "1";
    };
  };
}
