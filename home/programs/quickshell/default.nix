{
  inputs,
  pkgs,
  system,
  ...
}:
{
  home.packages = if pkgs.stdenv.isLinux then with pkgs; [
    inputs.quickshell.packages.${system}.default
  ] else [];

  # home.file = {
  #   ".config/quickshell/shell.qml".source = ./shell.qml;
  # };
}
