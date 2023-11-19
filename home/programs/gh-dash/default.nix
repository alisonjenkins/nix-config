{ config, lib, pkgs, ... }:
{
  home.packages = (with pkgs; [
      difftastic
  ]);
  programs.gh-dash = {
    enable = true;
    settings = builtins.readFile ./config.yaml;
  };
}
