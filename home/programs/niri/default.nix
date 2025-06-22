{ pkgs, inputs, system, ... }: {
  home.packages = with pkgs; [
    fuzzel
    swaylock
    xwayland-satellite
    inputs.quickshell.packages.${system}.default
  ];

  home.file = {
    ".config/niri/config.kdl".source = ./config.kdl;
  };
}
