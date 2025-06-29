{ pkgs, inputs, system, ... }: {
  home.packages =  if pkgs.stdenv.isLinux then [
    inputs.quickshell.packages.${system}.default
    pkgs.fuzzel
    pkgs.swaylock
    pkgs.xwayland-satellite
  ] else [];

  home.file = {
    ".config/niri/config.kdl".source = ./config.kdl;
  };
}
