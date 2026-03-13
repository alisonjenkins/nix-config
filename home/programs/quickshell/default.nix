{
  config,
  inputs,
  pkgs,
  ...
}:
{
  home.packages = if pkgs.stdenv.isLinux then with pkgs; [
    ibm-plex
    inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default
    material-symbols
    nerd-fonts.jetbrains-mono
  ] else [];

  home.file = {
  };
}
