{ config, lib, pkgs, ... }:
{
  imports = [
    ./ssh
  ];

  environment.systemPackages = with pkgs; [
    git
    htop
    lshw
    nnn
    tmux
    toybox
  ];
}
