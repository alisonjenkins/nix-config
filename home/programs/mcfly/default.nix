{ config, pkgs, ... }:
{
  programs.mcfly = {
    enable = true;
    fuzzySearchFactor = 3;
    keyScheme = "vim";
  };
}


