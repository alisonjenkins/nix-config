{ pkgs, ... }: {
  home.packages = with pkgs; [
    opencommit
  ];

  # home.file = {
  #   ".opencommit".source = ./opencommit-config;
  # };
}
