{
  config,
  inputs,
  pkgs,
  system,
  ...
}:
{
  home.packages = if pkgs.stdenv.isLinux then with pkgs; [
    ibm-plex
    inputs.quickshell.packages.${system}.default
    material-symbols
    nerd-fonts.jetbrains-mono
  ] else [];

  home.file = {
  };
}
