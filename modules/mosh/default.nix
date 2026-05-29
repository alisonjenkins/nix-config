{ config, lib, ... }:
let
  cfg = config.modules.mosh;
in
{
  options.modules.mosh.enable =
    lib.mkEnableOption "Mosh server (opens UDP 60000-61000, authenticates via SSH)";

  config = lib.mkIf cfg.enable {
    programs.mosh.enable = true;
  };
}
