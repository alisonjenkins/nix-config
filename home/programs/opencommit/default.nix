{ pkgs, ... }: {
  home.packages = with pkgs; [
    opencommit
  ];

  home.files = {
    ".opencommit".source = ./opencommit-config;
  };
}
