# Servers module - Prometheus exporters and server-specific configuration
{ config, lib, ... }:
let
  cfg = config.modules.servers;
in
{
  options.modules.servers = {
    enable = lib.mkEnableOption "server monitoring configuration";

    openPrometheusFirewallPort = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open firewall ports for enabled Prometheus exporters";
    };

    # Node exporter
    prometheus.nodeExporter = {
      enable = lib.mkOption { type = lib.types.bool; default = true; description = "Enable node exporter"; };
      port = lib.mkOption { type = lib.types.port; default = 9100; description = "Node exporter port"; };
      collectors = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ "systemd" "processes" ]; description = "Enabled collectors"; };
    };

    # Systemd exporter
    prometheus.systemdExporter = {
      enable = lib.mkOption { type = lib.types.bool; default = true; description = "Enable systemd exporter"; };
      port = lib.mkOption { type = lib.types.port; default = 9558; description = "Systemd exporter port"; };
    };

    # Smartctl exporter
    prometheus.smartctlExporter = {
      enable = lib.mkOption { type = lib.types.bool; default = false; description = "Enable smartctl exporter"; };
      port = lib.mkOption { type = lib.types.port; default = 9633; description = "Smartctl exporter port"; };
    };

    # Libvirt exporter
    prometheus.libvirtExporter = {
      enable = lib.mkOption { type = lib.types.bool; default = false; description = "Enable libvirt exporter"; };
      port = lib.mkOption { type = lib.types.port; default = 9177; description = "Libvirt exporter port"; };
    };

    # Nginx exporter
    prometheus.nginxExporter = {
      enable = lib.mkOption { type = lib.types.bool; default = false; description = "Enable nginx exporter"; };
      port = lib.mkOption { type = lib.types.port; default = 9113; description = "Nginx exporter port"; };
    };

    # WireGuard exporter
    prometheus.wireguardExporter = {
      enable = lib.mkOption { type = lib.types.bool; default = false; description = "Enable WireGuard exporter"; };
      port = lib.mkOption { type = lib.types.port; default = 9586; description = "WireGuard exporter port"; };
    };

    # Exportarr - Radarr
    prometheus.exportarrRadarr = {
      enable = lib.mkOption { type = lib.types.bool; default = false; description = "Enable Radarr exportarr"; };
      port = lib.mkOption { type = lib.types.port; default = 9707; description = "Radarr exportarr port"; };
      url = lib.mkOption { type = lib.types.str; default = "http://localhost:7878"; description = "Radarr URL"; };
      apiKeyFile = lib.mkOption { type = lib.types.nullOr lib.types.path; default = null; description = "Path to Radarr API key file"; };
    };

    # Exportarr - Sonarr
    prometheus.exportarrSonarr = {
      enable = lib.mkOption { type = lib.types.bool; default = false; description = "Enable Sonarr exportarr"; };
      port = lib.mkOption { type = lib.types.port; default = 9708; description = "Sonarr exportarr port"; };
      url = lib.mkOption { type = lib.types.str; default = "http://localhost:8989"; description = "Sonarr URL"; };
      apiKeyFile = lib.mkOption { type = lib.types.nullOr lib.types.path; default = null; description = "Path to Sonarr API key file"; };
    };

    # Exportarr - Bazarr
    prometheus.exportarrBazarr = {
      enable = lib.mkOption { type = lib.types.bool; default = false; description = "Enable Bazarr exportarr"; };
      port = lib.mkOption { type = lib.types.port; default = 9709; description = "Bazarr exportarr port"; };
      url = lib.mkOption { type = lib.types.str; default = "http://localhost:6767"; description = "Bazarr URL"; };
      apiKeyFile = lib.mkOption { type = lib.types.nullOr lib.types.path; default = null; description = "Path to Bazarr API key file"; };
    };

    # Exportarr - Prowlarr
    prometheus.exportarrProwlarr = {
      enable = lib.mkOption { type = lib.types.bool; default = false; description = "Enable Prowlarr exportarr"; };
      port = lib.mkOption { type = lib.types.port; default = 9710; description = "Prowlarr exportarr port"; };
      url = lib.mkOption { type = lib.types.str; default = "http://localhost:9696"; description = "Prowlarr URL"; };
      apiKeyFile = lib.mkOption { type = lib.types.nullOr lib.types.path; default = null; description = "Path to Prowlarr API key file"; };
    };
  };

  config = lib.mkIf cfg.enable {
    # Node exporter
    services.prometheus.exporters.node = {
      enable = cfg.prometheus.nodeExporter.enable;
      port = cfg.prometheus.nodeExporter.port;
      enabledCollectors = cfg.prometheus.nodeExporter.collectors;
    };

    # Systemd exporter
    services.prometheus.exporters.systemd = {
      enable = cfg.prometheus.systemdExporter.enable;
      port = cfg.prometheus.systemdExporter.port;
    };

    # Smartctl exporter
    services.prometheus.exporters.smartctl = {
      enable = cfg.prometheus.smartctlExporter.enable;
      port = cfg.prometheus.smartctlExporter.port;
    };

    # Libvirt exporter
    services.prometheus.exporters.libvirt = {
      enable = cfg.prometheus.libvirtExporter.enable;
      port = cfg.prometheus.libvirtExporter.port;
    };

    # Nginx exporter
    services.prometheus.exporters.nginx = {
      enable = cfg.prometheus.nginxExporter.enable;
      port = cfg.prometheus.nginxExporter.port;
    };

    # WireGuard exporter
    services.prometheus.exporters.wireguard = {
      enable = cfg.prometheus.wireguardExporter.enable;
      port = cfg.prometheus.wireguardExporter.port;
    };

    # Exportarr - Radarr
    services.prometheus.exporters.exportarr-radarr = {
      enable = cfg.prometheus.exportarrRadarr.enable;
      port = cfg.prometheus.exportarrRadarr.port;
      url = cfg.prometheus.exportarrRadarr.url;
      apiKeyFile = cfg.prometheus.exportarrRadarr.apiKeyFile;
    };

    # Exportarr - Sonarr
    services.prometheus.exporters.exportarr-sonarr = {
      enable = cfg.prometheus.exportarrSonarr.enable;
      port = cfg.prometheus.exportarrSonarr.port;
      url = cfg.prometheus.exportarrSonarr.url;
      apiKeyFile = cfg.prometheus.exportarrSonarr.apiKeyFile;
    };

    # Exportarr - Bazarr
    services.prometheus.exporters.exportarr-bazarr = {
      enable = cfg.prometheus.exportarrBazarr.enable;
      port = cfg.prometheus.exportarrBazarr.port;
      url = cfg.prometheus.exportarrBazarr.url;
      apiKeyFile = cfg.prometheus.exportarrBazarr.apiKeyFile;
    };

    # Exportarr - Prowlarr
    services.prometheus.exporters.exportarr-prowlarr = {
      enable = cfg.prometheus.exportarrProwlarr.enable;
      port = cfg.prometheus.exportarrProwlarr.port;
      url = cfg.prometheus.exportarrProwlarr.url;
      apiKeyFile = cfg.prometheus.exportarrProwlarr.apiKeyFile;
    };

    # Firewall rules
    networking.firewall.allowedTCPPorts =
      (lib.optional (cfg.prometheus.nodeExporter.enable && cfg.openPrometheusFirewallPort) cfg.prometheus.nodeExporter.port)
      ++ (lib.optional (cfg.prometheus.systemdExporter.enable && cfg.openPrometheusFirewallPort) cfg.prometheus.systemdExporter.port)
      ++ (lib.optional (cfg.prometheus.smartctlExporter.enable && cfg.openPrometheusFirewallPort) cfg.prometheus.smartctlExporter.port)
      ++ (lib.optional (cfg.prometheus.libvirtExporter.enable && cfg.openPrometheusFirewallPort) cfg.prometheus.libvirtExporter.port)
      ++ (lib.optional (cfg.prometheus.nginxExporter.enable && cfg.openPrometheusFirewallPort) cfg.prometheus.nginxExporter.port)
      ++ (lib.optional (cfg.prometheus.wireguardExporter.enable && cfg.openPrometheusFirewallPort) cfg.prometheus.wireguardExporter.port)
      ++ (lib.optional (cfg.prometheus.exportarrRadarr.enable && cfg.openPrometheusFirewallPort) cfg.prometheus.exportarrRadarr.port)
      ++ (lib.optional (cfg.prometheus.exportarrSonarr.enable && cfg.openPrometheusFirewallPort) cfg.prometheus.exportarrSonarr.port)
      ++ (lib.optional (cfg.prometheus.exportarrBazarr.enable && cfg.openPrometheusFirewallPort) cfg.prometheus.exportarrBazarr.port)
      ++ (lib.optional (cfg.prometheus.exportarrProwlarr.enable && cfg.openPrometheusFirewallPort) cfg.prometheus.exportarrProwlarr.port);
  };
}
