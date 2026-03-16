{ pkgs, inputs, ... }: {
  imports = [ ./module.nix ];

  home.packages = if pkgs.stdenv.isLinux then with pkgs; [
    fuzzel
    inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
    inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default
    nautilus
    unstable.wlr-which-key
    wlsunset
    xwayland-satellite
  ] else [];

  custom.niri.enable = true;

  home.file.".config/wlr-which-key/config.yaml".source = ./wlr-which-key/config.yaml;
}
