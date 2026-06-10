{ pkgs, inputs, lib, ... }:
let
  # noctalia 5.x is a from-scratch C++/OpenGL-ES rewrite — the old quickshell
  # QML tree (share/noctalia-shell/**.qml) no longer exists, so the previous
  # substituteInPlace patches (perf-mode blur/spectrum disable + lid-switch
  # inhibit) have no targets. 5.x also dropped the custom "noctaliaPerformanceMode"
  # visual flag entirely. Use the package vanilla; configure blur/idle via toml.
  noctalia-shell = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  imports = [ ./module.nix ];

  home.packages = if pkgs.stdenv.isLinux then with pkgs; [
    fuzzel
    noctalia-shell
    inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default
    nautilus
    unstable.wlr-which-key
    wlsunset
    xwayland-satellite
  ] else [];

  custom.niri.enable = true;

  home.file.".config/wlr-which-key/config.yaml".source = ./wlr-which-key/config.yaml;
}
