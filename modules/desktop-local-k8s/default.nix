{ config, lib, pkgs, ... }:
let
  cfg = config.modules.desktop-local-k8s;
in
{
  options.modules.desktop-local-k8s = {
    enable = lib.mkEnableOption "local Kubernetes development tools (kind, tilt, dive)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      dive
      kind
      tilt
    ];
  };
}
