{ config, pkgs, ... }:

{
  programs.starship = {
    enable = true;
  };

  home.file = {
    ".config/starship/config.toml".text = builtins.readFile ./config.toml;
  };
}

