{ config, lib, ... }:
let
  cfg = config.modules.ollama;
in
{
  options.modules.ollama = {
    enable = lib.mkEnableOption "ollama service";
    acceleration = lib.mkOption {
      type = lib.types.str;
      default = "rocm";
      description = "GPU acceleration type for Ollama";
    };
  };

  config = lib.mkIf cfg.enable {
    services = {
      ollama = {
        enable = true;
        acceleration = cfg.acceleration;
        user = "ollama";
        group = "ollama";
      };
    };
  };
}
