{ config, pkgs, ... }:

{
  programs = {
    zsh = {
      enable = true;
    };
  };

  home.file = {
    ".zshrc".text = builtins.readFile ./zshrc.sh;
    ".config/zshrc.d" = {
      source = ./zshrc.d;
      recursive = true;
    };
  };
}

