{ config, lib, pkgs, ... } @ args:
let
  cfg = config.modules.overseer;
  inputs = args.inputs or (throw "inputs not passed to home-manager module overseer");
in
{
  options.modules.overseer = {
    enable = lib.mkEnableOption "overseer agentic task orchestrator CLI";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      inputs.overseer.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];
  };
}
