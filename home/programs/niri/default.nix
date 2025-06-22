{ pkgs, ... }: {
  home.file = {
    ".config/niri/config.kdl".source = ./config.kdl;
  };
}
