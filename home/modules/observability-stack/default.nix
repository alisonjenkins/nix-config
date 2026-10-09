# Local Loki, Tempo, Prometheus and Grafana in containers, fed by Claude Code's
# own telemetry. See specs/007-local-observability-stack/ and
# docs/observability-stack.md.
{ config, lib, pkgs, ... }@args:
let
  cfg = config.modules.observabilityStack;
  inherit (lib) mkOption mkEnableOption mkIf mkMerge types;
  inherit (pkgs.stdenv.hostPlatform) isLinux isDarwin;

  yaml = pkgs.formats.yaml { };

  # Ports the pod's services bind among themselves. The pod shares one network
  # namespace, so a user-facing port must not collide with any of them.
  internalPorts = {
    collectorMetrics = 8888;
    collectorHealth = 13133;
    tempoOtlpGrpc = 14317;
    tempoOtlpHttp = 14318;
    lokiGrpc = 9096;
  };

  ctx = { inherit lib pkgs cfg yaml dataDir stateDir relativeStateDir hostLabel internalPorts; };
  configs = import ./configs.nix ctx;
  collector = import ./collector.nix (ctx // { inherit configs; });
  grafana = import ./grafana.nix ctx;
  pod = import ./pod.nix (ctx // { inherit configs collector grafana; });
  scripts = import ./scripts.nix (ctx // { inherit pod configs collector grafana; });

  dataDir =
    if cfg.dataDir != null then cfg.dataDir
    else if isDarwin then "${config.home.homeDirectory}/Library/Application Support/observability"
    else "${config.xdg.dataHome}/observability";
  stateDir = "${config.xdg.stateHome}/observability-stack";
  relativeStateDir = lib.removePrefix "${config.home.homeDirectory}/" stateDir;
  relativeConfigDir = lib.removePrefix "${config.home.homeDirectory}/" config.xdg.configHome;

  # Clients run on the same machine, so they always use loopback.
  endpoints = {
    host = hostLabel;
    stateDir = stateDir;
    ports = cfg.ports;
    urls = {
      grafana = "http://127.0.0.1:${toString cfg.ports.grafana}";
      loki = "http://127.0.0.1:${toString cfg.ports.loki}";
      tempo = "http://127.0.0.1:${toString cfg.ports.tempo}";
      prometheus = "http://127.0.0.1:${toString cfg.ports.prometheus}";
      otlpHttp = "http://127.0.0.1:${toString cfg.ports.otlpHttp}";
    };
  };
  rendered = config.modules.observabilityStack.rendered;
  hostLabel = cfg.hostLabel;

  # Ports other modules in this repository already bind on a workstation.
  knownUsedPorts = [ 8080 8110 9100 ];
  portValues = lib.attrValues cfg.ports;

  imageOk = i: builtins.match "sha256:[0-9a-f]{64}" i.digest != null && i.tag != "latest";
  budgetSum = cfg.budgetSplitGB.prometheus + cfg.budgetSplitGB.loki + cfg.budgetSplitGB.tempo;
  osPodman = (args.osConfig or null);
in
{
  options.modules.observabilityStack = {
    enable = mkEnableOption "the local observability stack (Loki, Tempo, Prometheus, Grafana)";

    retentionDays = mkOption {
      type = types.ints.positive;
      default = 30;
      description = "Days Loki, Tempo and Prometheus keep data.";
    };

    maxDiskGB = mkOption {
      type = types.ints.positive;
      default = 20;
      description = "Disk budget in GB for the three stores. Going over it never stops ingestion: the guard reports it (metric, dashboard, session-start notice, desktop notification).";
    };

    budgetSplitGB = {
      prometheus = mkOption { type = types.ints.positive; default = 4; description = "Prometheus size limit (--storage.tsdb.retention.size). Prometheus enforces it by discarding its oldest blocks, so this is the one store that drops history when full."; };
      loki = mkOption { type = types.ints.positive; default = 7; description = "Loki budget."; };
      tempo = mkOption { type = types.ints.positive; default = 7; description = "Tempo budget."; };
    };

    ports = {
      grafana = mkOption { type = types.port; default = 3000; description = "Grafana UI."; };
      loki = mkOption { type = types.port; default = 3100; description = "Loki HTTP API."; };
      tempo = mkOption { type = types.port; default = 3200; description = "Tempo HTTP API."; };
      prometheus = mkOption { type = types.port; default = 9090; description = "Prometheus HTTP API and OTLP metrics."; };
      otlpGrpc = mkOption { type = types.port; default = 4317; description = "Collector OTLP/gRPC."; };
      otlpHttp = mkOption { type = types.port; default = 4318; description = "Collector OTLP/HTTP."; };
    };

    listenAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Host address the published ports bind to.";
    };

    exposeBeyondLoopback = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Allow `listenAddress` to be something other than 127.0.0.1. The stores have no
        authentication; Grafana drops to a viewer role when this is on.
      '';
    };

    dataDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Bind-mount root for the stores. Null picks `$XDG_DATA_HOME/observability` on Linux
        and `~/Library/Application Support/observability` on macOS (the stack's podman machine
        shares the home directory, not the Nix store).
      '';
    };

    images = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          repo = mkOption { type = types.str; };
          tag = mkOption { type = types.str; };
          digest = mkOption { type = types.str; };
        };
      });
      default = import ./images.nix;
      description = "Pinned container images: repository, tag and manifest digest.";
    };

    hostLabel = mkOption {
      type = types.str;
      default = args.osConfig.networking.hostName or "localhost";
      defaultText = lib.literalMD "the NixOS host name, else `localhost`";
      description = "Value of the `host` label added to everything the collector forwards.";
    };

    claudeCode = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Point Claude Code's telemetry export at the collector (user-level settings).";
      };
      traces = mkOption {
        type = types.bool;
        default = true;
        description = "Export traces too (Claude Code's beta tracing).";
      };
      includeRepository = mkOption {
        type = types.bool;
        default = true;
        description = "Add the repository to token metrics, for per-project spend.";
      };
      capturePrompts = mkOption {
        type = types.bool;
        default = false;
        description = "Store prompt and response text. Off: the collector drops it even if a flag sends it.";
      };
      captureToolDetails = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Store tool parameters and inputs (shell commands, file paths). Off: the collector
          drops `tool_parameters`, `tool_input`, `full_command` and `file_path`. Skill and MCP
          server names are configuration names, not tool content; they stay as labels so cost
          can be attributed per skill and per MCP server.
        '';
      };
    };

    prices = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          inputPerMTok = mkOption { type = types.number; };
          outputPerMTok = mkOption { type = types.number; };
          cacheReadPerMTok = mkOption { type = types.number; };
          cacheWritePerMTok = mkOption { type = types.number; };
        };
      });
      default = import ./prices.nix;
      description = ''
        USD per million tokens, per model name as Claude Code reports it. Used only for the
        cost estimate series `obs:token_cost_usd_estimate`; a model missing here has no estimate.
      '';
    };

    ledger = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Install the cc-obs-ledger hooks: per-turn context size, cache hit ratio and tool-call hashes.";
      };
      package = mkOption {
        type = types.package;
        default = pkgs.token-tools;
        defaultText = lib.literalExpression "pkgs.token-tools";
        description = "Package providing the cc-obs-ledger binary.";
      };
    };

    review = {
      enable = mkEnableOption "the weekly unattended token review (needs the Claude Code CLI and the stack running). Takes effect only once the review runner (spec task T056) is implemented; today it only adds the session-start notice hook";
      schedule = mkOption {
        type = types.str;
        default = "Mon 06:00";
        description = "systemd OnCalendar expression on Linux; the weekday and time are mapped to a launchd calendar interval on macOS. Takes effect only once the review runner (T056) is implemented.";
      };
      digestModel = mkOption {
        type = types.str;
        default = "haiku";
        description = "Model for stage 1, which runs the cc-obs-query commands and submits the digest. Takes effect only once the review runner (T056) is implemented.";
      };
      analysisModel = mkOption {
        type = types.str;
        default = "opus";
        description = "Model for stage 2, which reads only the digest and writes the findings. Takes effect only once the review runner (T056) is implemented.";
      };
      maxBudgetUSD = {
        digest = mkOption { type = types.numbers.positive; default = 0.25; description = "`--max-budget-usd` for stage 1. Takes effect only once the review runner (T056) is implemented."; };
        analysis = mkOption { type = types.numbers.positive; default = 2.0; description = "`--max-budget-usd` for stage 2. Takes effect only once the review runner (T056) is implemented."; };
      };
      notify = mkOption {
        type = types.bool;
        default = true;
        description = "Print a one-line notice at session start when findings wait to be promoted or dismissed.";
      };
      stateDir = mkOption {
        type = types.str;
        default = "${config.xdg.stateHome}/token-review";
        defaultText = lib.literalExpression ''"''${config.xdg.stateHome}/token-review"'';
        description = "Digests and draft findings. Never inside a repository. The session-start notice reads it today; the review runner (T056) will write it.";
      };
    };

    podmanPackage = mkOption {
      type = types.package;
      default = pkgs.podman;
      defaultText = lib.literalExpression "pkgs.podman";
      description = "podman used by the runner on macOS; on Linux the system podman is used when present.";
    };

    podmanMachine = {
      name = mkOption {
        type = types.str;
        default = "observability";
        description = "macOS only, ignored on Linux. Name of the stack's own podman machine, kept apart from other container tools such as Colima and from podman's default machine. Per podman's documentation, podman runs one machine at a time on macOS, so the runner refuses to start (it never stops anything) while another machine is running; stop that one or set this to its name. Not yet verified on the owner's Mac (spike T005).";
      };
      cpus = mkOption {
        type = types.ints.positive;
        default = 2;
        description = "macOS only, ignored on Linux. CPUs of the podman machine, sized for Loki, Tempo, Prometheus, Grafana and the collector. Applied only when the machine is created; to change it run `podman machine rm <name>` first (the data lives in the data dir, not the VM).";
      };
      memoryMiB = mkOption {
        type = types.ints.positive;
        default = 4096;
        description = "macOS only, ignored on Linux. Memory in MiB of the podman machine, sized for Loki, Tempo, Prometheus, Grafana and the collector. Applied only when the machine is created; to change it run `podman machine rm <name>` first.";
      };
      diskSizeGiB = mkOption {
        type = types.ints.positive;
        default = 30;
        description = "macOS only, ignored on Linux. Disk in GiB of the podman machine VM (images and scratch; the stores live in the data dir). Applied only when the machine is created; to change it run `podman machine rm <name>` first.";
      };
    };

    rendered = mkOption {
      type = types.attrs;
      readOnly = true;
      internal = true;
      description = "Everything the module generates, for tests.";
    };
  };

  config = mkMerge [
    {
      modules.observabilityStack.rendered = {
        inherit pod;
        podYaml = pod.yamlFile;
        loki = configs.loki;
        tempo = configs.tempo;
        prometheus = configs.prometheus;
        prometheusArgs = configs.prometheusArgs;
        prometheusRules = configs.rules;
        collector = collector.config;
        grafanaDatasources = grafana.datasources;
        configFiles = configs.files // collector.files // grafana.files;
        scripts = { inherit (scripts) run guard; };
        machineScripts = lib.genAttrs [ "darwin" "linux" ] (os:
          scripts.machineScript { isDarwin = os == "darwin"; machine = cfg.podmanMachine; });
        inherit endpoints;
      };
    }

    (mkIf cfg.enable {
      # The single place client tools (cc-obs-query, cc-obs-ledger) read ports from.
      home.file."${relativeConfigDir}/cc-obs/endpoints.json".text = builtins.toJSON rendered.endpoints;

      assertions = [
        {
          assertion = budgetSum * 10 <= cfg.maxDiskGB * 9;
          message = ''
            modules.observabilityStack.budgetSplitGB sums to ${toString budgetSum} GB, over 90% of
            maxDiskGB (${toString cfg.maxDiskGB}). Lower the split or raise maxDiskGB; the rest is
            headroom for Grafana state and the collector queue.
          '';
        }
        {
          assertion = lib.length (lib.unique portValues) == lib.length portValues;
          message = "modules.observabilityStack.ports: two services share a port (${lib.concatMapStringsSep ", " toString portValues}). Give each its own.";
        }
      ]
      ++ lib.concatLists (lib.mapAttrsToList
        (option: port: lib.mapAttrsToList
          (name: internal: {
            assertion = port != internal;
            message = "modules.observabilityStack.ports.${option} = ${toString port} clashes with the stack's internal ${name} port; the pod shares one network namespace, so the service would fail to start. Pick another port.";
          })
          internalPorts)
        cfg.ports)
      ++ [
        {
          assertion = lib.all (p: !(lib.elem p knownUsedPorts)) portValues;
          message = "modules.observabilityStack.ports uses a port other modules in this repository bind (${lib.concatMapStringsSep ", " toString knownUsedPorts}). Pick another.";
        }
        {
          assertion = cfg.listenAddress == "127.0.0.1" || cfg.exposeBeyondLoopback;
          message = ''
            modules.observabilityStack.listenAddress is "${cfg.listenAddress}", not 127.0.0.1. The stores have
            no authentication; set modules.observabilityStack.exposeBeyondLoopback = true to publish them anyway.
          '';
        }
        {
          assertion = lib.all imageOk (lib.attrValues cfg.images);
          message = "modules.observabilityStack.images: every image needs a sha256 digest and a tag other than latest (see images.nix).";
        }
        {
          assertion = builtins.match "[A-Za-z0-9][A-Za-z0-9_.-]*" cfg.podmanMachine.name != null;
          message = "modules.observabilityStack.podmanMachine.name \"${cfg.podmanMachine.name}\" is not a valid podman machine name: use letters, digits, '_', '.' and '-', starting with a letter or digit.";
        }
        {
          assertion = osPodman == null || (osPodman.modules.podman.enable or false);
          message = "modules.observabilityStack needs rootless podman: set modules.podman.enable = true on this NixOS host.";
        }
      ];
    })

    # OTEL_* variables are only read from user-level or managed settings, never from a
    # project's .claude/settings.json.
    (mkIf (cfg.enable && cfg.claudeCode.enable) {
      programs.claude-code.settings.env =
        {
          CLAUDE_CODE_ENABLE_TELEMETRY = "1";
          OTEL_METRICS_EXPORTER = "otlp";
          OTEL_LOGS_EXPORTER = "otlp";
          OTEL_TRACES_EXPORTER = if cfg.claudeCode.traces then "otlp" else "none";
          OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf";
          OTEL_EXPORTER_OTLP_ENDPOINT = rendered.endpoints.urls.otlpHttp;
        }
        // lib.optionalAttrs cfg.claudeCode.traces { CLAUDE_CODE_ENHANCED_TELEMETRY_BETA = "1"; }
        // lib.optionalAttrs cfg.claudeCode.includeRepository { OTEL_METRICS_INCLUDE_REPOSITORY = "1"; }
        // lib.optionalAttrs cfg.claudeCode.capturePrompts { OTEL_LOG_USER_PROMPTS = "1"; }
        // lib.optionalAttrs cfg.claudeCode.captureToolDetails { OTEL_LOG_TOOL_DETAILS = "1"; };
    })

    # memory-recall ships its records to Loki and, through the collector, its spans and
    # metrics to Tempo and Prometheus. mkDefault, so an explicit value still wins.
    (mkIf (cfg.enable && (config.modules.memoryRecall.enable or false)) {
      modules.memoryRecall.telemetry = {
        lokiUrl = lib.mkDefault rendered.endpoints.urls.loki;
        tempoEndpoint = lib.mkDefault rendered.endpoints.urls.otlpHttp;
      };
    })

    # Appended to the hooks in home/programs/claude-code, as memory-recall does. The ledger
    # prints nothing and always exits 0, so none of these can hold up or block a prompt.
    (mkIf (cfg.enable && cfg.ledger.enable) {
      home.packages = [ cfg.ledger.package ];
      programs.claude-code.settings.hooks =
        let
          ledger = sub: [
            {
              hooks = [
                {
                  type = "command";
                  command = "${cfg.ledger.package}/bin/cc-obs-ledger ${sub}";
                  timeout = 5;
                }
              ];
            }
          ];
        in
        {
          SessionStart = ledger "census" ++ [
            {
              hooks = [
                {
                  type = "command";
                  command = "env CC_OBS_REVIEW_STATE_DIR=${lib.escapeShellArg cfg.review.stateDir} CC_OBS_STACK_STATE_DIR=${lib.escapeShellArg stateDir} ${cfg.ledger.package}/bin/cc-obs-ledger notice";
                  timeout = 5;
                }
              ];
            }
          ];
          Stop = ledger "turn";
          SessionEnd = ledger "end";
        };
    })

    (mkIf (cfg.enable && isLinux) (import ./runner-linux.nix (ctx // { inherit scripts; })))
    (mkIf (cfg.enable && isDarwin) (import ./runner-darwin.nix (ctx // { inherit scripts; })))
  ];
}
