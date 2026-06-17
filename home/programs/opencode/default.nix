{ ... }:
let
  mkProvider = { baseURL, models }:
    {
      api = "openai";
      inherit baseURL;
      inherit models;
    };

  mkModel = { name, toolCall ? true, reasoning ? true, attachment ? true }: {
    inherit name attachment toolCall reasoning;
  };
in
{
  xdg.configFile."opencode/config.json".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";

    provider = {
      local-orchestrator = mkProvider {
        baseURL = "http://localhost:8080/v1";
        models.qwen3-5-122b = mkModel {
          name = "Qwen3.5-122B-A10B";
        };
      };

      local-coder = mkProvider {
        baseURL = "http://localhost:8081/v1";
        models.qwen3-coder-30b = mkModel {
          name = "Qwen3-Coder-30B-A3B";
        };
      };

      local-agent = mkProvider {
        baseURL = "http://localhost:8082/v1";
        models.qwen3-6-35b = mkModel {
          name = "Qwen3.6-35B-A3B";
        };
      };
    };

    model = {
      coder = "local-coder/qwen3-coder-30b";
      task = "local-agent/qwen3-6-35b";
    };
  };
}
