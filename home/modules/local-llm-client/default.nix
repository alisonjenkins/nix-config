# Points the delegation skill's scripts at a llama-swap endpoint (local or on
# another machine, see modules/llama-swap/nixos.nix).
{ config, lib, ... }:
let
  cfg = config.modules.localLlmClient;
in
{
  options.modules.localLlmClient = {
    enable = lib.mkEnableOption "environment for the delegation scripts' local LLM endpoint";

    url = lib.mkOption {
      type = lib.types.str;
      example = "http://127.0.0.1:8080";
      description = "Base URL of the OpenAI-compatible endpoint.";
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "fast";
      description = "Model id requested from the endpoint.";
    };

    context = lib.mkOption {
      type = lib.types.int;
      description = "Context window in tokens of the chosen model; the agent script budgets against it.";
    };

    apiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/llama-swap-api-key";
      description = "Runtime path of the endpoint's API key. Only the path is exported, never the key.";
    };

    chatTimeout = lib.mkOption {
      type = lib.types.int;
      default = 900;
      description = "Seconds to wait for one chat completion.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.sessionVariables = {
      LOCAL_LLM_URL = cfg.url;
      LOCAL_LLM_MODEL = cfg.model;
      LOCAL_LLM_CONTEXT = toString cfg.context;
      LOCAL_LLM_CHAT_TIMEOUT = toString cfg.chatTimeout;
    } // lib.optionalAttrs (cfg.apiKeyFile != null) {
      LOCAL_LLM_API_KEY_FILE = cfg.apiKeyFile;
    };
  };
}
