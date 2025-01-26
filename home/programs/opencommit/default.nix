{ pkgs, ... }: {
  home.packages = with pkgs; [
    opencommit
  ];
}
