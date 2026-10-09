# Grafana provisioning: three datasources linked to each other, and a provider
# that loads every dashboard JSON from /config/grafana/dashboards.
{ lib, cfg, yaml, ... }:
let
  inherit (cfg) ports;
  url = port: "http://localhost:${toString port}";

  datasources = {
    apiVersion = 1;
    datasources = [
      {
        name = "Prometheus";
        uid = "prometheus";
        type = "prometheus";
        access = "proxy";
        url = url ports.prometheus;
        isDefault = true;
        jsonData.httpMethod = "POST";
      }
      {
        name = "Loki";
        uid = "loki";
        type = "loki";
        access = "proxy";
        url = url ports.loki;
        # A recall record's JSON line carries the Claude Code session id; this links it to
        # the traces of that session. Unverified until quickstart section 4 is run on a live stack.
        jsonData.derivedFields = [
          {
            name = "Claude Code session";
            matcherRegex = ''"session_id":"([^"]+)"'';
            url = "{ span.session.id = \"\${__value.raw}\" }";
            datasourceUid = "tempo";
            urlDisplayLabel = "Claude Code trace";
          }
        ];
      }
      {
        name = "Tempo";
        uid = "tempo";
        type = "tempo";
        access = "proxy";
        url = url ports.tempo;
        jsonData = {
          tracesToLogsV2 = {
            datasourceUid = "loki";
            filterByTraceID = true;
            filterBySpanID = false;
          };
          tracesToMetrics.datasourceUid = "prometheus";
          serviceMap.datasourceUid = "prometheus";
          nodeGraph.enabled = true;
        };
      }
    ];
  };

  dashboardProvider = {
    apiVersion = 1;
    providers = [
      {
        name = "observability-stack";
        type = "file";
        allowUiUpdates = false;
        options.path = "/config/grafana/dashboards";
      }
    ];
  };

  dashboardFiles =
    let dir = ./dashboards;
    in
    lib.optionalAttrs (builtins.pathExists dir) (
      lib.mapAttrs' (name: _: lib.nameValuePair "grafana/dashboards/${name}" "${dir}/${name}")
        (lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".json" n) (builtins.readDir dir))
    );

  exposed = cfg.listenAddress != "127.0.0.1";

  env = {
    GF_SERVER_HTTP_PORT = toString ports.grafana;
    GF_PATHS_PROVISIONING = "/config/grafana/provisioning";
    GF_AUTH_ANONYMOUS_ENABLED = "true";
    GF_AUTH_ANONYMOUS_ORG_ROLE = if exposed then "Viewer" else "Admin";
    GF_AUTH_DISABLE_LOGIN_FORM = "true";
    GF_USERS_VIEWERS_CAN_EDIT = if exposed then "true" else "false";
    GF_SECURITY_DISABLE_INITIAL_ADMIN_CREATION = if exposed then "true" else "false";
    GF_SECURITY_DISABLE_GRAVATAR = "true";
    GF_ANALYTICS_REPORTING_ENABLED = "false";
    GF_ANALYTICS_CHECK_FOR_UPDATES = "false";
    GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES = "false";
    GF_NEWS_NEWS_FEED_ENABLED = "false";
  }
  # Exposed: the public host name is unknown, so no domain is enforced.
  // lib.optionalAttrs (!exposed) {
    # Grafana answers only for this host name, so a DNS-rebinding page cannot use the anonymous Admin login.
    GF_SERVER_DOMAIN = "localhost";
    GF_SERVER_ENFORCE_DOMAIN = "true";
    GF_SERVER_ROOT_URL = "${url ports.grafana}/";
  };
in
{
  inherit datasources env;

  files =
    {
      "grafana/provisioning/datasources/datasources.yaml" = yaml.generate "datasources.yaml" datasources;
      "grafana/provisioning/dashboards/dashboards.yaml" = yaml.generate "dashboards.yaml" dashboardProvider;
    }
    // dashboardFiles;
}
