{
  inputs,
  pkgs,
  system,
  ...
}:
{
  home.packages = with pkgs; [
    inputs.quickshell.packages.${system}.default
  ];

  # home.file = {
  #   ".config/quickshell/shell.qml".source = ./shell.qml;
  # };
}
