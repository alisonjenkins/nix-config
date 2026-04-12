{ config, lib, pkgs, ... }:
let
  cfg = config.modules.k8s-master;
in
{
  options.modules.k8s-master = {
    enable = lib.mkEnableOption "Kubernetes master node";

    masterIP = lib.mkOption {
      type = lib.types.str;
      default = "192.168.1.59";
      description = "IP address of the Kubernetes master node.";
    };

    masterHostname = lib.mkOption {
      type = lib.types.str;
      default = "api.kube";
      description = "Hostname for the Kubernetes API server.";
    };

    apiServerPort = lib.mkOption {
      type = lib.types.port;
      default = 6443;
      description = "Port for the Kubernetes API server.";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.extraHosts = "${cfg.masterIP} ${cfg.masterHostname}";

    environment.systemPackages = with pkgs; [
      kompose
      kubectl
      kubernetes
    ];

    services.kubernetes = {
      roles = [ "master" "node" ];
      masterAddress = cfg.masterHostname;
      apiserverAddress = "https://${cfg.masterHostname}:${toString cfg.apiServerPort}";
      easyCerts = true;
      apiserver = {
        securePort = cfg.apiServerPort;
        advertiseAddress = cfg.masterIP;
      };

      addons.dns.enable = true;
    };
  };
}
