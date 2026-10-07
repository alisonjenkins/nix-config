# Semantic recall of Claude memory files (scripts/retrieval-eval): a
# UserPromptSubmit hook injects the few memories closest to each prompt, backed
# by a local EmbeddingGemma 2 server. See docs/memory-recall.md.
{ config, lib, pkgs, ... }:
let
  cfg = config.modules.memoryRecall;
  inherit (lib) mkOption mkEnableOption mkIf types;

  baseUrl = "http://127.0.0.1:${toString cfg.port}";
  cacheFile = "${config.xdg.cacheHome}/memory-recall/gemma-${toString cfg.dims}.json";

  recall = lib.concatStringsSep " " [
    "${cfg.package}/bin/memory-recall"
    "--memory-dir ${lib.escapeShellArg cfg.memoryDir}"
    "--embedder ${lib.escapeShellArg "gemma=gemma@${baseUrl}#${toString cfg.dims}"}"
    "--cache ${lib.escapeShellArg cacheFile}"
  ];

  logArgs = lib.optionalString (cfg.logFile != null) " --log ${lib.escapeShellArg cfg.logFile}";

  hookScript = pkgs.writeShellScript "memory-recall-hook" ''
    exec ${recall} hook --top ${toString cfg.top} --min-score ${toString cfg.minScore} \
      --body-score ${toString cfg.bodyScore} --inject ${cfg.inject}${logArgs}
  '';

  # The first index embeds every memory (~70 s on CPU), so wait for the server
  # to come up instead of failing the unit on a cold login.
  indexScript = pkgs.writeShellApplication {
    name = "memory-recall-index";
    runtimeInputs = [ pkgs.coreutils pkgs.curl ];
    text = ''
      mkdir -p "$(dirname ${lib.escapeShellArg cacheFile})"
      for _ in $(seq 1 60); do
        curl -fsS --max-time 2 ${baseUrl}/health >/dev/null && break
        sleep 2
      done
      exec ${recall} index
    '';
  };

  serverArgs = [
    "${cfg.llamaCpp}/bin/llama-server"
    "-m ${cfg.model}"
    "--embeddings"
    "-c 2048"
    "-ub 2048"
    "-ngl 0"
    "--host 127.0.0.1"
    "--port ${toString cfg.port}"
  ] ++ lib.optional (cfg.threads != null) "--threads ${toString cfg.threads}";
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
      default = 256;
      description = ''
        Matryoshka dimensions kept per vector. Changing it, or the model,
        invalidates the vector cache and the score threshold: re-measure
        minScore (docs/memory-recall.md).
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
        one-line snippet. The right memory's best score ran 0.70 to 0.87 over 58
        queries, so this leans to recall; a stray snippet costs about 35 tokens.
        Measured for EmbeddingGemma 2 at 256 dimensions.
      '';
    };

    bodyScore = mkOption {
      type = types.float;
      default = 0.76;
      description = ''
        With `inject = "auto"`, the score from which a memory is injected in
        full (about 1,000 tokens) so the model answers without opening the file.
        Higher than minScore because a wrong full memory is the expensive mistake.
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

    logFile = mkOption {
      type = types.nullOr types.str;
      default = "${config.xdg.stateHome}/memory-recall/recall.jsonl";
      description = ''
        One JSON line per prompt: best score, matches, how many in full and
        tokens added. Never the prompt. Summarise it with
        `memory-recall log-summary <file>`. Null turns logging off.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.memoryDir != null;
        message = "modules.memoryRecall.memoryDir must be set when memory recall is enabled.";
      }
      {
        assertion = pkgs.stdenv.hostPlatform.isLinux;
        message = "modules.memoryRecall needs systemd user units, so it is Linux-only.";
      }
    ];

    home.packages = [ cfg.package ];

    # Appended to the hooks in home/programs/claude-code, the way claude-monitor
    # adds its own. 5 s is above the binary's own 3 s request timeout.
    programs.claude-code.settings.hooks.UserPromptSubmit = [
      {
        hooks = [
          {
            type = "command";
            command = "${hookScript}";
            timeout = 5;
          }
        ];
      }
    ];

    systemd.user.services.memory-recall-server = {
      Unit.Description = "Embedding server for memory-recall";
      Service = {
        ExecStart = lib.concatStringsSep " " serverArgs;
        Restart = "on-failure";
        RestartSec = 5;
        # Embeds a prompt in ~20 ms, so it never needs to win against a game.
        Nice = 10;
      };
      Install.WantedBy = [ "default.target" ];
    };

    systemd.user.services.memory-recall-index = {
      Unit = {
        Description = "Refresh the memory-recall vector cache";
        After = [ "memory-recall-server.service" ];
        Wants = [ "memory-recall-server.service" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${indexScript}/bin/memory-recall-index";
        # Embedding every memory makes llama.cpp keep its largest compute
        # buffer: the server grows from ~425 MB to ~2.7 GB and never gives it
        # back. Restarting it after an index returns it to ~425 MB; hooks that
        # land in the second it takes inject nothing.
        ExecStartPost = "${pkgs.systemd}/bin/systemctl --user try-restart memory-recall-server.service";
      };
      # Builds the cache at login; the path unit below keeps it fresh.
      Install.WantedBy = [ "default.target" ];
    };

    systemd.user.paths.memory-recall-index = {
      Unit.Description = "Reindex memories when a memory file changes";
      Path = {
        PathChanged = cfg.memoryDir;
        Unit = "memory-recall-index.service";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
