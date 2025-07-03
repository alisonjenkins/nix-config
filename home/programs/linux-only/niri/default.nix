{ pkgs, inputs, system, ... }: {
  home.packages =  if pkgs.stdenv.isLinux then [
    inputs.quickshell.packages.${system}.default
    pkgs.fuzzel
    pkgs.swaylock
    pkgs.unstable.wlr-which-key
    pkgs.xwayland-satellite
  ] else [];

  home.file = {
    ".config/niri/config.kdl".source = ./config.kdl;
    ".config/wlr-which-key/config.yaml".source = ./wlr-which-key/config.yaml;
  };
}
