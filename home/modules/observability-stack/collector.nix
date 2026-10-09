# The OpenTelemetry Collector is the single local OTLP endpoint: Claude Code,
# memory-recall and cc-obs-ledger send to it, and it routes logs to Loki,
# traces to Tempo and metrics to Prometheus.
{ lib, cfg, yaml, hostLabel, configs, internalPorts, ... }:
let
  inherit (cfg) ports;

  # Content that must not reach a store unless its option is on. Claude Code already
  # keeps most of it behind OTEL_LOG_* flags; this is the second lock, so a flag set
  # elsewhere (a project shell, a managed setting) cannot leak it into the stores.
  neverStored = [ "api_request_body" "api_response_body" "tool_content" ];
  promptKeys = [ "prompt" "prompt_text" "user_prompt" "response" "response_text" ];
  toolDetailKeys = [ "tool_parameters" "tool_input" "full_command" "file_path" ];
  redacted =
    neverStored
    ++ lib.optionals (!cfg.claudeCode.capturePrompts) promptKeys
    ++ lib.optionals (!cfg.claudeCode.captureToolDetails) toolDetailKeys;

  config = {
    extensions.health_check.endpoint = "0.0.0.0:${toString internalPorts.collectorHealth}";

    receivers.otlp.protocols = {
      grpc.endpoint = "0.0.0.0:${toString ports.otlpGrpc}";
      http.endpoint = "0.0.0.0:${toString ports.otlpHttp}";
    };

    processors = {
      memory_limiter = {
        check_interval = "5s";
        limit_mib = 256;
      };
      resource.attributes = [
        {
          key = "host";
          value = hostLabel;
          action = "upsert";
        }
      ];
      "attributes/redact".actions = map (key: { inherit key; action = "delete"; }) redacted;
      # Prometheus drops delta sums; the ledger and Claude Code may send them.
      deltatocumulative = { };
      batch = { };
    };

    exporters = {
      "otlphttp/loki".endpoint = "http://localhost:${toString ports.loki}/otlp";
      "otlp/tempo" = {
        endpoint = "localhost:${toString configs.tempoOtlpGrpc}";
        tls.insecure = true;
      };
      "otlphttp/prometheus".endpoint = "http://localhost:${toString ports.prometheus}/api/v1/otlp";
    };

    service = {
      extensions = [ "health_check" ];
      telemetry.metrics.readers = [
        {
          pull.exporter.prometheus = {
            host = "0.0.0.0";
            port = internalPorts.collectorMetrics;
          };
        }
      ];
      pipelines =
        let
          pipe = exporter: extra: {
            receivers = [ "otlp" ];
            processors = [ "memory_limiter" "resource" "attributes/redact" ] ++ extra ++ [ "batch" ];
            exporters = [ exporter ];
          };
        in
        {
          logs = pipe "otlphttp/loki" [ ];
          traces = pipe "otlp/tempo" [ ];
          metrics = pipe "otlphttp/prometheus" [ "deltatocumulative" ];
        };
    };
  };
in
{
  inherit config;
  files."collector.yaml" = yaml.generate "collector.yaml" config;
}
