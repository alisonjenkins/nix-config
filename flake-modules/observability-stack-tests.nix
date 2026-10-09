# Evaluates the observability-stack home module with a stub of the
# home-manager options it touches and asserts on what it renders (spec 007).
# Nothing here starts a container.
#   nix build .#checks.x86_64-linux.observability-stack-render
{ self, inputs, ... }:
{
  perSystem = { pkgs, lib, system, ... }:
    lib.optionalAttrs (system == "x86_64-linux" || system == "aarch64-linux") (
      let
        darwinPkgs = import inputs.nixpkgs { system = "aarch64-darwin"; };

        stub = { lib, ... }:
          let
            anyAttrs = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; };
          in
          {
            options = {
              assertions = lib.mkOption { type = lib.types.listOf lib.types.attrs; default = [ ]; };
              home.homeDirectory = lib.mkOption { type = lib.types.str; default = "/home/test"; };
              home.file = anyAttrs;
              home.packages = lib.mkOption { type = lib.types.listOf lib.types.package; default = [ ]; };
              xdg.dataHome = lib.mkOption { type = lib.types.str; default = "/home/test/.local/share"; };
              xdg.stateHome = lib.mkOption { type = lib.types.str; default = "/home/test/.local/state"; };
              xdg.configHome = lib.mkOption { type = lib.types.str; default = "/home/test/.config"; };
              xdg.cacheHome = lib.mkOption { type = lib.types.str; default = "/home/test/.cache"; };
              systemd.user.services = anyAttrs;
              systemd.user.timers = anyAttrs;
              launchd.agents = anyAttrs;
              modules.memoryRecall = {
                enable = lib.mkOption { type = lib.types.bool; default = false; };
                telemetry.lokiUrl = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
                telemetry.tempoEndpoint = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
              };
              programs.claude-code.settings = lib.mkOption { type = lib.types.attrs; default = { }; };
            };
          };

        # The real package comes from the repo overlay, which a bare nixpkgs lacks.
        fakeLedger = pkgs.writeShellScriptBin "cc-obs-ledger" "";

        evalWith = { p ? pkgs, extra ? { }, recall ? { } }: lib.evalModules {
          specialArgs = { pkgs = p; };
          modules = [
            stub
            self.homeModules.observability-stack
            { modules.observabilityStack = { enable = true; ledger.package = fakeLedger; } // extra; }
            { modules.memoryRecall = recall; }
          ];
        };

        base = evalWith { };
        darwin = evalWith { p = darwinPkgs; };
        rendered = (evalWith { }).config.modules.observabilityStack.rendered;
        containers = rendered.pod.spec.containers;

        # The run script's port pre-check is tested with a listener on this port.
        runPort = 38123;
        runRendered = (evalWith { extra.ports.grafana = runPort; }).config.modules.observabilityStack.rendered;

        machineExtra = { name = "obs-test"; cpus = 3; memoryMiB = 5000; diskSizeGiB = 40; };
        machineScripts = (evalWith { extra.podmanMachine = machineExtra; }).config.modules.observabilityStack.rendered.machineScripts;
        linesWith = needle: lib.filter (l: lib.hasInfix needle l) (lib.splitString "\n" machineScripts.darwin);

        failedAssertions = e: builtins.filter (a: !a.assertion) e.config.assertions;
        # True when an assertion fails and its message contains `needle`. An evaluation
        # error (a misspelled option, a type error) is not caught, so it fails the check
        # instead of passing as a rejection.
        rejects = extra: needle:
          let
            e = evalWith { inherit extra; };
            msgs = map (a: a.message) (failedAssertions e);
          in
          lib.any (m: lib.hasInfix needle m) msgs;
        accepts = extra: failedAssertions (evalWith { inherit extra; }) == [ ];

        pinned = c: builtins.match ".*@sha256:[0-9a-f]{64}" c.image != null;
        hostPorts = c: map (p: p.hostIP) (c.ports or [ ]);
        allHostIPs = lib.concatMap hostPorts containers;
        containerNames = map (c: c.name) containers;
        grafanaEnvOf = e: builtins.listToAttrs (lib.concatMap
          (c: if c.name == "grafana" then c.env else [ ])
          e.config.modules.observabilityStack.rendered.pod.spec.containers);
        domainVars = [ "GF_SERVER_DOMAIN" "GF_SERVER_ENFORCE_DOMAIN" "GF_SERVER_ROOT_URL" ];

        # Ports the pod's own services bind in the shared network namespace, pinned here
        # so dropping one from the module's list fails a case.
        internalPorts = {
          "collector self-metrics" = 8888;
          "collector health" = 13133;
          "tempo OTLP gRPC" = 14317;
          "tempo OTLP HTTP" = 14318;
          "loki gRPC" = 9096;
        };

        cases = {
          "pod has the five services" =
            lib.sort lib.lessThan containerNames == [ "collector" "grafana" "loki" "prometheus" "tempo" ];
          "every image is pinned by digest" = lib.all pinned containers;
          "no image uses a floating tag" = lib.all (c: !(lib.hasInfix ":latest" c.image)) containers;
          "images only pulled when missing" = lib.all (c: c.imagePullPolicy == "IfNotPresent") containers;
          "rejects an image without a digest" = rejects
            { images.loki = { repo = "docker.io/grafana/loki"; tag = "3.7.8"; digest = ""; }; }
            "modules.observabilityStack.images";
          "rejects a latest tag" = rejects
            {
              images.loki = {
                repo = "docker.io/grafana/loki";
                tag = "latest";
                digest = "sha256:1107dd5274e0ada47e42472b7a7e71f3b2a2fe878878108f3e2f9e51528f0193";
              };
            }
            "modules.observabilityStack.images";
          "a misspelled option is an evaluation error, not a rejection" =
            !(builtins.tryEval (rejects { listenAdress = "0.0.0.0"; } "exposeBeyondLoopback")).success;

          "published ports bind loopback by default" =
            allHostIPs != [ ] && lib.all (ip: ip == "127.0.0.1") allHostIPs;
          "rejects a wider listen address without opt-in, naming the opt-in" =
            rejects { listenAddress = "0.0.0.0"; } "exposeBeyondLoopback";
          "accepts a wider listen address with opt-in" =
            accepts { listenAddress = "0.0.0.0"; exposeBeyondLoopback = true; };
          "wider listen address is published when opted in" =
            let
              e = evalWith { extra = { listenAddress = "0.0.0.0"; exposeBeyondLoopback = true; }; };
              ips = lib.concatMap hostPorts e.config.modules.observabilityStack.rendered.pod.spec.containers;
            in
            ips != [ ] && lib.all (ip: ip == "0.0.0.0") ips;
          "rejects duplicate ports" = rejects { ports.loki = 3000; } "two services share a port";
          "rejects a port already used in this repo" = rejects { ports.grafana = 8080; } "other modules in this repository bind";
          "accepts the default ports" = accepts { };
          "loopback grafana enforces the localhost domain against DNS rebinding" =
            let env = grafanaEnvOf base;
            in env.GF_SERVER_DOMAIN == "localhost" && env.GF_SERVER_ENFORCE_DOMAIN == "true"
              && env.GF_SERVER_ROOT_URL == "http://localhost:3000/";
          "loopback grafana root url follows the grafana port" =
            (grafanaEnvOf (evalWith { extra.ports.grafana = 3999; })).GF_SERVER_ROOT_URL == "http://localhost:3999/";
          "exposed grafana sets no domain variables" =
            let env = grafanaEnvOf (evalWith { extra = { listenAddress = "0.0.0.0"; exposeBeyondLoopback = true; }; });
            in lib.all (v: !(env ? ${v})) domainVars;

          "macOS machine script names the dedicated machine" = lib.hasInfix "machine=obs-test" machineScripts.darwin;
          "macOS machine init passes the configured sizing and the name" =
            linesWith "podman machine init" == [ "  podman machine init --cpus 3 --memory 5000 --disk-size 40 \"$machine\"" ];
          "every podman machine call names the machine" =
            let lifecycle = lib.filter (l: !(lib.hasInfix "podman machine list" l || lib.hasInfix "echo" l)) (linesWith "podman machine");
            in lifecycle != [ ] && lib.all (l: lib.hasInfix "\"$machine\"" l) lifecycle;
          "macOS machine script points later podman calls at it" =
            lib.hasInfix "export CONTAINER_CONNECTION=\"$machine\"" machineScripts.darwin;
          "linux machine script is empty" = machineScripts.linux == "";
          "machine defaults are observability, 2 CPUs, 4 GiB, 30 GiB" =
            base.config.modules.observabilityStack.podmanMachine
            == { name = "observability"; cpus = 2; memoryMiB = 4096; diskSizeGiB = 30; };
          "rejects a machine name with a leading dash" = rejects { podmanMachine.name = "-bad"; } "podmanMachine.name";
          "rejects a machine name with a space" = rejects { podmanMachine.name = "a b"; } "podmanMachine.name";
          "accepts a dotted machine name" = accepts { podmanMachine.name = "obs.1_x-y"; };
        }
        // lib.mapAttrs'
          (what: port: lib.nameValuePair "rejects ports.grafana on the internal ${what} port ${toString port}"
            (rejects { ports.grafana = port; } "modules.observabilityStack.ports.grafana = ${toString port}"))
          internalPorts
        // {

          "loki retention is 30 days" = rendered.loki.limits_config.retention_period == "720h";
          "loki compactor enforces retention" = rendered.loki.compactor.retention_enabled;
          "tempo retention is 30 days" = rendered.tempo.compactor.compaction.block_retention == "720h";
          "prometheus retention is 30 days" =
            lib.elem "--storage.tsdb.retention.time=30d" rendered.prometheusArgs;
          "prometheus size limit comes from the budget" =
            lib.elem "--storage.tsdb.retention.size=4GB" rendered.prometheusArgs;
          "retention follows the option" =
            let r = (evalWith { extra.retentionDays = 7; }).config.modules.observabilityStack.rendered;
            in r.loki.limits_config.retention_period == "168h"
              && lib.elem "--storage.tsdb.retention.time=7d" r.prometheusArgs;
          "rejects a budget split over 90 percent of the cap" =
            rejects { budgetSplitGB = { prometheus = 6; loki = 7; tempo = 7; }; } "modules.observabilityStack.budgetSplitGB";
          "accepts a budget split at 90 percent of the cap" =
            accepts { budgetSplitGB = { prometheus = 4; loki = 7; tempo = 7; }; };

          "prometheus promotes the resource attributes the views use" =
            rendered.prometheus.otlp.promote_resource_attributes == [ "host" "review.run" "repository" ];
          "a cost estimate rule exists per model and token type, labelled as an estimate" =
            let rules = (lib.head rendered.prometheusRules.groups).rules;
            in lib.length rules == 16
              && lib.all (r: r.record == "obs:token_cost_usd_estimate" && r.labels.estimate == "true") rules;
          "changing a price changes the rule" =
            let
              exprs = e: map (r: r.expr) (lib.head e.config.modules.observabilityStack.rendered.prometheusRules.groups).rules;
              changed = evalWith { extra.prices."claude-haiku-5-5".inputPerMTok = 1.0; };
            in
            exprs base != exprs changed;
          "a model without prices gets no estimate" =
            (lib.head (evalWith { extra.prices = { }; }).config.modules.observabilityStack.rendered.prometheusRules.groups).rules == [ ];
          "prometheus loads the rules file" = lib.elem "/config/rules.yml" rendered.prometheus.rule_files;
          "prometheus accepts OTLP" = lib.elem "--web.enable-otlp-receiver" rendered.prometheusArgs;

          "grafana provisions loki, tempo and prometheus" =
            lib.sort lib.lessThan (map (d: d.uid) rendered.grafanaDatasources.datasources)
            == [ "loki" "prometheus" "tempo" ];

          "client tools read their ports from one endpoints file" =
            let
              file = base.config.home.file.".config/cc-obs/endpoints.json".text;
              parsed = builtins.fromJSON file;
            in
            parsed.ports.loki == 3100 && parsed.urls.otlpHttp == "http://127.0.0.1:4318";
          "endpoints follow the port options" =
            let
              e = evalWith { extra.ports.loki = 3101; };
              parsed = builtins.fromJSON e.config.home.file.".config/cc-obs/endpoints.json".text;
            in
            parsed.urls.loki == "http://127.0.0.1:3101";

          "claude settings point at the collector" =
            let env = base.config.programs.claude-code.settings.env;
            in env.CLAUDE_CODE_ENABLE_TELEMETRY == "1"
              && env.OTEL_EXPORTER_OTLP_ENDPOINT == "http://127.0.0.1:4318"
              && env.OTEL_EXPORTER_OTLP_PROTOCOL == "http/protobuf"
              && env.OTEL_METRICS_EXPORTER == "otlp"
              && env.OTEL_LOGS_EXPORTER == "otlp"
              && env.OTEL_TRACES_EXPORTER == "otlp";
          "the claude endpoint follows the collector port" =
            (evalWith { extra.ports.otlpHttp = 4999; }).config.programs.claude-code.settings.env.OTEL_EXPORTER_OTLP_ENDPOINT
            == "http://127.0.0.1:4999";
          "content gates are off by default" =
            let env = base.config.programs.claude-code.settings.env;
            in !(env ? OTEL_LOG_USER_PROMPTS) && !(env ? OTEL_LOG_TOOL_DETAILS)
              && !(env ? OTEL_LOG_TOOL_CONTENT) && !(env ? OTEL_LOG_RAW_API_BODIES);
          "prompt capture sets only its own gate" =
            let env = (evalWith { extra.claudeCode.capturePrompts = true; }).config.programs.claude-code.settings.env;
            in env.OTEL_LOG_USER_PROMPTS == "1" && !(env ? OTEL_LOG_TOOL_DETAILS);
          "tool detail capture sets only its own gate" =
            let env = (evalWith { extra.claudeCode.captureToolDetails = true; }).config.programs.claude-code.settings.env;
            in env.OTEL_LOG_TOOL_DETAILS == "1" && !(env ? OTEL_LOG_USER_PROMPTS);
          "token metrics carry the repository by default" =
            base.config.programs.claude-code.settings.env.OTEL_METRICS_INCLUDE_REPOSITORY == "1";
          "the repository label can be turned off" =
            !((evalWith { extra.claudeCode.includeRepository = false; }).config.programs.claude-code.settings.env ? OTEL_METRICS_INCLUDE_REPOSITORY);
          "traces off exports none and drops the beta flag" =
            let env = (evalWith { extra.claudeCode.traces = false; }).config.programs.claude-code.settings.env;
            in env.OTEL_TRACES_EXPORTER == "none" && !(env ? CLAUDE_CODE_ENHANCED_TELEMETRY_BETA);
          "the ledger hooks cover session start, stop and end" =
            let
              hooks = base.config.programs.claude-code.settings.hooks;
              command = event: (lib.head (lib.head hooks.${event}).hooks).command;
            in
            lib.hasSuffix "/bin/cc-obs-ledger census" (command "SessionStart")
            && lib.hasSuffix "/bin/cc-obs-ledger turn" (command "Stop")
            && lib.hasSuffix "/bin/cc-obs-ledger end" (command "SessionEnd");
          "no ledger hook can hold a prompt for long" =
            let hooks = base.config.programs.claude-code.settings.hooks;
            in lib.all (event: (lib.head (lib.head hooks.${event}).hooks).timeout <= 5) (lib.attrNames hooks);
          "the notice hook runs when the ledger is enabled" =
            lib.any (entry: lib.any (h: lib.hasInfix "cc-obs-ledger notice" h.command) entry.hooks)
              (evalWith { }).config.programs.claude-code.settings.hooks.SessionStart;
          "the notice hook is absent when the ledger is off" =
            !((evalWith { extra.ledger.enable = false; }).config.programs.claude-code.settings ? hooks);
          "the notice hook does not depend on the review switches" =
            lib.any (entry: lib.any (h: lib.hasInfix "cc-obs-ledger notice" h.command) entry.hooks)
              (evalWith { extra.review = { enable = false; notify = false; }; }).config.programs.claude-code.settings.hooks.SessionStart;
          "the notice hook is told where the guard state lives" =
            lib.any (entry: lib.any (h: lib.hasInfix "cc-obs-ledger notice" h.command && lib.hasInfix "CC_OBS_STACK_STATE_DIR=" h.command && lib.hasInfix "/observability-stack" h.command) entry.hooks)
              base.config.programs.claude-code.settings.hooks.SessionStart;
          "the ledger hooks can be switched off" =
            (evalWith { extra.ledger.enable = false; }).config.programs.claude-code.settings
            ? hooks == false;
          "claude wiring can be switched off" =
            !((evalWith { extra.claudeCode.enable = false; }).config.programs.claude-code.settings ? env);
          "with claude wiring and the ledger both off no settings are written" =
            (evalWith { extra = { claudeCode.enable = false; ledger.enable = false; }; }).config.programs.claude-code.settings == { };
          "the collector drops prompt and tool keys by default" =
            let
              keys = map (a: a.key) rendered.collector.processors."attributes/redact".actions;
            in
            lib.elem "prompt" keys && lib.elem "tool_parameters" keys && lib.elem "api_request_body" keys;
          "the default redaction list is exactly the documented keys and keeps skill and mcp server names" =
            let
              keys = map (a: a.key) rendered.collector.processors."attributes/redact".actions;
            in
            lib.sort lib.lessThan keys == lib.sort lib.lessThan [
              "api_request_body"
              "api_response_body"
              "tool_content"
              "prompt"
              "prompt_text"
              "user_prompt"
              "response"
              "response_text"
              "tool_parameters"
              "tool_input"
              "full_command"
              "file_path"
            ]
            && !(lib.elem "skill_name" keys) && !(lib.elem "mcp_server_name" keys);
          "the metrics pipeline converts delta sums to cumulative, the others do not" =
            let
              p = rendered.collector.service.pipelines;
              has = name: lib.elem "deltatocumulative" p.${name}.processors;
              ordered = lib.last (lib.init p.metrics.processors) == "deltatocumulative"
                && lib.last p.metrics.processors == "batch";
            in
            rendered.collector.processors ? deltatocumulative && has "metrics" && ordered && !(has "logs") && !(has "traces");
          "the collector keeps prompt keys when prompts are captured" =
            let
              r = (evalWith { extra.claudeCode.capturePrompts = true; }).config.modules.observabilityStack.rendered.collector;
              keys = map (a: a.key) r.processors."attributes/redact".actions;
            in
            !(lib.elem "prompt" keys) && lib.elem "tool_parameters" keys;

          "memory-recall ships to the stack when both modules are on" =
            let t = (evalWith { recall.enable = true; }).config.modules.memoryRecall.telemetry;
            in t.lokiUrl == "http://127.0.0.1:3100" && t.tempoEndpoint == "http://127.0.0.1:4318";
          "an explicit memory-recall endpoint wins" =
            let t = (evalWith { recall = { enable = true; telemetry.lokiUrl = "http://elsewhere:3100"; }; }).config.modules.memoryRecall.telemetry;
            in t.lokiUrl == "http://elsewhere:3100" && t.tempoEndpoint == "http://127.0.0.1:4318";
          "memory-recall is left alone when it is off" =
            let t = base.config.modules.memoryRecall.telemetry;
            in t.lokiUrl == null && t.tempoEndpoint == null;
          "recall log lines link to the traces of their session" =
            let loki = lib.findFirst (d: d.uid == "loki") null rendered.grafanaDatasources.datasources;
            in loki != null && (lib.head loki.jsonData.derivedFields).datasourceUid == "tempo";

          "linux gets a systemd user service and no launchd agent" =
            base.config.systemd.user.services ? observability-stack
            && base.config.launchd.agents == { };
          "darwin gets a launchd agent and no systemd unit" =
            darwin.config.launchd.agents ? observability-stack
            && darwin.config.systemd.user.services == { };
          "both platforms render the same pod ports" =
            let d = darwin.config.modules.observabilityStack.rendered.pod.spec.containers;
            in map (c: c.ports or [ ]) containers == map (c: c.ports or [ ]) d
              && map (c: map (p: p.containerPort) (c.ports or [ ])) containers
              == map (c: map (p: p.containerPort) (c.ports or [ ])) d
              && lib.concatMap (c: map (p: p.hostPort) (c.ports or [ ])) containers
              == lib.concatMap (c: map (p: p.hostPort) (c.ports or [ ])) d
              && lib.concatMap (c: map (p: p.hostPort) (c.ports or [ ])) containers != [ ];
          "both platforms render the same datasources" =
            rendered.grafanaDatasources == darwin.config.modules.observabilityStack.rendered.grafanaDatasources;
        };

        dashboards = lib.mapAttrs (_: path: builtins.fromJSON (builtins.readFile path))
          (lib.filterAttrs (name: _: lib.hasPrefix "grafana/dashboards/" name) rendered.configFiles);
        datasourceUids = dashboard:
          let
            uidOf = x: lib.optional (x ? datasource && x.datasource ? uid) x.datasource.uid;
            panels = dashboard.panels or [ ];
            variables = dashboard.templating.list or [ ];
          in
          lib.unique (
            lib.concatMap (p: uidOf p ++ lib.concatMap uidOf (p.targets or [ ])) panels
            ++ lib.concatMap uidOf variables
          );
        stackHealth = lib.findFirst (d: d.uid == "stack-health") { panels = [ ]; } (lib.attrValues dashboards);
        panelIds = dashboard: map (p: p.id) (dashboard.panels or [ ]);

        # Every series a dashboard queries. Names ending in a stem (observability_guard_*,
        # claude_code_cost_usage) are matched in the dashboards by `__name__=~"stem.*"`
        # because the exporter appends unit suffixes.
        knownMetrics = [
          "up"
          "claude_code_token_usage_tokens_total"
          "claude_code_session_count_total"
          "claude_code_active_time_seconds_total"
          "claude_code_cost_usage"
          "cc_obs_ledger_context_tokens"
          "cc_obs_ledger_fixed_context_tokens"
          "cc_obs_ledger_cache_hit_ratio"
          "recall_requests_total"
          "recall_hits_total"
          "recall_latency_seconds"
          "recall_tokens_injected_total"
          "observability_guard_used_bytes"
          "observability_guard_cap_bytes"
          "observability_guard_over_budget"
          "obs:token_cost_usd_estimate"
          "otelcol_receiver_refused_spans_total"
          "otelcol_receiver_refused_log_records_total"
          "otelcol_receiver_refused_metric_points_total"
          "otelcol_exporter_send_failed_spans_total"
          "otelcol_exporter_send_failed_log_records_total"
          "otelcol_exporter_send_failed_metric_points_total"
          "otelcol_receiver_accepted_spans_total"
          "otelcol_receiver_accepted_log_records_total"
          "otelcol_receiver_accepted_metric_points_total"
          "loki_distributor_lines_received_total"
          "loki_distributor_bytes_received_total"
          "tempo_distributor_spans_received_total"
          "prometheus_tsdb_head_series"
          "prometheus_tsdb_storage_blocks_bytes"
        ];
        metricPrefixes = [ "claude_code_" "cc_obs_ledger_" "recall_" "observability_guard_" "obs:" "otelcol_" "loki_" "tempo_" "prometheus_" ];
        # Metric-looking identifiers in the PromQL of the Prometheus-backed targets.
        promqlMetrics = dashboard:
          let
            promTargets = lib.concatMap
              (p: lib.filter
                (t: ((t.datasource or p.datasource or { }).uid or "") == "prometheus" && t ? expr)
                (p.targets or [ ]))
              (dashboard.panels or [ ]);
            identifiers = expr: lib.filter lib.isString (builtins.split "[^a-zA-Z0-9_:]+" expr);
            metricLike = id: id == "up" || lib.any (pre: lib.hasPrefix pre id) metricPrefixes;
          in
          lib.unique (lib.filter metricLike (lib.concatMap (t: identifiers t.expr) promTargets));
        unknownMetrics = lib.concatMap
          (d: lib.filter (m: !(lib.elem m knownMetrics)) (promqlMetrics d))
          (lib.attrValues dashboards);

        dashboardCases = {
          "every metric a dashboard queries is a known series (unknown: ${lib.concatStringsSep ", " unknownMetrics})" =
            unknownMetrics == [ ];
          "the metric scan finds the metrics it is meant to check" =
            lib.all (m: lib.any (d: lib.elem m (promqlMetrics d)) (lib.attrValues dashboards))
              [ "claude_code_token_usage_tokens_total" "recall_latency_seconds" "cc_obs_ledger_context_tokens" "observability_guard_used_bytes" "observability_guard_over_budget" ];
          "stack-health reads every guard metric through last_over_time, so a late push is not No data" =
            let
              exprs = lib.concatMap (p: map (t: t.expr or "") (p.targets or [ ])) stackHealth.panels;
              guardExprs = lib.filter (e: lib.hasInfix "observability_guard_" e) exprs;
              bare = e: builtins.match ".*observability_guard_[a-z_]+[^a-z_\\[].*|.*observability_guard_[a-z_]+" e != null;
            in
            guardExprs != [ ] && lib.all (e: !(bare e)) guardExprs;
          "the metric scan sees metrics inside last_over_time" =
            lib.elem "observability_guard_used_bytes" (promqlMetrics stackHealth);
          "the four dashboards are provisioned by uid" =
            lib.sort lib.lessThan (map (d: d.uid) (lib.attrValues dashboards))
            == [ "claude-code" "recall" "stack-health" "token-cost" ];
          "every dashboard datasource is provisioned" =
            lib.all
              (d: lib.all (u: lib.elem u (map (s: s.uid) rendered.grafanaDatasources.datasources)) (datasourceUids d))
              (lib.attrValues dashboards);
          "dashboards have unique panel ids and titles on every panel" =
            lib.all
              (d: lib.length (lib.unique (panelIds d)) == lib.length (panelIds d) && lib.all (p: p ? title) d.panels)
              (lib.attrValues dashboards);
          "dashboards are tagged for the provider" =
            lib.all (d: lib.elem "observability-stack" d.tags) (lib.attrValues dashboards);
        };

        failed = lib.attrNames (lib.filterAttrs (_: ok: !ok) (cases // dashboardCases));

        # Runs the real collector with the module's processors over canary telemetry and
        # checks which canaries reach the exporter.
        redactionRun = name: extra: expectations:
          let
            r = (evalWith { inherit extra; }).config.modules.observabilityStack.rendered.collector;
            testConfig = (pkgs.formats.yaml { }).generate "redaction-${name}.yaml" {
              receivers.otlpjsonfile = {
                include = [ "input/*.jsonl" ];
                start_at = "beginning";
              };
              inherit (r) processors;
              exporters."file/out".path = "out.jsonl";
              service.pipelines = lib.genAttrs [ "logs" "traces" "metrics" ] (_: {
                receivers = [ "otlpjsonfile" ];
                processors = r.service.pipelines.logs.processors;
                exporters = [ "file/out" ];
              });
            };
          in
          pkgs.runCommand "observability-stack-redaction-${name}"
            { nativeBuildInputs = [ pkgs.opentelemetry-collector-contrib ]; }
            ''
              mkdir input
              cp ${self + "/home/modules/observability-stack/tests/fixtures"}/*.jsonl input/
              otelcol-contrib --config=${testConfig} > collector.log 2>&1 &
              pid=$!
              for _ in $(seq 120); do
                if [ "$(cat out.jsonl 2>/dev/null | wc -l)" -ge 3 ]; then break; fi
                sleep 0.5
              done
              kill $pid 2>/dev/null || true
              wait $pid 2>/dev/null || true
              lines=$(cat out.jsonl 2>/dev/null | wc -l)
              if [ "$lines" -lt 3 ]; then
                cat collector.log
                echo "expected 3 exported lines (logs, traces, metrics), got $lines"
                exit 1
              fi
              # `! grep` would be exempt from errexit, so say it with explicit exits.
              present() { grep -q "$1" out.jsonl || { echo "missing from export: $1"; exit 1; }; }
              absent() { if grep -q "$1" out.jsonl; then echo "leaked into export: $1"; exit 1; fi; }
              present KEEP-NAME
              ${expectations}
              touch $out
            '';
      in
      {
        checks.observability-stack-render =
          if failed == [ ]
          then pkgs.runCommand "observability-stack-render" { } "touch $out"
          else throw "observability-stack-render failing cases: ${lib.concatStringsSep "; " failed}";

        # The rendered store configs must be accepted by the real binaries, not only
        # look right. Versions are nixpkgs', a patch or two off the pinned images.
        checks.observability-stack-config-validate =
          let
            files = rendered.configFiles;
          in
          pkgs.runCommand "observability-stack-config-validate"
            {
              nativeBuildInputs = [ pkgs.grafana-loki pkgs.tempo pkgs.prometheus.cli pkgs.opentelemetry-collector-contrib ];
            }
            ''
              # The container path of the rules file does not exist in the sandbox.
              sed 's#/config/rules.yml#${files."rules.yml"}#' ${files."prometheus.yml"} > prometheus.yml
              promtool check config prometheus.yml
              promtool check rules ${files."rules.yml"}
              tempo -config.file=${files."tempo.yaml"} -config.verify=true
              loki -config.file=${files."loki.yaml"} -verify-config
              otelcol-contrib validate --config=${files."collector.yaml"}
              touch $out
            '';

        checks.observability-stack-redaction-default = redactionRun "default" { } ''
          absent CANARY-PROMPT
          absent CANARY-TOOL
        '';
        checks.observability-stack-redaction-prompts = redactionRun "prompts" { claudeCode.capturePrompts = true; } ''
          present CANARY-PROMPT
          absent CANARY-TOOL
        '';
        checks.observability-stack-redaction-tools = redactionRun "tools" { claudeCode.captureToolDetails = true; } ''
          absent CANARY-PROMPT
          present CANARY-TOOL
        '';

        checks.observability-stack-guard =
          pkgs.runCommand "observability-stack-guard"
            {
              nativeBuildInputs = [ pkgs.bats pkgs.coreutils pkgs.jq pkgs.python3 ];
              GUARD = "${rendered.scripts.guard}/bin/observability-stack-guard";
              RUN = "${runRendered.scripts.run}/bin/observability-stack-run";
              RUN_PORT = toString runPort;
              MACHINE = pkgs.writeShellScript "machine-step" machineScripts.darwin;
            }
            ''
              bats ${self + "/home/modules/observability-stack/tests/disk-guard.bats"}
              touch $out
            '';
      }
    );
}
