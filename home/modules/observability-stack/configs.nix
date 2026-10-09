# Loki, Tempo and Prometheus configuration. Paths are the ones inside the
# containers; see pod.nix for what is mounted there.
{ lib, cfg, yaml, internalPorts, ... }:
let
  inherit (internalPorts) tempoOtlpGrpc tempoOtlpHttp;

  # Series name after OTLP-to-Prometheus translation of claude_code.token.usage (unit
  # "tokens", monotonic sum). Verified on a synthetic point in the S2 spike; confirm it
  # against Claude Code's real export in task T032.
  tokenUsageMetric = "claude_code_token_usage_tokens_total";
  costGroupLabels = [ "model" "type" "query_source" "agent_name" "skill_name" "mcp_server_name" "repository" "review_run" ];

  priceKeyFor = {
    input = "inputPerMTok";
    output = "outputPerMTok";
    cacheRead = "cacheReadPerMTok";
    cacheCreation = "cacheWritePerMTok";
  };

  costRule = model: prices: type: priceKey: {
    record = "obs:token_cost_usd_estimate";
    expr = "sum by (${lib.concatStringsSep ", " costGroupLabels}) (${tokenUsageMetric}{model=\"${model}\", type=\"${type}\"}) * ${builtins.toJSON (prices.${priceKey} / 1000000.0)}";
    labels.estimate = "true";
  };

  rules.groups = [
    {
      name = "token-cost-estimates";
      rules = lib.concatLists (lib.mapAttrsToList
        (model: prices: lib.mapAttrsToList (costRule model prices) priceKeyFor)
        cfg.prices);
    }
  ];

  hours = "${toString (cfg.retentionDays * 24)}h";

  # Tempo's own OTLP receiver moves off the default ports because the collector,
  # in the same pod network, owns 4317/4318 (ports in default.nix's internalPorts).

  loki = {
    auth_enabled = false;
    server = {
      http_listen_port = cfg.ports.loki;
      grpc_listen_port = internalPorts.lokiGrpc;
      log_level = "warn";
    };
    common = {
      path_prefix = "/loki";
      replication_factor = 1;
      ring = {
        instance_addr = "127.0.0.1";
        kvstore.store = "inmemory";
      };
      storage.filesystem = {
        chunks_directory = "/loki/chunks";
        rules_directory = "/loki/rules";
      };
    };
    schema_config.configs = [
      {
        from = "2024-01-01";
        store = "tsdb";
        object_store = "filesystem";
        schema = "v13";
        index = {
          prefix = "index_";
          period = "24h";
        };
      }
    ];
    limits_config = {
      retention_period = hours;
      allow_structured_metadata = true;
      ingestion_rate_mb = 4;
      ingestion_burst_size_mb = 8;
    };
    compactor = {
      working_directory = "/loki/compactor";
      retention_enabled = true;
      delete_request_store = "filesystem";
    };
    analytics.reporting_enabled = false;
  };

  tempo = {
    server = {
      http_listen_port = cfg.ports.tempo;
      log_level = "warn";
    };
    distributor.receivers.otlp.protocols = {
      grpc.endpoint = "0.0.0.0:${toString tempoOtlpGrpc}";
      http.endpoint = "0.0.0.0:${toString tempoOtlpHttp}";
    };
    compactor.compaction.block_retention = hours;
    storage.trace = {
      backend = "local";
      wal.path = "/var/tempo/wal";
      local.path = "/var/tempo/blocks";
    };
    usage_report.reporting_enabled = false;
  };

  scrape = name: port: {
    job_name = name;
    static_configs = [ { targets = [ "localhost:${toString port}" ]; } ];
  };

  prometheus = {
    global.scrape_interval = "30s";
    rule_files = [ "/config/rules.yml" ];
    # Without this OTLP resource attributes are dropped; the views group on them.
    otlp.promote_resource_attributes = [ "host" "review.run" "repository" ];
    scrape_configs = [
      (scrape "prometheus" cfg.ports.prometheus)
      (scrape "loki" cfg.ports.loki)
      (scrape "tempo" cfg.ports.tempo)
      (scrape "grafana" cfg.ports.grafana)
      (scrape "collector" internalPorts.collectorMetrics)
    ];
  };

  prometheusArgs = [
    "--config.file=/config/prometheus.yml"
    "--storage.tsdb.path=/prometheus"
    "--storage.tsdb.retention.time=${toString cfg.retentionDays}d"
    "--storage.tsdb.retention.size=${toString cfg.budgetSplitGB.prometheus}GB"
    "--web.enable-otlp-receiver"
    "--web.listen-address=0.0.0.0:${toString cfg.ports.prometheus}"
  ];
in
{
  inherit loki tempo prometheus prometheusArgs tempoOtlpGrpc tempoOtlpHttp rules;

  files = {
    "rules.yml" = yaml.generate "rules.yml" rules;
    "loki.yaml" = yaml.generate "loki.yaml" loki;
    "tempo.yaml" = yaml.generate "tempo.yaml" tempo;
    "prometheus.yml" = yaml.generate "prometheus.yml" prometheus;
  };
}
