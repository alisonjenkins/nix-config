# Semantic recall of Claude memory files (scripts/retrieval-eval): a
# UserPromptSubmit hook injects the few memories closest to each prompt, backed
# by a local EmbeddingGemma 2 server. See docs/memory-recall.md.
{ config, lib, pkgs, ... }:
let
  cfg = config.modules.memoryRecall;
  inherit (lib) mkOption mkEnableOption mkIf types;

  inherit (pkgs.stdenv.hostPlatform) isLinux isDarwin;

  urlFor = port: "http://127.0.0.1:${toString port}";
  baseUrl = urlFor cfg.port;
  indexUrl = urlFor cfg.indexPort;

  stateDir = "${config.xdg.stateHome}/memory-recall";
  cacheFile = "${config.xdg.cacheHome}/memory-recall/gemma-${toString cfg.dims}.json";

  recallAt = url: lib.concatStringsSep " " [
    "${cfg.package}/bin/memory-recall"
    "--memory-dir ${lib.escapeShellArg cfg.memoryDir}"
    "--embedder ${lib.escapeShellArg "gemma=gemma@${url}#${toString cfg.dims}"}"
    "--cache ${lib.escapeShellArg cacheFile}"
  ];
  recall = recallAt baseUrl;

  telemetryArgs = lib.concatStrings (
    lib.optional (cfg.telemetry.lokiUrl != null) " --loki-url ${lib.escapeShellArg cfg.telemetry.lokiUrl}"
    ++ lib.optional (cfg.telemetry.tempoEndpoint != null) " --otlp-endpoint ${lib.escapeShellArg cfg.telemetry.tempoEndpoint}"
    ++ lib.optional (cfg.telemetry.tenantId != null) " --telemetry-tenant ${lib.escapeShellArg cfg.telemetry.tenantId}"
    ++ lib.optional (cfg.telemetry.headersFile != null) " --telemetry-headers-file ${lib.escapeShellArg cfg.telemetry.headersFile}"
    ++ lib.mapAttrsToList (k: v: " --telemetry-label ${lib.escapeShellArg "${k}=${v}"}") cfg.telemetry.labels
  );

  logArgs =
    lib.optionalString (cfg.logFile != null) " --log ${lib.escapeShellArg cfg.logFile}"
    + telemetryArgs;

  hookScript = pkgs.writeShellScript "memory-recall-hook" ''
    exec ${recall} hook --top ${toString cfg.top} --min-score ${toString cfg.minScore} \
      --body-score ${toString cfg.bodyScore} --inject ${cfg.inject} \
      --max-tokens ${toString cfg.maxTokens} \
      --on-unavailable ${cfg.onUnavailable}${logArgs}
  '';

  skillsCacheFile = "${config.xdg.cacheHome}/memory-recall/skills-gemma-${toString cfg.dims}.json";

  skillRecallAt = url: lib.concatStringsSep " " [
    "${cfg.package}/bin/skill-recall"
    "--skills-root ${lib.escapeShellArg cfg.skills.root}"
    "--embedder ${lib.escapeShellArg "gemma=gemma@${url}#${toString cfg.dims}"}"
    "--cache ${lib.escapeShellArg skillsCacheFile}"
  ];
  skillRecall = skillRecallAt baseUrl;

  skillsHookScript = pkgs.writeShellScript "skill-recall-hook" ''
    exec ${skillRecall} hook --top ${toString cfg.skills.top} \
      --min-score ${toString (if cfg.skills.pointerScore != null then cfg.skills.pointerScore else cfg.skills.minScore)} \
      --full-score ${toString cfg.skills.minScore} \
      --section-chars ${toString cfg.skills.sectionChars} \
      --max-tokens ${toString cfg.skills.maxTokens} \
      --on-unavailable ${cfg.onUnavailable}${logArgs}
  '';

  serverArgvOn = port: [
    "${cfg.llamaCpp}/bin/llama-server"
    "-m"
    "${cfg.model}"
    "--embeddings"
    "-c"
    "2048"
    "-ub"
    "2048"
    "-ngl"
    "0"
    "--host"
    "127.0.0.1"
    "--port"
    (toString port)
    # Warnings and errors only. At the default level the server writes about ten
    # lines to the journal for every embedding request (slot allocation and
    # release), which is a prompt's worth of noise per hook run.
    "--log-verbosity"
    "2"
  ] ++ lib.optionals (cfg.threads != null) [ "--threads" (toString cfg.threads) ];
  # Only the query server pins its pages; the index server is short-lived. This
  # llama.cpp has no --mlock: the loading mode is --load-mode (checked: --mlock
  # exits 1 with "invalid argument", which would crash-loop the unit).
  serverArgv = serverArgvOn cfg.port ++ [ "--load-mode" "mmap+mlock" ];

  # Embedding a long document makes llama.cpp keep its largest compute buffer for
  # good: the server goes from ~425 MB to ~1.6 GB after one long memory and ~2.7 GB
  # after a full index. So the index runs against its own short-lived server on
  # indexPort. The query server is never restarted, never grows, and picks up new
  # vectors because the hook reads the cache file on every prompt. The first index
  # embeds every memory (~70 s on CPU).
  indexScript = pkgs.writeShellApplication {
    name = "memory-recall-index";
    runtimeInputs = [ pkgs.coreutils pkgs.curl ];
    text = ''
      mkdir -p "$(dirname ${lib.escapeShellArg cacheFile})"
      ${lib.escapeShellArgs (serverArgvOn cfg.indexPort)} >/dev/null 2>&1 &
      server_pid=$!
      trap 'kill "$server_pid" 2>/dev/null || true' EXIT
      for _ in $(seq 1 120); do
        curl -fsS --max-time 2 ${indexUrl}/health >/dev/null && break
        sleep 1
      done
      # One failing step must not skip the others.
      status=0
      ${recallAt indexUrl} index || status=$?
      ${lib.optionalString cfg.skills.enable "${skillRecallAt indexUrl} index || status=$?"}
      ${lib.optionalString cfg.catalogue.enable "${recall} catalogue --write ${lib.escapeShellArg "${cfg.memoryDir}/MEMORY.md"} || status=$?"}
      exit "$status"
    '';
  };
in
{
  options.modules.memoryRecall = {
    enable = mkEnableOption "semantic recall of Claude memory files as a UserPromptSubmit hook";

    memoryDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/home/ali/.claude/projects/-home-ali-git-personal-nix-config/memory";
      description = ''
        Directory of memory `*.md` files to index. Claude keeps one per project,
        so this covers one project's memories.
      '';
    };

    package = mkOption {
      type = types.package;
      default = pkgs.memory-recall;
      description = "Package providing the memory-recall binary.";
    };

    llamaCpp = mkOption {
      type = types.package;
      default = pkgs.llama-cpp-upstream;
      description = ''
        llama.cpp providing llama-server. Must know the gemma-embedding2
        architecture, which nixpkgs unstable does not yet.
      '';
    };

    model = mkOption {
      type = types.path;
      default = pkgs.llama-models.embeddinggemma-2-q8-0.modelFile;
      description = "GGUF embedding model file.";
    };

    port = mkOption {
      type = types.port;
      default = 8110;
      description = "Loopback port of the embedding server.";
    };

    threads = mkOption {
      type = types.nullOr types.ints.positive;
      default = 4;
      description = ''
        llama-server CPU threads; null lets it use every core. Measured on a
        16-core/32-thread Ryzen 9 7950X: 4 threads answer a prompt in 23 ms
        against 17 ms for 16 or more, but spend 90 ms of CPU per prompt against
        about 270 ms, and idle at 2 ms/s against 10 ms/s, because llama.cpp's
        threads spin while waiting for work (docs/memory-recall.md).
      '';
    };

    dims = mkOption {
      type = types.enum [ 128 256 512 768 ];
      default = 512;
      description = ''
        Matryoshka dimensions kept per vector. Changing it, or the model,
        invalidates the vector cache and the score thresholds: re-measure
        minScore, bodyScore and the skills floors (docs/memory-recall.md).
        512 separates right from wrong matches better than 256: at the same
        recall, adjacent prompts get half the false injections (bench/results/dims-512.md).
      '';
    };

    top = mkOption {
      type = types.ints.positive;
      default = 3;
      description = "Most memories injected per prompt.";
    };

    minScore = mkOption {
      type = types.float;
      default = 0.70;
      description = ''
        Cosine similarity a memory must reach to be injected at all, as a
        one-line snippet. At 512 dimensions the right memory's best score ran
        0.68 to 0.86 over 88 queries on three sets and 90 to 93% of them clear
        0.70; 3% of off-topic and 35% of adjacent prompts do too, at about 35
        tokens a stray snippet. Measured for EmbeddingGemma 2.
      '';
    };

    maxTokens = mkOption {
      type = types.ints.positive;
      default = 1500;
      description = ''
        Most tokens the memory hook adds to one prompt; lower-ranked matches are
        dropped past it. Half of the 3,000-token ceiling the memory and skills
        hooks share.
      '';
    };

    bodyScore = mkOption {
      type = types.float;
      default = 0.74;
      description = ''
        With `inject = "auto"`, the score from which a memory is injected in
        full (about 1,000 tokens) so the model answers without opening the file.
        Higher than minScore because a wrong full memory is the expensive mistake:
        at 512 dimensions and 0.74, 3% of off-topic and 5% of adjacent prompts get
        one and 89 to 93% of injections are right.
      '';
    };

    inject = mkOption {
      type = types.enum [ "auto" "snippets" "top" "all" ];
      default = "auto";
      description = ''
        How much of a match the model sees: `auto` puts matches scoring at least
        bodyScore in full and the rest as one-line snippets; `snippets` never
        includes a body, so the model must open the file; `top` and `all` always
        put the best, or every, match in full.
      '';
    };

    indexPort = mkOption {
      type = types.port;
      default = 8111;
      description = ''
        Loopback port of the short-lived embedding server each index run starts
        and stops, so the query server is never restarted or grown by indexing.
      '';
    };

    catalogue.enable = mkEnableOption ''
      keeping `MEMORY.md` a names-only catalogue. After each index run the file is
      rewritten from the memory files, but only if its content changed, so a line
      Claude appends when it saves a memory is replaced by the bare name and the
      file cannot grow into the token overhead the hook exists to avoid. It
      overwrites a file Claude maintains, so it is off by default'';

    onUnavailable = mkOption {
      type = types.enum [ "block" "keyword" "allow" ];
      default = "block";
      description = ''
        What a hook does when it cannot retrieve memories or skills (the
        embedding server is down after 1.5 s of retries, or the directory cannot
        be read). `block` refuses the prompt with a message (exit code 2), so it is
        never answered without the context that might have stopped a mistake;
        `keyword` injects the keyword matches instead; `allow` lets the prompt
        through with nothing injected. `block` means Claude Code stops working
        until the server is back.
      '';
    };

    telemetry = {
      lokiUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "http://loki.example.lan:3100";
        description = ''
          Loki base URL. Each hook run is pushed there as one log line (the same
          JSON as `logFile`: scores, counts and timings, never the prompt),
          labelled `service` (`memory-recall` or `skill-recall`) and `kind`.
        '';
      };

      tempoEndpoint = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "http://tempo.example.lan:4318";
        description = ''
          OTLP/HTTP base URL of Tempo or a collector in front of it (port 4318;
          spans go to `/v1/traces`). Each hook run becomes a `memory-recall.hook`
          or `skill-recall.hook` span with an `embed` child, carrying the score,
          match counts, tokens and whether it fell back or failed.
        '';
      };

      tenantId = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "X-Scope-OrgID sent to Loki and Tempo, for a multi-tenant setup.";
      };

      headersFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "/run/user/1000/secrets/otel-headers";
        description = ''
          Path of a file of extra HTTP headers for Loki and Tempo, one `Name: value`
          per line (`Authorization: Bearer ...`), read when sending. It is a string,
          not a path literal, so the secret is never copied into the Nix store; point
          it at a sops-nix secret.
        '';
      };

      labels = mkOption {
        type = types.attrsOf types.str;
        default = { };
        example = { host = "desk"; };
        description = "Extra Loki labels and span resource attributes.";
      };
    };

    logFile = mkOption {
      type = types.nullOr types.str;
      default = "${config.xdg.stateHome}/memory-recall/recall.jsonl";
      description = ''
        One JSON line per prompt: best score, matches, how many in full and
        tokens added. Never the prompt. Summarise it with
        `memory-recall log-summary <file>`. Null turns logging off.
      '';
    };

    skills = {
      enable = mkEnableOption "injecting the skill sections closest to each prompt (skill-recall)";

      root = mkOption {
        type = types.str;
        default = "${config.home.homeDirectory}/.claude/skills";
        description = "Directory with one folder per skill.";
      };

      top = mkOption {
        type = types.ints.positive;
        default = 3;
        description = "Most skill sections injected per prompt.";
      };

      minScore = mkOption {
        type = types.float;
        default = 0.72;
        description = ''
          Cosine similarity a skill section must reach to be injected in full.
          Skill scores overlap more than memory scores. At 512 dimensions and 0.72
          the right section is among the top 3 for 80 to 85% of queries and 27% of
          off-topic prompts get an injection (220 to 300 tokens a prompt on
          average); sections between pointerScore and this are one-line pointers.
        '';
      };

      pointerScore = mkOption {
        type = types.nullOr types.float;
        default = 0.66;
        description = ''
          A section scoring from here up to minScore is injected as a one-line
          pointer (path, score, first line) for the model to open if it applies,
          about 30 tokens each; only minScore and above are injected in full. At
          512 dimensions the right section is among the top 3 for 87 to 90% of
          queries from 0.66. null injects nothing below minScore.
        '';
      };

      sectionChars = mkOption {
        type = types.ints.positive;
        default = 3000;
        description = "Longest section injected, in characters (about 750 tokens).";
      };

      maxTokens = mkOption {
        type = types.ints.positive;
        default = 1500;
        description = ''
          Most tokens the skills hook adds to one prompt; lower-ranked sections are
          dropped past it. With the memory hook's own maxTokens the two stay under
          3,000 tokens together, less than the names-only catalogue saves.
        '';
      };
    };
  };

  config = mkIf cfg.enable (lib.mkMerge [
    {
    assertions = [
      {
        assertion = cfg.memoryDir != null;
        message = "modules.memoryRecall.memoryDir must be set when memory recall is enabled.";
      }
      {
        assertion = isLinux || isDarwin;
        message = "modules.memoryRecall runs its server as a systemd user unit (Linux) or a launchd agent (macOS).";
      }
    ];

    home.packages = [ cfg.package ];

    # The unit starts llama-server with these flags and restarts it when it exits.
    # A flag the pinned llama.cpp rejects (--mlock was one) crash-loops it, and every
    # prompt then blocks. `--version` parses the arguments and exits without loading
    # the model, so a bad list stops the switch before anything is written.
    home.activation.memoryRecallServerFlags = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
      if ! server_flags_out=$(${lib.escapeShellArgs serverArgv} --version 2>&1); then
        echo "memory-recall: llama-server rejects the embedding server's flags; the unit would crash-loop and every prompt would block:" >&2
        echo "$server_flags_out" >&2
        exit 1
      fi
    '';

    # Appended to the hooks in home/programs/claude-code, the way claude-monitor
    # adds its own. 12 s is above the binary's own 8 s request timeout.
    programs.claude-code.settings.hooks.UserPromptSubmit = [
      {
        hooks = [
          {
            type = "command";
            command = "${hookScript}";
            timeout = 12;
          }
        ] ++ lib.optional cfg.skills.enable {
          type = "command";
          command = "${skillsHookScript}";
          timeout = 12;
        };
      }
    ];
    }

    (mkIf isLinux {
    systemd.user.services.memory-recall-server = {
      Unit.Description = "Embedding server for memory-recall";
      Service = {
        ExecStart = lib.concatStringsSep " " serverArgv;
        Restart = "always";
        RestartSec = 2;
        # A prompt waits for this server, and a hook that gets no answer blocks it.
        # On a busy desktop (a game, a browser, a build) the kernel swapped the
        # server out, and paging it back in took longer than the hook waited. So it
        # may not swap, its pages are locked (--load-mode mmap+mlock) and protected from reclaim,
        # and it runs at normal priority with extra CPU weight: it is ~300 MB and
        # embeds a prompt in ~20 ms, so this costs the rest of the system nothing.
        MemorySwapMax = 0;
        MemoryLow = "1G";
        CPUWeight = 200;
      };
      Install.WantedBy = [ "default.target" ];
    };

    systemd.user.services.memory-recall-index = {
      Unit.Description = "Refresh the memory-recall vector cache";
      Service = {
        Type = "oneshot";
        # Starts and stops its own embedding server; it does not need the query one.
        ExecStart = "${indexScript}/bin/memory-recall-index";
        # That server embeds with several threads for up to ~90 s on the first
        # index: at the default priority it could starve a real-time audio session.
        Nice = 10;
      };
      # Builds the cache at login; the path unit below keeps it fresh.
      Install.WantedBy = [ "default.target" ];
    };

    systemd.user.paths.memory-recall-index = {
      Unit.Description = "Reindex memories and skills when one changes";
      Path = {
        # Not recursive: a new skill folder is seen at once, an edit inside one
        # on the next login or index run.
        PathChanged = [ cfg.memoryDir ] ++ lib.optional cfg.skills.enable cfg.skills.root;
        Unit = "memory-recall-index.service";
      };
      Install.WantedBy = [ "default.target" ];
    };
    })

    # macOS has no systemd: the server is a launchd agent kept alive, and the
    # index agent runs at login and whenever a watched directory changes.
    (mkIf isDarwin {
      launchd.agents.memory-recall-server = {
        enable = true;
        config = {
          ProgramArguments = serverArgv;
          RunAtLoad = true;
          KeepAlive = true;
          ProcessType = "Background";
          Nice = 10;
          StandardOutPath = "${stateDir}/server.log";
          StandardErrorPath = "${stateDir}/server.log";
        };
      };

      launchd.agents.memory-recall-index = {
        enable = true;
        config = {
          ProgramArguments = [ "${indexScript}/bin/memory-recall-index" ];
          RunAtLoad = true;
          # Not recursive, like the Linux path unit: a new skill folder is seen at
          # once, an edit inside one on the next login or index run.
          WatchPaths = [ cfg.memoryDir ] ++ lib.optional cfg.skills.enable cfg.skills.root;
          ProcessType = "Background";
          Nice = 10;
          StandardOutPath = "${stateDir}/index.log";
          StandardErrorPath = "${stateDir}/index.log";
        };
      };

      # launchd will not create the log directory.
      home.activation.memoryRecallStateDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run mkdir -p ${lib.escapeShellArg stateDir}
      '';
    })
  ]);
}
