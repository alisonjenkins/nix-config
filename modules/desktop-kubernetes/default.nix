{ config, lib, pkgs, ... }:
let
  cfg = config.modules.desktop-kubernetes;
in
{
  options.modules.desktop-kubernetes = {
    enable = lib.mkEnableOption "Kubernetes CLI tools (k9s, kubectl, helm, cilium-cli, etc.)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      unstable.cilium-cli
      unstable.cmctl
      unstable.fluxcd
      unstable.k9s
      unstable.kubectl
      unstable.kubernetes-helm
      unstable.pluto
      unstable.seabird
    ];
  };
}
