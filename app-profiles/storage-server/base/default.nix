{ config, pkgs, lib, ... }:
{
  environment.systemPackages = with pkgs; [
    mergerfs
    mergerfs-tools
  ];

  # snapraid = {
  #   enable = true;
  # };
}
