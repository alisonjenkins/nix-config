{ config, lib, pkgs, ... }:
let
  cfg = config.modules.storage-server;
in
{
  options.modules.storage-server = {
    enable = lib.mkEnableOption "storage server tools (mergerfs)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      mergerfs
      mergerfs-tools
    ];
  };
}
