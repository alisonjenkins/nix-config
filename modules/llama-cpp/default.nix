{ config, lib, pkgs, ... }:
let
  cfg = config.modules.llama-cpp;
in
{
  options.modules.llama-cpp = {
    enable = lib.mkEnableOption "llama.cpp server";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.llama-cpp;
      description = "llama-cpp package variant (e.g. pkgs.llama-cpp, pkgs.llama-cpp-rocm, pkgs.llama-cpp-vulkan)";
    };
    model = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to the GGUF model file. Service won't start until set.";
      example = "/models/qwen2.5-coder-32b-instruct-q4_k_m.gguf";
    };
    host = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Listen address for llama-server";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Listen port for llama-server";
    };
    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra CLI flags passed to llama-server (e.g. --gpu-layers, --ctx-size)";
    };
    allowedIPs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        List of IPs/CIDRs allowed to connect. When empty, only localhost can
        reach the server (the NixOS firewall's default DROP policy blocks
        everything else). Example: ["100.127.142.30" "192.168.1.0/24"]
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.llama-cpp = lib.mkIf (cfg.model != null) {
      enable = true;
      package = cfg.package;
      model = cfg.model;
      host = cfg.host;
      port = cfg.port;
      extraFlags = cfg.extraFlags;
    };

    networking.firewall.extraCommands = lib.mkIf (cfg.model != null && cfg.allowedIPs != [ ]) (
      lib.concatMapStringsSep "\n" (ip:
        "iptables -A nixos-fw -p tcp --dport ${toString cfg.port} -s ${ip} -j nixos-fw-accept"
      ) cfg.allowedIPs
    );

    environment.persistence.${config.modules.base.impermanencePersistencePath}.directories =
      lib.mkIf config.modules.base.enableImpermanence [
        {
          directory = "/var/lib/private/llama-cpp";
          mode = "0700";
        }
      ];
  };
}
