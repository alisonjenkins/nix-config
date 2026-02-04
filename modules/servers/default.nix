# Servers module - Prometheus exporters and server-specific configuration
#
# Usage:
#   (import ../../modules/servers { })                    # Defaults: node + systemd exporters
#   (import ../../modules/servers {
#     enablePrometheusSmartctlExporter = true;            # For physical disk monitoring
#     enablePrometheusLibvirtExporter = true;             # For KVM hypervisors
#     enablePrometheusNginxExporter = true;               # For nginx servers
#     enablePrometheusWireguardExporter = true;           # For WireGuard VPN
#     enablePrometheusExportarrRadarr = true;             # For Radarr
#     exportarrRadarrUrl = "http://localhost:7878";
#     exportarrRadarrApiKeyFile = "/path/to/api-key";
#   })

{ # Node exporter (system metrics)
  enablePrometheusNodeExporter ? true
, prometheusNodeExporterPort ? 9100
, prometheusNodeExporterCollectors ? [ "systemd" "processes" ]

  # Systemd exporter (service metrics)
, enablePrometheusSystemdExporter ? true
, prometheusSystemdExporterPort ? 9558

  # Smartctl exporter (disk health - for physical disks)
, enablePrometheusSmartctlExporter ? false
, prometheusSmartctlExporterPort ? 9633

  # Libvirt exporter (VM metrics - for KVM hypervisors)
, enablePrometheusLibvirtExporter ? false
, prometheusLibvirtExporterPort ? 9177

  # Nginx exporter (web server metrics)
, enablePrometheusNginxExporter ? false
, prometheusNginxExporterPort ? 9113

  # WireGuard exporter (VPN metrics)
, enablePrometheusWireguardExporter ? false
, prometheusWireguardExporterPort ? 9586

  # Exportarr - Radarr (movie management)
, enablePrometheusExportarrRadarr ? false
, prometheusExportarrRadarrPort ? 9707
, exportarrRadarrUrl ? "http://localhost:7878"
, exportarrRadarrApiKeyFile ? null

  # Exportarr - Sonarr (TV management)
, enablePrometheusExportarrSonarr ? false
, prometheusExportarrSonarrPort ? 9708
, exportarrSonarrUrl ? "http://localhost:8989"
, exportarrSonarrApiKeyFile ? null

  # Exportarr - Bazarr (subtitle management)
, enablePrometheusExportarrBazarr ? false
, prometheusExportarrBazarrPort ? 9709
, exportarrBazarrUrl ? "http://localhost:6767"
, exportarrBazarrApiKeyFile ? null

  # Exportarr - Prowlarr (indexer management)
, enablePrometheusExportarrProwlarr ? false
, prometheusExportarrProwlarrPort ? 9710
, exportarrProwlarrUrl ? "http://localhost:9696"
, exportarrProwlarrApiKeyFile ? null

  # Firewall configuration
, openPrometheusFirewallPort ? true

, ...
}: {
  config = {
    # Node exporter
    services.prometheus.exporters.node = {
      enable = enablePrometheusNodeExporter;
      port = prometheusNodeExporterPort;
      enabledCollectors = prometheusNodeExporterCollectors;
    };

    # Systemd exporter
    services.prometheus.exporters.systemd = {
      enable = enablePrometheusSystemdExporter;
      port = prometheusSystemdExporterPort;
    };

    # Smartctl exporter
    services.prometheus.exporters.smartctl = {
      enable = enablePrometheusSmartctlExporter;
      port = prometheusSmartctlExporterPort;
    };

    # Libvirt exporter
    services.prometheus.exporters.libvirt = {
      enable = enablePrometheusLibvirtExporter;
      port = prometheusLibvirtExporterPort;
    };

    # Nginx exporter (requires nginx stub_status to be enabled)
    services.prometheus.exporters.nginx = {
      enable = enablePrometheusNginxExporter;
      port = prometheusNginxExporterPort;
    };

    # WireGuard exporter
    services.prometheus.exporters.wireguard = {
      enable = enablePrometheusWireguardExporter;
      port = prometheusWireguardExporterPort;
    };

    # Exportarr - Radarr
    services.prometheus.exporters.exportarr-radarr = {
      enable = enablePrometheusExportarrRadarr;
      port = prometheusExportarrRadarrPort;
      url = exportarrRadarrUrl;
      apiKeyFile = exportarrRadarrApiKeyFile;
    };

    # Exportarr - Sonarr
    services.prometheus.exporters.exportarr-sonarr = {
      enable = enablePrometheusExportarrSonarr;
      port = prometheusExportarrSonarrPort;
      url = exportarrSonarrUrl;
      apiKeyFile = exportarrSonarrApiKeyFile;
    };

    # Exportarr - Bazarr
    services.prometheus.exporters.exportarr-bazarr = {
      enable = enablePrometheusExportarrBazarr;
      port = prometheusExportarrBazarrPort;
      url = exportarrBazarrUrl;
      apiKeyFile = exportarrBazarrApiKeyFile;
    };

    # Exportarr - Prowlarr
    services.prometheus.exporters.exportarr-prowlarr = {
      enable = enablePrometheusExportarrProwlarr;
      port = prometheusExportarrProwlarrPort;
      url = exportarrProwlarrUrl;
      apiKeyFile = exportarrProwlarrApiKeyFile;
    };

    # Firewall rules
    networking.firewall.allowedTCPPorts =
      (if enablePrometheusNodeExporter && openPrometheusFirewallPort
       then [ prometheusNodeExporterPort ] else [])
      ++
      (if enablePrometheusSystemdExporter && openPrometheusFirewallPort
       then [ prometheusSystemdExporterPort ] else [])
      ++
      (if enablePrometheusSmartctlExporter && openPrometheusFirewallPort
       then [ prometheusSmartctlExporterPort ] else [])
      ++
      (if enablePrometheusLibvirtExporter && openPrometheusFirewallPort
       then [ prometheusLibvirtExporterPort ] else [])
      ++
      (if enablePrometheusNginxExporter && openPrometheusFirewallPort
       then [ prometheusNginxExporterPort ] else [])
      ++
      (if enablePrometheusWireguardExporter && openPrometheusFirewallPort
       then [ prometheusWireguardExporterPort ] else [])
      ++
      (if enablePrometheusExportarrRadarr && openPrometheusFirewallPort
       then [ prometheusExportarrRadarrPort ] else [])
      ++
      (if enablePrometheusExportarrSonarr && openPrometheusFirewallPort
       then [ prometheusExportarrSonarrPort ] else [])
      ++
      (if enablePrometheusExportarrBazarr && openPrometheusFirewallPort
       then [ prometheusExportarrBazarrPort ] else [])
      ++
      (if enablePrometheusExportarrProwlarr && openPrometheusFirewallPort
       then [ prometheusExportarrProwlarrPort ] else []);
  };
}
