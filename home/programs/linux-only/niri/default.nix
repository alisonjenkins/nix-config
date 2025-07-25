{ pkgs, inputs, system, ... }: {
  home.packages =  if pkgs.stdenv.isLinux then [
    inputs.quickshell.packages.${system}.default
    pkgs.fuzzel
    pkgs.mako
    pkgs.swaylock
    pkgs.swww
    pkgs.unstable.wlr-which-key
    pkgs.waybar
    pkgs.xwayland-satellite
  ] else [];

  home.file = {
    ".config/niri/config.kdl".source = ./config.kdl;
    ".config/wlr-which-key/config.yaml".source = ./wlr-which-key/config.yaml;
  };
}
