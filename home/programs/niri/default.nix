{ pkgs, inputs, system, ... }: {
  home.packages =  if pkgs.stdenv.isLinux then [
    pkgs.fuzzel
    pkgs.swaylock
    pkgs.xwayland-satellite
    inputs.quickshell.packages.${system}.default
  ] else [];

  home.file = {
    ".config/niri/config.kdl".source = ./config.kdl;
  };
}
