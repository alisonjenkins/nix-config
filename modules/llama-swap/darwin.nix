{ config, lib, pkgs, ... }:
let
  cfg = config.modules.llamaSwap;

  llamaServerBin = lib.getExe' cfg.llamaCppPackage "llama-server";
  llamaSwapBin = lib.getExe' cfg.package "llama-swap";

  # Build the `cmd` string llama-swap runs to spawn a llama-server child for one
  # model. llama-swap injects the listening port via the ${PORT} macro. Flash
  # attention is left at llama.cpp's `auto` default (enables itself on Metal),
  # so no version-fragile flag is passed.
  mkCmd = m: lib.concatStringsSep " " (
    [
      llamaServerBin
      "--model" m.modelFile
      "--n-gpu-layers" "99"        # offload all layers to the Metal GPU
      "--jinja"                    # Qwen3 chat template + tool-calling
      "--host" "127.0.0.1"
      "--port" "\${PORT}"
      "--ctx-size" (toString m.contextSize)
    ]
    ++ lib.optionals (m.draftModelFile != null) [
      "--model-draft" m.draftModelFile
      "--gpu-layers-draft" "99"    # speculative-decoding draft on GPU too
    ]
    ++ m.extraFlags
  );

  # One llama-swap model entry per configured model. `ttl` unloads the spawned
  # llama-server after the configured idle period (the idle-unload behaviour);
  # llama-swap itself stays resident under launchd.
  swapConfig = {
    models = lib.mapAttrs (_name: m: {
      cmd = mkCmd m;
      ttl = cfg.idleTimeout;
    }) cfg.models;
  };

  configFile = (pkgs.formats.yaml { }).generate "llama-swap.yaml" swapConfig;

  modelType = lib.types.submodule {
    options = {
      modelFile = lib.mkOption {
        type = lib.types.path;
        description = "Path to the GGUF model file llama-server should load.";
      };
      draftModelFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Optional GGUF draft model for speculative decoding. Must share the
          target model's tokenizer. Worth it for dense models; leave null for
          fast MoE models that need no draft.
        '';
      };
      contextSize = lib.mkOption {
        type = lib.types.int;
        default = 32768;
        description = "Context window (`--ctx-size`) for this model.";
      };
      extraFlags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra flags appended to the llama-server command for this model.";
      };
    };
  };
in
{
  options.modules.llamaSwap = {
    enable = lib.mkEnableOption "llama-swap OpenAI-compatible model-swapping proxy (Metal llama.cpp)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.llama-swap;
      defaultText = lib.literalExpression "pkgs.llama-swap";
      description = "The llama-swap package to run.";
    };

    llamaCppPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.llama-cpp;
      defaultText = lib.literalExpression "pkgs.llama-cpp";
      description = ''
        The llama.cpp package providing `llama-server`. On aarch64-darwin
        nixpkgs builds this with Metal acceleration by default.
      '';
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address llama-swap listens on.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port llama-swap listens on. The OpenAI-compatible API is served here.";
    };

    idleTimeout = lib.mkOption {
      type = lib.types.int;
      default = 300;
      description = ''
        Seconds a spawned llama-server child stays loaded after its last
        request before llama-swap unloads it (frees GPU/unified memory). The
        llama-swap proxy itself stays resident.
      '';
    };

    logFile = lib.mkOption {
      type = lib.types.str;
      default = "/tmp/llama-swap.log";
      description = "Absolute path for the launchd agent's stdout/stderr log.";
    };

    models = lib.mkOption {
      type = lib.types.attrsOf modelType;
      default = { };
      description = ''
        Models llama-swap can serve, keyed by the name clients request in the
        OpenAI `model` field. llama-swap loads one on demand and swaps between
        them automatically, so only one is resident at a time.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # User agent (not a system daemon): the service is per-user, needs no root,
    # and the model store paths are user-readable. KeepAlive keeps the
    # lightweight proxy resident; the heavy llama-server children are spawned on
    # demand and unloaded after `ttl`.
    launchd.user.agents.llama-swap.serviceConfig = {
      Label = "org.nixos.llama-swap";
      ProgramArguments = [
        llamaSwapBin
        "--config" "${configFile}"
        "--listen" "${cfg.host}:${toString cfg.port}"
      ];
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = cfg.logFile;
      StandardErrorPath = cfg.logFile;
    };
  };
}
