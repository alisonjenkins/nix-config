{ config, lib, pkgs, ... }:
{
  imports = [
    ./ssh
  ];

  # config.environment.systemPackages = with pkgs; [
  #   git
  #   htop
  #   lshw
  #   nnn
  #   tmux
  #   toybox
  # ];
}
